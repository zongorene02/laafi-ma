"""Contenu `sourced` (OMS, UNFPA, relu par aucune sage-femme) : caché par
défaut, servi avec `provisional: true` si SERVE_SOURCED_CONTENT=true, validé ou
renvoyé en brouillon comme un autre contenu, et servi en français quand la
langue demandée n'a pas de texte."""

import io
import os
import subprocess
import sys
from pathlib import Path

import pytest
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session

from app.config import settings
from app.content import served_statuses
from app.db_models import Capsule, DangerSign, HelpService, KbEntry
from app.matching import best_match, normalize_question
from app.routers.assistant import kb_candidates
from app.seed import seed
from app.seed_content import CAPSULES, KB_ENTRIES

SERVICE_DIR = Path(__file__).resolve().parent.parent
QUESTION = KB_ENTRIES[0]["translations"]["fr"]["question"]
ANSWER = KB_ENTRIES[0]["translations"]["fr"]["answer"]
SOURCE = KB_ENTRIES[0]["source"]


@pytest.fixture
def serve_sourced(monkeypatch) -> None:
    monkeypatch.setattr(settings, "serve_sourced_content", True)


def _ask(client, text, lang="fr"):
    return client.post("/assistant/ask-text", json={"text": text, "lang": lang}).json()


def _entry(db, seed_key=None) -> KbEntry:
    return db.scalar(select(KbEntry).where(KbEntry.seed_key == (seed_key or KB_ENTRIES[0]["seed_key"])))


def _capsule(db) -> Capsule:
    return db.scalar(select(Capsule).where(Capsule.seed_key == CAPSULES[0]["seed_key"]))


def _sign(db, seed_key="grossesse-saignement") -> DangerSign:
    return db.scalar(select(DangerSign).where(DangerSign.seed_key == seed_key))


def _stored_id(item) -> str:
    return str(item.id)


# --- Réglage désactivé : rien ne change ---------------------------------------


def test_served_statuses_depend_on_the_setting(monkeypatch):
    assert served_statuses() == ("validated",)
    monkeypatch.setattr(settings, "serve_sourced_content", True)
    assert served_statuses() == ("validated", "sourced")


def test_sourced_content_is_hidden_without_the_setting(client, db, models_loaded):
    seed(db)
    assert _ask(client, QUESTION)["matched"] is False
    assert _ask(client, "je saigne")["danger"] is False
    assert client.get("/assistant/faq").json()["entries"] == []
    assert client.get("/assistant/danger-signs").json() == []
    assert client.get("/learn/capsules").json() == []
    # Pas de synthèse non plus : une URL devinée répond 404.
    entry = _entry(db)
    from app import audio_store

    path = audio_store.synthetic_relative_path("kb", entry.id, "fr", ANSWER)
    assert client.get(f"/media/{path}").status_code == 404


# --- Réglage activé : servi et signalé ----------------------------------------


def test_sourced_answer_is_served_as_provisional(client, db, serve_sourced):
    seed(db)
    body = _ask(client, QUESTION)
    assert body["matched"] is True
    assert body["entry"]["answer"] == ANSWER
    assert body["entry"]["provisional"] is True
    assert body["entry"]["source"] == SOURCE


def test_sourced_faq_and_capsules_are_provisional(client, db, serve_sourced):
    seed(db)
    faq = client.get("/assistant/faq").json()["entries"]
    assert len(faq) == len(KB_ENTRIES)
    assert all(e["provisional"] is True and e["source"] for e in faq)

    capsules = client.get("/learn/capsules").json()
    assert len(capsules) == len(CAPSULES)
    assert all(c["provisional"] is True and c["status"] == "sourced" for c in capsules)
    assert all("source" not in c for c in capsules)  # pas de colonne source sur les capsules


def test_danger_detection_fires_on_sourced_signs(client, db, serve_sourced):
    seed(db)
    body = _ask(client, "je saigne")
    assert body["danger"] is True
    (hit,) = body["danger_signs"]
    assert hit["label"] == "Saignement pendant la grossesse"
    assert hit["advice"] == "Allez tout de suite au centre de santé, de jour comme de nuit, sans attendre."
    assert hit["provisional"] is True
    assert hit["source"].startswith("OMS, Pregnancy")


