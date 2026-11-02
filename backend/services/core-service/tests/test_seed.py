"""Seed (données sourcées uniquement, idempotent) et création du premier admin."""

import pytest

from app.bootstrap_admin import bootstrap_admins
from app.db_models import Capsule, DangerSign, District, HelpService, KbEntry, User
from app.security import verify_password
from app.seed import ADVICE_GO_NOW, seed
from app.seed_content import CAPSULES, KB_ENTRIES, WHO_NEWBORN, WHO_PCPNC


def test_seed_is_idempotent_and_contains_only_sourced_data(db):
    assert seed(db) == {
        "help_services": 4,
        "danger_signs": 13,
        "kb_entries": len(KB_ENTRIES),
        "capsules": len(CAPSULES),
    }
    assert seed(db) == {"help_services": 0, "danger_signs": 0, "kb_entries": 0, "capsules": 0}

    services = {s.phone: s for s in db.query(HelpService).all()}
    assert set(services) == {"80 00 12 87", "17", "16", "18"}
    hotline = services["80 00 12 87"]
    assert hotline.phone == "80 00 12 87"
    assert hotline.free_call is True
    assert hotline.verified_at is None  # à confirmer en 2026
    assert hotline.source_url.startswith("https://www.burkina24.com/2021/03/02/")

    assert (services["17"].category, services["16"].category, services["18"].category) == (
        "police",
        "gendarmerie",
        "emergency",
    )
    for phone in ("17", "16", "18"):
        assert services[phone].verified_at is None  # « à confirmer », comme dans le dossier
        assert services[phone].source_url.startswith("https://diplomatie.belgium.be/")
        assert services[phone].city is None  # numéros nationaux
        assert services[phone].languages == []  # non précisé par la source

    signs = db.query(DangerSign).all()
    assert len(signs) == 13
    for sign in signs:
        assert sign.status == "sourced"  # jamais validé par le seed
        assert set(sign.translations) == {"fr"}  # pas de mooré/dioula inventé
        assert sign.translations["fr"]["advice"]
        assert sign.translations["fr"]["refer_when"] == "Orienter tout de suite vers le centre de santé."
        assert sign.keywords_fr
        assert "OMS" in sign.source

    # Le contenu de santé est `sourced`, en français seulement.
    for item in [*db.query(KbEntry).all(), *db.query(Capsule).all()]:
        assert item.status == "sourced"
        assert set(item.translations) == {"fr"}
        assert item.validated_by_id is None and item.validated_at is None

    # Rien d'autre n'est inventé.
    assert db.query(District).count() == 0


def test_seeded_danger_signs_carry_the_exact_advice_and_source(db):
    seed(db)
    signs = {s.seed_key: s for s in db.query(DangerSign).all()}
    advice = {key: sign.translations["fr"]["advice"] for key, sign in signs.items()}
    assert advice == {
        "grossesse-saignement": ADVICE_GO_NOW,
        "grossesse-maux-de-tete": ADVICE_GO_NOW,
        "grossesse-vision-trouble": ADVICE_GO_NOW,
        "grossesse-convulsions": ADVICE_GO_NOW,
        "grossesse-douleurs-ventre": ADVICE_GO_NOW,
        "grossesse-difficulte-respirer": ADVICE_GO_NOW,
        "grossesse-bebe-ne-bouge-plus": ADVICE_GO_NOW,
        "grossesse-fievre": (
            "Allez au centre de santé le plus vite possible, sans attendre que ça passe. "
            "Si vous êtes trop faible pour vous lever, allez-y tout de suite."
        ),
        "grossesse-gonflement": "Allez au centre de santé le plus vite possible, sans attendre que ça passe.",
        "grossesse-perte-des-eaux": (
            "Allez au centre de santé dès que les eaux ont coulé, même sans contractions. "
            "N'attendez pas que l'eau s'arrête."
        ),
        "bebe-ne-tete-pas": ADVICE_GO_NOW,
        "bebe-corps-froid": ADVICE_GO_NOW,
        "bebe-bouge-moins": ADVICE_GO_NOW,
    }
    assert ADVICE_GO_NOW == "Allez tout de suite au centre de santé, de jour comme de nuit, sans attendre."
    # Le délai de 6 heures ne vaut que pour un accouchement à domicile sans soignant.
    assert not any("6 heures" in text for text in advice.values())

    assert signs["grossesse-perte-des-eaux"].translations["fr"]["label"] == "Perte des eaux"
    assert signs["grossesse-saignement"].source == WHO_PCPNC
    assert "édition 2003" in WHO_PCPNC
    assert signs["bebe-corps-froid"].source == WHO_NEWBORN
    assert signs["bebe-ne-tete-pas"].keywords_fr == [
        "ne tète pas",
        "ne tète plus",
        "refuse le sein",
        "n'arrive pas à téter",
    ]


def test_seed_does_not_overwrite_or_duplicate_team_edits(db):
    seed(db)
    sign = db.query(DangerSign).first()
    sign.translations = {"fr": {"label": "Libellé revu par la sage-femme", "advice": "Conseil revu"}}
    db.commit()
    entry = db.query(KbEntry).first()
    entry.status = "validated"
    entry.translations = {"fr": {"question": "Question revue", "variants": [], "answer": "Réponse revue"}}
    capsule = db.query(Capsule).first()
    capsule.status = "draft"
    db.commit()
    seed(db)
    assert db.query(DangerSign).count() == 13
    assert db.query(KbEntry).count() == len(KB_ENTRIES)
    assert db.query(Capsule).count() == len(CAPSULES)
    db.refresh(sign)
    assert sign.translations["fr"]["label"] == "Libellé revu par la sage-femme"
    db.refresh(entry)
    assert entry.status == "validated" and entry.translations["fr"]["answer"] == "Réponse revue"
    db.refresh(capsule)
    assert capsule.status == "draft"


def test_seeded_content_is_not_served_by_default(client, db):
    seed(db)
    assert client.get("/assistant/danger-signs").json() == []
    assert client.post("/assistant/ask-text", json={"text": "je saigne", "lang": "fr"}).json()["danger"] is False
    assert sorted(s["phone"] for s in client.get("/help/services").json()) == ["16", "17", "18", "80 00 12 87"]
    emergency = client.get("/help/services", params={"category": "emergency"}).json()
    assert [(s["phone"], s["verified_at"]) for s in emergency] == [("18", None)]


def test_bootstrap_creates_then_promotes_without_duplicates(db):
    asked: list[int] = []

    def password() -> str:
        asked.append(1)
        return "mot-de-passe-admin"

    report = bootstrap_admins(db, ["Admin@Laafi-Ma.bf"], password, full_name="Admin Ztech")
    assert report == ["admin@laafi-ma.bf : compte admin créé"]
    admin = db.query(User).one()
    assert admin.role == "admin" and admin.email == "admin@laafi-ma.bf"
    assert verify_password("mot-de-passe-admin", admin.hashed_password)

    admin.role = "agent"
    db.commit()
    assert bootstrap_admins(db, ["admin@laafi-ma.bf"], password) == ["admin@laafi-ma.bf : promu admin"]
    assert db.query(User).count() == 1
    assert len(asked) == 1  # mot de passe demandé seulement pour créer


def test_bootstrap_refuses_a_weak_password(db):
    with pytest.raises(ValueError):
        bootstrap_admins(db, ["admin@laafi-ma.bf"], lambda: "court")
    assert db.query(User).count() == 0
