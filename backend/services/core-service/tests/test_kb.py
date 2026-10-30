"""Base de connaissances : rôles, circuit de validation (toute modification
renvoie en brouillon), audio humain, traduction automatique, signes de
danger, questions sans réponse."""

import copy
import io

import pytest
from helpers import DANGER_BLEEDING, KB_NUTRITION, create_danger_sign, create_kb_entry, validated_kb_entry

from app.db_models import DangerSign, UnansweredQuestion


@pytest.mark.parametrize("path", ["/kb/entries", "/kb/danger-signs", "/kb/unanswered"])
def test_kb_is_reserved_to_validators_and_admins(client, woman, agent_headers, admin_headers, path):
    assert client.get(path).status_code == 401
    assert client.get(path, headers=woman["headers"]).status_code == 403
    assert client.get(path, headers=agent_headers).status_code == 403
    assert client.get(path, headers=admin_headers).status_code == 200


def test_a_new_entry_is_a_draft_with_all_three_languages(client, validator_headers):
    entry = create_kb_entry(client, validator_headers)
    assert entry["status"] == "draft"
    assert entry["validated_by"] is None
    assert set(entry["translations"]) == {"fr", "mos", "dyu"}
    assert entry["translations"]["dyu"] == {
        "question": "",
        "variants": [],
        "answer": "",
        "audio_url": None,
        "audio_kind": None,
        "machine_translated": False,
    }


def test_validation_records_who_and_when(client, validator_headers):
    entry = validated_kb_entry(client, validator_headers)
    assert entry["status"] == "validated"
    assert entry["validated_by"]["full_name"] == "Validator Test"
    assert entry["validated_at"].endswith("Z")


def test_validation_is_refused_without_french_text(client, validator_headers):
    payload = copy.deepcopy(KB_NUTRITION)
    payload["translations"]["fr"]["answer"] = ""
    entry = create_kb_entry(client, validator_headers, payload)
    assert client.post(f"/kb/entries/{entry['id']}/validate", headers=validator_headers).status_code == 409


def test_editing_a_validated_entry_sends_it_back_to_draft(client, validator_headers):
    entry = validated_kb_entry(client, validator_headers)
    payload = copy.deepcopy(KB_NUTRITION)
    payload["translations"]["fr"]["answer"] = "Réponse corrigée."
    edited = client.put(f"/kb/entries/{entry['id']}", json=payload, headers=validator_headers).json()
    assert edited["status"] == "draft"
    assert edited["validated_by"] is None and edited["validated_at"] is None
    # ...et n'est donc plus servie à l'app.
    assert client.get("/assistant/faq").json()["entries"] == []


def test_saving_without_any_change_keeps_the_validation(client, validator_headers):
    entry = validated_kb_entry(client, validator_headers)
    same = client.put(f"/kb/entries/{entry['id']}", json=KB_NUTRITION, headers=validator_headers).json()
    assert same["status"] == "validated"


def test_a_partial_body_does_not_erase_other_languages(client, validator_headers):
    entry = create_kb_entry(client, validator_headers)
    payload = {**KB_NUTRITION, "translations": {"fr": KB_NUTRITION["translations"]["fr"]}}
    updated = client.put(f"/kb/entries/{entry['id']}", json=payload, headers=validator_headers).json()
    assert updated["translations"]["mos"]["answer"] == "Réponse de test (mos)"


def test_filters_and_accent_insensitive_search(client, validator_headers):
    validated = validated_kb_entry(client, validator_headers)
    other = copy.deepcopy(KB_NUTRITION)
    other["topic"] = "hygiene"
    other["translations"] = {"fr": {"question": "Comment se laver les mains ?", "answer": "Avec du savon."}}
    draft = create_kb_entry(client, validator_headers, other)

    def ids(**params):
        return [e["id"] for e in client.get("/kb/entries", params=params, headers=validator_headers).json()]

    assert ids(status="validated") == [validated["id"]]
    assert ids(topic="hygiene") == [draft["id"]]
    assert ids(q="GROSSESSE") == [validated["id"]]
    assert ids(q="savon") == [draft["id"]]
    assert client.get("/kb/entries", params={"status": "bidon"}, headers=validator_headers).status_code == 422


def test_get_and_delete(client, validator_headers):
    entry = create_kb_entry(client, validator_headers)
    assert client.get(f"/kb/entries/{entry['id']}", headers=validator_headers).json()["id"] == entry["id"]
    assert client.delete(f"/kb/entries/{entry['id']}", headers=validator_headers).status_code == 204
    assert client.get(f"/kb/entries/{entry['id']}", headers=validator_headers).status_code == 404