@pytest.mark.parametrize(
    ("text", "label"),
    [
        ("mon bébé ne tète plus", "Le bébé n'arrive pas à téter"),
        ("il n'arrive pas à téter", "Le bébé n'arrive pas à téter"),
        ("mon bébé a le corps froid", "Le bébé a le corps froid"),
        ("le bébé très mou", "Le bébé bouge beaucoup moins"),
    ],
)
def test_baby_danger_signs_are_detected(client, db, serve_sourced, text, label):
    seed(db)
    assert label in [s["label"] for s in _ask(client, text)["danger_signs"]]


def test_public_danger_signs_serve_the_sourced_aid(client, db, serve_sourced):
    seed(db)
    signs = client.get("/assistant/danger-signs").json()
    assert len(signs) == 13
    assert all(s["provisional"] is True and s["source"] for s in signs)
    assert all(s["refer_when"] == "Orienter tout de suite vers le centre de santé." for s in signs)


def test_speech_synthesis_accepts_sourced_text(client, db, serve_sourced, models_loaded):
    seed(db)
    body = _ask(client, QUESTION)
    assert body["entry"]["audio_kind"] == "synthetic"
    assert client.get(body["entry"]["audio_url"]).status_code == 200


def test_capsule_synthesis_accepts_sourced_text(client, db, serve_sourced, models_loaded):
    seed(db)
    (capsule, *_) = client.get("/learn/capsules", params={"track": CAPSULES[0]["track"]}).json()
    assert client.get(capsule["translations"]["fr"]["audio_url"]).status_code == 200


# --- Circuit de validation ----------------------------------------------------


def test_validation_turns_sourced_into_validated(client, db, validator_headers, serve_sourced):
    seed(db)
    entry_id = _stored_id(_entry(db))
    validated = client.post(f"/kb/entries/{entry_id}/validate", headers=validator_headers).json()
    assert validated["status"] == "validated"
    assert validated["validated_by"] is not None
    body = _ask(client, QUESTION)
    assert body["entry"]["id"] == entry_id
    assert body["entry"]["provisional"] is False


def test_validated_item_stays_served_without_the_setting(client, db, validator_headers):
    seed(db)
    sign_id = _stored_id(_sign(db))
    client.post(f"/kb/danger-signs/{sign_id}/validate", headers=validator_headers)
    (hit,) = _ask(client, "je saigne")["danger_signs"]
    assert hit["provisional"] is False


def test_validating_a_sourced_sign_and_capsule(client, db, validator_headers, serve_sourced):
    seed(db)
    capsule_id = _stored_id(_capsule(db))
    sign_id = _stored_id(_sign(db))
    assert (
        client.post(f"/learn/capsules/{capsule_id}/validate", headers=validator_headers).json()["provisional"] is False
    )
    assert (
        client.post(f"/kb/danger-signs/{sign_id}/validate", headers=validator_headers).json()["status"] == "validated"
    )


def test_validation_of_sourced_keeps_the_409_rule(client, db, validator_headers):
    seed(db)
    entry = _entry(db)
    entry.translations = {"fr": {"question": "", "variants": [], "answer": ""}}
    db.commit()
    assert client.post(f"/kb/entries/{entry.id}/validate", headers=validator_headers).status_code == 409


def test_editing_a_sourced_entry_sets_it_to_draft(client, db, validator_headers, serve_sourced):
    seed(db)
    entry = _entry(db)
    fr = KB_ENTRIES[0]["translations"]["fr"]
    payload = {
        "topic": entry.topic,
        "is_danger_topic": entry.is_danger_topic,
        "source": entry.source,
        "translations": {"fr": {**fr, "answer": "Réponse modifiée."}},
    }
    edited = client.put(f"/kb/entries/{entry.id}", json=payload, headers=validator_headers).json()
    assert edited["status"] == "draft"
    faq = client.get("/assistant/faq").json()["entries"]
    assert edited["id"] not in [e["id"] for e in faq]


def test_saving_a_sourced_entry_unchanged_keeps_its_status(client, db, validator_headers):
    """Un « Enregistrer » sans changement ne doit pas sortir l'entrée du circuit."""
    seed(db)
    entry = _entry(db)
    payload = {
        "topic": entry.topic,
        "is_danger_topic": entry.is_danger_topic,
        "source": entry.source,
        "translations": {"fr": KB_ENTRIES[0]["translations"]["fr"]},
    }
    assert client.put(f"/kb/entries/{entry.id}", json=payload, headers=validator_headers).json()["status"] == "sourced"


