"""Statistiques anonymes : aucun identifiant stocké, suppression des petites
cellules, événements sensibles jamais ventilés par district ni par semaine."""

import uuid
from datetime import UTC, date, datetime, timedelta

import pytest
from conftest import create_staff

from app.config import settings
from app.db_models import Beneficiary, District, EventCount, GbvReferral, Visit
from app.schemas.misc import SENSITIVE_EVENT_TYPES

TODAY = datetime.now(UTC).date()


def _event(type_="question_asked", lang="fr", district_id=None, day=TODAY):
    return {"type": type_, "lang": lang, "district_id": district_id, "occurred_on": day.isoformat()}


def _send(client, events):
    return client.post("/events", json={"events": events})


def test_events_are_stored_as_anonymous_daily_counters(client, db):
    response = _send(client, [_event(), _event(), {**_event(), "device_id": "abc", "user_id": "xyz"}])
    assert response.status_code == 202
    assert response.json() == {"accepted": 3}

    (cell,) = db.query(EventCount).all()
    assert cell.count == 3
    assert set(EventCount.__table__.columns.keys()) == {"id", "occurred_on", "type", "lang", "district_id", "count"}


def test_invalid_events_are_refused(client):
    assert _send(client, [_event(type_="bidon")]).status_code == 422
    assert _send(client, [_event(lang="en")]).status_code == 422
    assert _send(client, [_event()] * 101).status_code == 422
    assert _send(client, [_event(day=TODAY + timedelta(days=5))]).status_code == 422


def test_unknown_district_is_dropped(client, db):
    _send(client, [_event(district_id="77777777-7777-4777-8777-777777777777")])
    assert db.query(EventCount).one().district_id == ""


def test_events_are_rate_limited(client):
    statuses = [_send(client, [_event()]).status_code for _ in range(31)]
    assert statuses[-1] == 429


def test_public_stats_suppress_small_cells_and_protect_sensitive_types(client, admin_headers):
    district = client.post("/districts", json={"name": "D1", "region": "R1"}, headers=admin_headers).json()
    _send(client, [_event(district_id=district["id"])] * 12)  # au-dessus du seuil
    _send(client, [_event(type_="help_call", district_id=district["id"])] * 12)  # sensible
    _send(client, [_event(type_="capsule_played", lang="mos")] * 3)  # sous le seuil

    stats = client.get("/public/stats").json()
    assert stats["min_count"] == 10
    assert set(stats["period"]) == {"from", "to"}
    totals = {t["type"]: t["count"] for t in stats["totals"]}
    assert totals == {"question_asked": 12, "help_call": 12}

    assert {c["type"] for c in stats["by_district"]} == {"question_asked"}
    assert {c["type"] for c in stats["by_week"]} == {"question_asked"}
    assert {c["type"] for c in stats["by_lang"]} == {"question_asked"}
    assert {c["type"] for c in stats["by_region"]} == {"question_asked", "help_call"}
    assert {c["type"] for c in stats["by_month"]} == {"question_asked", "help_call"}
    assert stats["by_district"] == [{"district": "D1", "type": "question_asked", "count": 12}]
    # capsule_played (3) supprimé partout où il apparaissait : totaux, semaine,
    # mois, langue (pas de district -> ni district ni région).
    assert stats["suppressed_cells"] == 4


DOSSIER_EVENT_TYPES = [
    "monthly_active",
    "question_voice",
    "answer_understood",
    "answer_not_understood",
    "anc_visit_recorded",
    "vaccine_recorded",
]


def test_dossier_indicator_events_are_accepted_and_not_sensitive(client, admin_headers):
    district = client.post("/districts", json={"name": "D1", "region": "R1"}, headers=admin_headers).json()
    events = [_event(type_=t, lang="mos", district_id=district["id"]) for t in DOSSIER_EVENT_TYPES for _ in range(10)]
    assert _send(client, events).status_code == 202

    assert not SENSITIVE_EVENT_TYPES.intersection(DOSSIER_EVENT_TYPES)
    stats = client.get("/public/stats").json()
    assert {t["type"]: t["count"] for t in stats["totals"]} == dict.fromkeys(DOSSIER_EVENT_TYPES, 10)
    # Ventilés comme n'importe quel type non sensible.
    for breakdown in ("by_week", "by_lang", "by_district", "by_month", "by_region"):
        assert {c["type"] for c in stats[breakdown]} == set(DOSSIER_EVENT_TYPES), breakdown


# --- Activité des agents -------------------------------------------------------


DANGER_SIGN_ID = "66666666-6666-4666-8666-666666666666"