def test_archive(client, validator_headers):
    entry = validated_kb_entry(client, validator_headers)
    archived = client.post(f"/kb/entries/{entry['id']}/archive", headers=validator_headers).json()
    assert archived["status"] == "archived"


def test_human_audio_upload_stores_a_recording_and_returns_to_draft(client, validator_headers, models_loaded):
    entry = validated_kb_entry(client, validator_headers)
    response = client.post(
        f"/kb/entries/{entry['id']}/audio/mos",
        files={"audio": ("voix.m4a", io.BytesIO(b"audio"), "audio/mp4")},
        headers=validator_headers,
    )
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "draft"
    assert body["translations"]["mos"]["audio_kind"] == "human"
    assert body["translations"]["mos"]["audio_url"].startswith("/media/kb/human/")
    bad_lang = client.post(
        f"/kb/entries/{entry['id']}/audio/en",
        files={"audio": ("voix.m4a", io.BytesIO(b"audio"), "audio/mp4")},
        headers=validator_headers,
    )
    assert bad_lang.status_code == 422


def test_machine_translation_fills_missing_languages_and_is_flagged(client, validator_headers, models_loaded):
    payload = {**KB_NUTRITION, "translations": {"fr": KB_NUTRITION["translations"]["fr"]}}
    entry = validated_kb_entry(client, validator_headers, payload)
    translated = client.post(f"/kb/entries/{entry['id']}/translate", headers=validator_headers).json()

    assert translated["status"] == "draft"  # traduction automatique = à relire
    for lang in ("mos", "dyu"):
        assert translated["translations"][lang]["machine_translated"] is True
        assert translated["translations"][lang]["answer"] == f"[{lang}] Réponse de test validée (fr)."
    assert translated["translations"]["fr"]["machine_translated"] is False

    # Un humain retouche le mooré : le drapeau tombe pour cette langue seulement.
    edit = {
        **KB_NUTRITION,
        "translations": {"mos": {"question": "Question relue", "variants": [], "answer": "Réponse relue"}},
    }
    edited = client.put(f"/kb/entries/{entry['id']}", json=edit, headers=validator_headers).json()
    assert edited["translations"]["mos"]["machine_translated"] is False
    assert edited["translations"]["dyu"]["machine_translated"] is True


def test_machine_translation_without_model_is_503(client, validator_headers):
    entry = create_kb_entry(client, validator_headers)
    assert client.post(f"/kb/entries/{entry['id']}/translate", headers=validator_headers).status_code == 503


# --- Signes de danger ---------------------------------------------------------


def test_danger_sign_workflow(client, validator_headers):
    sign = create_danger_sign(client, validator_headers)
    assert sign["status"] == "validated"
    assert sign["keywords_fr"] == ["saigne", "saignement", "sang"]

    edited_payload = {**DANGER_BLEEDING, "keywords_fr": ["saigne", "hémorragie"]}
    edited = client.put(f"/kb/danger-signs/{sign['id']}", json=edited_payload, headers=validator_headers).json()
    assert edited["status"] == "draft"
    assert client.get("/assistant/danger-signs").json() == []

    listed = client.get("/kb/danger-signs", params={"status": "draft"}, headers=validator_headers).json()
    assert [s["id"] for s in listed] == [sign["id"]]
    assert client.delete(f"/kb/danger-signs/{sign['id']}", headers=validator_headers).status_code == 204


def test_danger_sign_agent_aid_is_stored_and_editing_it_resets_to_draft(client, validator_headers):
    sign = create_danger_sign(client, validator_headers)
    assert sign["translations"]["fr"]["agent_questions"] == []
    assert sign["translations"]["fr"]["refer_when"] is None
    assert sign["translations"]["mos"] == {"label": "", "advice": "", "agent_questions": [], "refer_when": None}

    fr = {
        **DANGER_BLEEDING["translations"]["fr"],
        "agent_questions": ["  Depuis quand ?  ", "Combien de linges ?"],
        "refer_when": "  Plus d'un linge par heure.  ",
    }
    payload = {**DANGER_BLEEDING, "translations": {"fr": fr}}
    edited = client.put(f"/kb/danger-signs/{sign['id']}", json=payload, headers=validator_headers).json()
    assert edited["status"] == "draft"
    assert edited["translations"]["fr"]["agent_questions"] == ["Depuis quand ?", "Combien de linges ?"]
    assert edited["translations"]["fr"]["refer_when"] == "Plus d'un linge par heure."

    # Réenregistrer à l'identique ne renvoie PAS un signe validé en brouillon.
    client.post(f"/kb/danger-signs/{sign['id']}/validate", headers=validator_headers)
    same = client.put(f"/kb/danger-signs/{sign['id']}", json=payload, headers=validator_headers).json()
    assert same["status"] == "validated"


