"""Seed (données sourcées uniquement, idempotent) et création du premier admin."""

import pytest

from app.bootstrap_admin import bootstrap_admins
from app.db_models import Capsule, DangerSign, District, HelpService, KbEntry, User
from app.security import verify_password
from app.seed import seed


def test_seed_is_idempotent_and_contains_only_sourced_data(db):
    assert seed(db) == {"help_services": 4, "danger_signs": 10}
    assert seed(db) == {"help_services": 0, "danger_signs": 0}

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
    assert len(signs) == 10
    for sign in signs:
        assert sign.status == "draft"  # jamais servi avant validation
        assert set(sign.translations) == {"fr"}  # pas de mooré/dioula inventé
        assert sign.translations["fr"]["advice"] == "Allez immédiatement au centre de santé."
        assert sign.keywords_fr
        assert "OMS" in sign.source

    # Rien d'autre n'est inventé.
    assert db.query(KbEntry).count() == 0
    assert db.query(Capsule).count() == 0
    assert db.query(District).count() == 0


def test_seed_does_not_overwrite_or_duplicate_team_edits(db):
    seed(db)
    sign = db.query(DangerSign).first()
    sign.translations = {"fr": {"label": "Libellé revu par la sage-femme", "advice": "Conseil revu"}}
    db.commit()
    seed(db)
    assert db.query(DangerSign).count() == 10
    db.refresh(sign)
    assert sign.translations["fr"]["label"] == "Libellé revu par la sage-femme"


def test_seeded_drafts_are_not_served(client, db):
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