def test_editing_a_sourced_capsule_and_sign_sets_them_to_draft(client, db, validator_headers, serve_sourced):
    seed(db)
    capsule = _capsule(db)
    item = CAPSULES[0]
    same = {"track": item["track"], "order": item["order"], "translations": item["translations"], "quiz": item["quiz"]}
    unchanged = client.put(f"/learn/capsules/{capsule.id}", json=same, headers=validator_headers).json()
    assert unchanged["status"] == "sourced"
    changed = {**same, "order": item["order"] + 50}
    assert (
        client.put(f"/learn/capsules/{capsule.id}", json=changed, headers=validator_headers).json()["status"] == "draft"
    )

    sign = _sign(db)
    payload = {
        "translations": {"fr": {"label": "Saignement", "advice": "Conseil modifié."}},
        "keywords_fr": sign.keywords_fr,
        "source": sign.source,
    }
    assert (
        client.put(f"/kb/danger-signs/{sign.id}", json=payload, headers=validator_headers).json()["status"] == "draft"
    )


def test_staff_filters_accept_sourced(client, db, validator_headers, admin_headers):
    seed(db)
    entries = client.get("/kb/entries", params={"status": "sourced"}, headers=validator_headers).json()
    assert len(entries) == len(KB_ENTRIES)
    signs = client.get("/kb/danger-signs", params={"status": "sourced"}, headers=validator_headers).json()
    assert len(signs) == 13
    capsules = client.get("/learn/capsules", params={"status": "sourced"}, headers=validator_headers).json()
    assert len(capsules) == len(CAPSULES)

    stats = client.get("/admin/stats", headers=admin_headers).json()
    assert stats["kb"]["sourced"] == len(KB_ENTRIES)
    assert stats["capsules"]["sourced"] == len(CAPSULES)


# --- Repli sur le français ----------------------------------------------------


def test_moore_request_gets_the_french_text_everywhere(client, db, serve_sourced, models_loaded):
    seed(db)
    models_loaded["to_french"]["question en moore"] = QUESTION
    body = _ask(client, "question en moore", lang="mos")
    assert body["entry"]["answer"] == ANSWER
    assert body["entry"]["provisional"] is True
    assert "_fr_" in body["entry"]["audio_url"]  # voix française pour un texte français

    faq = client.get("/assistant/faq", params={"lang": "mos"}).json()["entries"]
    assert len(faq) == len(KB_ENTRIES)
    assert all(e["answer"] for e in faq)
    assert ANSWER in [e["answer"] for e in faq]

    (sign, *_) = client.get("/assistant/danger-signs", params={"lang": "dyu"}).json()
    assert sign["label"] and sign["advice"]

    capsules = client.get("/learn/capsules", params={"lang": "mos"}).json()
    assert len(capsules) == len(CAPSULES)
    assert all(c["translations"]["fr"]["text"] for c in capsules)

    models_loaded["to_french"]["je saigne en moore"] = "je saigne"
    (hit,) = _ask(client, "je saigne en moore", lang="dyu")["danger_signs"]
    assert hit["advice"]


# --- Rapprochement sur le contenu de seed_content.py --------------------------


def _phrasings():
    for item in KB_ENTRIES:
        fr = item["translations"]["fr"]
        for phrasing in [fr["question"], *fr["variants"]]:
            yield item["seed_key"], phrasing


def _candidates():
    return kb_candidates(KbEntry(id=item["seed_key"], translations=item["translations"]) for item in KB_ENTRIES)


@pytest.mark.parametrize(("seed_key", "phrasing"), list(_phrasings()))
def test_every_phrasing_matches_its_own_entry(seed_key, phrasing):
    match = best_match(phrasing, _candidates())
    assert match is not None
    assert match.entry_id == seed_key
    assert match.confidence >= settings.assistant_min_confidence


def test_no_two_entries_collide():
    """Deux entrées ne partagent aucune formulation une fois normalisée (mots
    vides retirés) : sinon le rapprochement ne pourrait pas les départager."""
    owners: dict[str, set[str]] = {}
    for seed_key, phrasing in _phrasings():
        owners.setdefault(normalize_question(phrasing), set()).add(seed_key)
    assert {text: keys for text, keys in owners.items() if len(keys) > 1} == {}


def test_seed_keys_are_unique():
    keys = [item["seed_key"] for item in [*KB_ENTRIES, *CAPSULES]]
    assert len(keys) == len(set(keys))