def _agent_with_records(
    db, district_id, *, visits=0, referred=0, gbv=0, day=TODAY, deleted_visits=0, referred_without_danger=0
):
    """Un agent et ses fiches, écrits directement en base (plus rapide que la
    synchronisation, déjà testée dans test_agent.py). Les `referred`
    premières visites sont orientées pour un signe de danger, les
    `referred_without_danger` suivantes orientées sans signe constaté."""
    agent = create_staff(db, "agent", district_id=district_id)
    stamp = datetime.now(UTC)
    beneficiary = Beneficiary(
        id=str(uuid.uuid4()),
        agent_id=agent.id,
        pseudonym="B",
        age_range="20-24",
        consent_given_at=stamp,
        updated_at=stamp,
    )
    db.add(beneficiary)
    for i in range(visits + deleted_visits):
        db.add(
            Visit(
                id=str(uuid.uuid4()),
                agent_id=agent.id,
                beneficiary_id=beneficiary.id,
                visit_date=day,
                type="prenatal",
                referred=i < referred + referred_without_danger,
                danger_sign_ids=[DANGER_SIGN_ID] if i < referred else [],
                deleted=i >= visits,
                updated_at=stamp,
            )
        )
    for _ in range(gbv):
        db.add(
            GbvReferral(
                id=str(uuid.uuid4()), agent_id=agent.id, referral_date=day, category="physical", updated_at=stamp
            )
        )
    db.commit()
    return agent


def _period(day=TODAY):
    return {"from": (day - timedelta(days=30)).isoformat(), "to": day.isoformat()}


@pytest.fixture
def no_threshold(monkeypatch):
    monkeypatch.setattr(settings, "public_stats_min_count", 1)


def test_agent_activity_counts_by_month_and_region(client, db, no_threshold):
    centre = District(name="D1", region="Centre")
    hauts = District(name="D2", region="Hauts-Bassins")
    db.add_all([centre, hauts])
    db.commit()
    # 3 visites : 2 orientées pour un signe de danger, 1 orientée sans signe.
    _agent_with_records(db, centre.id, visits=3, referred=2, referred_without_danger=1, deleted_visits=4)
    _agent_with_records(db, centre.id, gbv=2)  # actif par ses seules orientations VBG
    _agent_with_records(db, hauts.id, visits=1)
    _agent_with_records(db, None, visits=5, gbv=5)  # sans district : ignoré
    _agent_with_records(db, centre.id, visits=7, day=TODAY - timedelta(days=200))  # hors période
    create_staff(db, "agent", district_id=centre.id)  # aucune fiche : pas actif

    stats = client.get("/public/stats", params=_period()).json()
    month = TODAY.strftime("%Y-%m")
    assert stats["agent_activity"] == [
        {"month": month, "region": "Centre", "type": "agent_visits", "count": 3},
        {"month": month, "region": "Centre", "type": "agents_active", "count": 2},
        {"month": month, "region": "Centre", "type": "danger_referrals", "count": 2},
        {"month": month, "region": "Centre", "type": "gbv_referrals", "count": 2},
        {"month": month, "region": "Hauts-Bassins", "type": "agent_visits", "count": 1},
        {"month": month, "region": "Hauts-Bassins", "type": "agents_active", "count": 1},
    ]
    assert stats["suppressed_cells"] == 0


def test_agent_activity_counts_an_agent_once_per_month(client, db, no_threshold):
    district = District(name="D1", region="Centre")
    db.add(district)
    db.commit()
    first = date(2026, 9, 30)
    agent = _agent_with_records(db, district.id, visits=2, gbv=1, day=first)
    db.add(
        GbvReferral(
            id=str(uuid.uuid4()),
            agent_id=agent.id,
            referral_date=date(2026, 10, 1),
            category="sexual",
            updated_at=datetime.now(UTC),
        )
    )
    db.commit()

    stats = client.get("/public/stats", params={"from": "2026-09-01", "to": "2026-10-31"}).json()
    active = {(c["month"], c["count"]) for c in stats["agent_activity"] if c["type"] == "agents_active"}
    assert active == {("2026-09", 1), ("2026-10", 1)}


def test_agent_activity_suppresses_small_cells(client, db):
    district = District(name="D1", region="Centre")
    db.add(district)
    db.commit()
    _agent_with_records(db, district.id, visits=12, referred=3, gbv=1)

    stats = client.get("/public/stats", params=_period()).json()
    assert stats["agent_activity"] == [
        {"month": TODAY.strftime("%Y-%m"), "region": "Centre", "type": "agent_visits", "count": 12}
    ]
    # agents_active (1), danger_referrals (3), gbv_referrals (1) : supprimés.
    assert stats["suppressed_cells"] == 3


def test_public_stats_period_validation(client):
    assert client.get("/public/stats", params={"from": "2026-10-10", "to": "2026-10-01"}).status_code == 422
    body = client.get("/public/stats", params={"from": "2026-10-01", "to": "2026-10-10"}).json()
    assert body["period"] == {"from": "2026-10-01", "to": "2026-10-10"}