def test_danger_sign_agent_aid_limits(client, validator_headers):
    def _post(**fr_extra):
        fr = {**DANGER_BLEEDING["translations"]["fr"], **fr_extra}
        return client.post(
            "/kb/danger-signs", json={**DANGER_BLEEDING, "translations": {"fr": fr}}, headers=validator_headers
        )

    assert _post(agent_questions=[f"Question {i} ?" for i in range(10)]).status_code == 201
    assert _post(agent_questions=[f"Question {i} ?" for i in range(11)]).status_code == 422
    assert _post(agent_questions=["x" * 301]).status_code == 422
    assert _post(agent_questions=[""]).status_code == 422
    assert _post(refer_when="x" * 1000).status_code == 201
    assert _post(refer_when="x" * 1001).status_code == 422


def test_old_danger_signs_without_agent_aid_keys_still_load_and_stay_validated(client, validator_headers, db):
    """Les lignes écrites avant la fiche d'aide n'ont que label/advice dans
    leur JSON : elles se lisent avec les valeurs par défaut, et un
    réenregistrement identique ne les renvoie pas en brouillon."""
    sign = create_danger_sign(client, validator_headers)
    row = db.get(DangerSign, sign["id"])
    row.translations = {"fr": {"label": "Saignement pendant la grossesse", "advice": "Allez au centre de santé."}}
    db.commit()

    listed = client.get("/kb/danger-signs", headers=validator_headers).json()
    assert listed[0]["translations"]["fr"]["agent_questions"] == []
    assert listed[0]["translations"]["fr"]["refer_when"] is None
    assert client.get("/assistant/danger-signs").json()[0]["agent_questions"] == []

    same = client.put(f"/kb/danger-signs/{sign['id']}", json=DANGER_BLEEDING, headers=validator_headers).json()
    assert same["status"] == "validated"


def test_danger_sign_validation_requires_french_label_and_advice(client, validator_headers):
    response = client.post("/kb/danger-signs", json={"keywords_fr": ["sang"]}, headers=validator_headers)
    sign = response.json()
    assert client.post(f"/kb/danger-signs/{sign['id']}/validate", headers=validator_headers).status_code == 409


# --- Questions sans réponse ---------------------------------------------------


def test_unanswered_questions_can_be_listed_and_resolved(client, validator_headers, db):
    client.post("/assistant/ask-text", json={"text": "question sans réponse", "lang": "fr"})
    (question,) = client.get("/kb/unanswered", params={"resolved": "false"}, headers=validator_headers).json()
    assert question["text_fr"] == "question sans réponse"
    assert question["resolved"] is False

    assert client.post(f"/kb/unanswered/{question['id']}/resolve", headers=validator_headers).status_code == 204
    assert client.get("/kb/unanswered", params={"resolved": "false"}, headers=validator_headers).json() == []
    assert len(client.get("/kb/unanswered", params={"resolved": "true"}, headers=validator_headers).json()) == 1
    assert db.query(UnansweredQuestion).one().resolved_at is not None


def test_danger_sign_archive(client, validator_headers):
    sign = create_danger_sign(client, validator_headers)
    archived = client.post(f"/kb/danger-signs/{sign['id']}/archive", headers=validator_headers).json()
    assert archived["status"] == "archived"
    assert client.get("/assistant/danger-signs").json() == []


def test_a_language_may_carry_the_agent_aid_without_label_or_advice(client, validator_headers):
    """Seul le français exige libellé et conseil (à la validation). Une
    langue envoyée avec seulement la fiche d'aide est acceptée ; l'app reçoit
    alors le libellé et le conseil français."""
    payload = {
        **DANGER_BLEEDING,
        "translations": {
            **DANGER_BLEEDING["translations"],
            "mos": {"label": "", "advice": "", "agent_questions": ["Question (mos)"], "refer_when": "Orienter (mos)"},
        },
    }
    response = client.post("/kb/danger-signs", json=payload, headers=validator_headers)
    assert response.status_code == 201
    sign = response.json()
    assert client.post(f"/kb/danger-signs/{sign['id']}/validate", headers=validator_headers).status_code == 200

    (mos,) = client.get("/assistant/danger-signs", params={"lang": "mos"}).json()
    assert (mos["label"], mos["advice"]) == ("Saignement pendant la grossesse", "Allez au centre de santé.")
    assert (mos["agent_questions"], mos["refer_when"]) == (["Question (mos)"], "Orienter (mos)")