# --- `python -m app.seed` sur une base neuve ----------------------------------


def test_seed_module_twice_on_a_clean_database_adds_nothing(tmp_path):
    url = f"sqlite:///{(tmp_path / 'seed.db').as_posix()}"
    env = {**os.environ, "DATABASE_URL": url, "LOAD_MODELS_ON_STARTUP": "false", "PYTHONIOENCODING": "utf-8"}
    python = sys.executable
    subprocess.run([python, "-m", "alembic", "upgrade", "head"], cwd=SERVICE_DIR, env=env, check=True)
    first = subprocess.run(
        [python, "-m", "app.seed"], cwd=SERVICE_DIR, env=env, check=True, capture_output=True, encoding="utf-8"
    )
    assert "4 service(s)" in first.stdout and "13 signe(s)" in first.stdout

    engine = create_engine(url)

    def counts() -> list[int]:
        with Session(engine) as db:
            return [
                db.scalar(select(func.count()).select_from(m)) or 0 for m in (HelpService, DangerSign, KbEntry, Capsule)
            ]

    assert counts() == [4, 13, len(KB_ENTRIES), len(CAPSULES)]
    second = subprocess.run(
        [python, "-m", "app.seed"], cwd=SERVICE_DIR, env=env, check=True, capture_output=True, encoding="utf-8"
    )
    assert "0 service(s)" in second.stdout and "0 signe(s)" in second.stdout
    assert counts() == [4, 13, len(KB_ENTRIES), len(CAPSULES)]
    engine.dispose()


def test_audio_upload_on_sourced_sets_draft(client, db, validator_headers, models_loaded):
    seed(db)
    entry = _entry(db)
    response = client.post(
        f"/kb/entries/{entry.id}/audio/fr",
        files={"audio": ("voix.wav", io.BytesIO(b"wav"), "audio/wav")},
        headers=validator_headers,
    )
    assert response.json()["status"] == "draft"


@pytest.mark.parametrize(
    ("question", "expected"),
    [
        ("je saigne beaucoup et je suis enceinte", "kb-signes-danger-grossesse"),
        ("j'ai accouché hier et je saigne beaucoup", "kb-saignement-apres-accouchement"),
        ("j'ai de la fièvre et je suis enceinte", "kb-signes-danger-grossesse"),
    ],
)
def test_danger_question_gets_a_danger_answer(client, db, serve_sourced, question, expected):
    seed(db)
    body = client.post("/assistant/ask-text", json={"text": question, "lang": "fr"}).json()
    assert body["danger"] is True
    entry = db.scalar(select(KbEntry).where(KbEntry.seed_key == expected))
    assert body["entry"]["id"] == entry.id


def test_danger_question_never_gets_a_routine_answer_by_resemblance(client, db, serve_sourced):
    seed(db)
    routine = {e.id for e in db.scalars(select(KbEntry)) if not e.is_danger_topic}
    for question in ["je saigne", "je perds du sang", "j'ai des saignements depuis ce matin"]:
        body = client.post("/assistant/ask-text", json={"text": question, "lang": "fr"}).json()
        assert body["danger"] is True, question
        assert body["entry"] is None or body["entry"]["id"] not in routine, question


def test_exact_routine_question_stays_answered_despite_the_danger_keyword(client, db, serve_sourced):
    seed(db)
    body = client.post(
        "/assistant/ask-text", json={"text": "je saigne beaucoup pendant les règles", "lang": "fr"}
    ).json()
    entry = db.scalar(select(KbEntry).where(KbEntry.seed_key == "kb-regles-douleur"))
    assert body["entry"]["id"] == entry.id


def test_seed_refreshes_sourced_entries_but_not_edited_ones(db):
    seed(db)
    sourced = db.scalar(select(KbEntry).where(KbEntry.seed_key == "kb-anemie"))
    edited = db.scalar(select(KbEntry).where(KbEntry.seed_key == "kb-fistule"))
    sourced.translations = {"fr": {"question": "vieux", "answer": "vieux", "variants": []}}
    edited.translations = {"fr": {"question": "relu", "answer": "relu", "variants": []}}
    edited.status = "draft"
    db.commit()
    seed(db)
    db.refresh(sourced)
    db.refresh(edited)
    assert sourced.translations["fr"]["question"] != "vieux"
    assert edited.translations["fr"]["question"] == "relu"
