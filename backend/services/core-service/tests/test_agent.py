"""Espace agent : cloisonnement par agent, consentement obligatoire,
synchronisation dernier-écrit-gagne, suppression logique, orientations VBG
sans identifiant de bénéficiaire."""

from datetime import UTC, datetime, timedelta

from conftest import create_staff, login_headers

from app.db_models import GbvReferral

B1 = "11111111-1111-4111-8111-111111111111"
B2 = "33333333-3333-4333-8333-333333333333"
V1 = "22222222-2222-4222-8222-222222222222"
R1 = "44444444-4444-4444-8444-444444444444"


def _ts(minutes: int = 0) -> str:
    return (datetime(2026, 10, 20, 8, 0, tzinfo=UTC) + timedelta(minutes=minutes)).isoformat().replace("+00:00", "Z")


def beneficiary(id_=B1, minutes=0, **extra):
    return {
        "id": id_,
        "pseudonym": "Maman A",
        "village": "Village test",
        "age_range": "20-24",
        "pregnant": True,
        "children_under_5": 1,
        "consent_given_at": _ts(),
        "updated_at": _ts(minutes),
        **extra,
    }


def visit(id_=V1, beneficiary_id=B1, minutes=0, **extra):
    today = datetime.now(UTC).date().isoformat()
    return {
        "id": id_,
        "beneficiary_id": beneficiary_id,
        "visit_date": today,
        "type": "prenatal",
        "updated_at": _ts(minutes),
        **extra,
    }


def test_agent_space_is_reserved_to_agents(client, validator_headers, woman):
    assert client.get("/agent/beneficiaries").status_code == 401
    assert client.get("/agent/beneficiaries", headers=validator_headers).status_code == 403
    assert client.get("/agent/beneficiaries", headers=woman["headers"]).status_code == 403


def test_beneficiary_without_consent_is_refused(client, agent_headers):
    payload = beneficiary()
    del payload["consent_given_at"]
    assert client.post("/agent/beneficiaries", json=payload, headers=agent_headers).status_code == 422
    payload["consent_given_at"] = None
    assert client.post("/agent/beneficiaries", json=payload, headers=agent_headers).status_code == 422


def test_rest_crud_and_soft_delete(client, agent_headers):
    created = client.post("/agent/beneficiaries", json=beneficiary(), headers=agent_headers)
    assert created.status_code == 201
    assert client.post("/agent/beneficiaries", json=beneficiary(), headers=agent_headers).status_code == 409

    updated = client.put(
        f"/agent/beneficiaries/{B1}", json=beneficiary(minutes=5, pseudonym="Maman B"), headers=agent_headers
    )
    assert updated.json()["pseudonym"] == "Maman B"
    assert client.get(f"/agent/beneficiaries/{B1}", headers=agent_headers).json()["pseudonym"] == "Maman B"

    assert client.post("/agent/visits", json=visit(), headers=agent_headers).status_code == 201
    assert len(client.get("/agent/visits", params={"beneficiary_id": B1}, headers=agent_headers).json()) == 1

    assert client.delete(f"/agent/beneficiaries/{B1}", headers=agent_headers).status_code == 204
    assert client.get("/agent/beneficiaries", headers=agent_headers).json() == []
    assert client.get("/agent/visits", headers=agent_headers).json() == []

    # La suppression est LOGIQUE : elle se propage par la synchronisation.
    synced = client.post("/agent/sync", json={"since": None}, headers=agent_headers).json()
    assert synced["beneficiaries"][0]["deleted"] is True
    assert synced["visits"][0]["deleted"] is True


def test_records_are_scoped_to_their_agent(client, db):
    agent_a = create_staff(db, "agent")
    agent_b = create_staff(db, "agent")
    headers_a = login_headers(client, agent_a.email)
    headers_b = login_headers(client, agent_b.email)
    client.post("/agent/beneficiaries", json=beneficiary(), headers=headers_a)

    assert client.get("/agent/beneficiaries", headers=headers_b).json() == []
    assert client.get(f"/agent/beneficiaries/{B1}", headers=headers_b).status_code == 404
    assert client.put(f"/agent/beneficiaries/{B1}", json=beneficiary(minutes=9), headers=headers_b).status_code == 404
    # Même identifiant poussé par un autre agent : jamais appliqué.
    assert client.post("/agent/beneficiaries", json=beneficiary(), headers=headers_b).status_code == 409
    client.post("/agent/sync", json={"beneficiaries": [beneficiary(minutes=60, pseudonym="Pirate")]}, headers=headers_b)
    assert client.get(f"/agent/beneficiaries/{B1}", headers=headers_a).json()["pseudonym"] == "Maman A"
    # Une visite rattachée au bénéficiaire d'un autre agent est refusée.
    assert client.post("/agent/visits", json=visit(), headers=headers_b).status_code == 422


def test_sync_last_write_wins(client, agent_headers):
    client.post(
        "/agent/sync", json={"beneficiaries": [beneficiary(minutes=10, pseudonym="Version 10")]}, headers=agent_headers
    )

    older = client.post(
        "/agent/sync", json={"beneficiaries": [beneficiary(minutes=5, pseudonym="Version 5")]}, headers=agent_headers
    )
    assert older.status_code == 200
    assert client.get(f"/agent/beneficiaries/{B1}", headers=agent_headers).json()["pseudonym"] == "Version 10"

    client.post(
        "/agent/sync", json={"beneficiaries": [beneficiary(minutes=20, pseudonym="Version 20")]}, headers=agent_headers
    )
    assert client.get(f"/agent/beneficiaries/{B1}", headers=agent_headers).json()["pseudonym"] == "Version 20"


def test_sync_creates_visits_with_their_beneficiary_and_skips_orphans(client, agent_headers):
    response = client.post(
        "/agent/sync",
        json={
            "beneficiaries": [beneficiary()],
            "visits": [visit(), visit(id_="55555555-5555-4555-8555-555555555555", beneficiary_id=B2)],
        },
        headers=agent_headers,
    )
    assert response.status_code == 200
    assert [v["id"] for v in response.json()["visits"]] == [V1]


def test_sync_returns_only_what_changed_since(client, agent_headers):
    first = client.post("/agent/sync", json={"beneficiaries": [beneficiary()]}, headers=agent_headers).json()
    assert [b["id"] for b in first["beneficiaries"]] == [B1]

    later = client.post(
        "/agent/sync",
        json={"since": first["server_time"], "beneficiaries": [beneficiary(id_=B2)]},
        headers=agent_headers,
    ).json()
    assert later["server_time"] >= first["server_time"]
    assert B2 in [b["id"] for b in later["beneficiaries"]]

    nothing_new = client.post("/agent/sync", json={"since": later["server_time"]}, headers=agent_headers).json()
    assert B1 not in [b["id"] for b in nothing_new["beneficiaries"]]


def test_gbv_referral_stores_no_name_and_no_beneficiary_id(client, agent_headers, db):
    payload = {
        "id": R1,
        "referral_date": "2026-10-21",
        "category": "physical",
        "service_id": None,
        # Champs qui ne doivent JAMAIS être stockés, même envoyés par erreur.
        "beneficiary_id": B1,
        "name": "Nom Réel",
    }
    response = client.post("/agent/gbv-referrals", json=payload, headers=agent_headers)
    assert response.status_code == 201
    assert "beneficiary_id" not in response.json() and "name" not in response.json()

    columns = set(GbvReferral.__table__.columns.keys())
    assert columns == {"id", "agent_id", "referral_date", "service_id", "category", "updated_at", "synced_at"}
    assert db.query(GbvReferral).count() == 1
    assert client.post("/agent/gbv-referrals", json=payload, headers=agent_headers).status_code == 409


def test_summary(client, agent_headers):
    client.post(
        "/agent/sync",
        json={
            "beneficiaries": [beneficiary(), beneficiary(id_=B2, pregnant=False)],
            "visits": [visit(referred=True, danger_sign_ids=["66666666-6666-4666-8666-666666666666"])],
            "gbv_referrals": [{"id": R1, "referral_date": datetime.now(UTC).date().isoformat(), "category": "sexual"}],
        },
        headers=agent_headers,
    )
    assert client.get("/agent/summary", headers=agent_headers).json() == {
        "beneficiaries": 2,
        "pregnant": 1,
        "visits_last_30_days": 1,
        "referrals_last_30_days": 2,
        "danger_signs_last_30_days": 1,
    }


def test_next_appointment_round_trips_through_rest_and_sync(client, agent_headers):
    created = client.post("/agent/beneficiaries", json=beneficiary(), headers=agent_headers).json()
    # Facultatif : absent = null.
    assert created["next_appointment_date"] is None
    assert created["next_appointment_reason"] is None

    appointment = {"next_appointment_date": "2026-11-12", "next_appointment_reason": "vaccine"}
    updated = client.put(
        f"/agent/beneficiaries/{B1}", json=beneficiary(minutes=5, **appointment), headers=agent_headers
    ).json()
    assert {k: updated[k] for k in appointment} == appointment
    fetched = client.get(f"/agent/beneficiaries/{B1}", headers=agent_headers).json()
    assert {k: fetched[k] for k in appointment} == appointment

    synced = client.post(
        "/agent/sync",
        json={
            "beneficiaries": [
                beneficiary(id_=B2, minutes=1, next_appointment_date="2026-12-01", next_appointment_reason="prenatal")
            ]
        },
        headers=agent_headers,
    ).json()
    by_id = {b["id"]: b for b in synced["beneficiaries"]}
    assert by_id[B1]["next_appointment_reason"] == "vaccine"
    assert (by_id[B2]["next_appointment_date"], by_id[B2]["next_appointment_reason"]) == ("2026-12-01", "prenatal")

    # Rendez-vous honoré : l'appareil efface les deux champs.
    cleared = client.put(
        f"/agent/beneficiaries/{B1}",
        json=beneficiary(minutes=10, next_appointment_date=None, next_appointment_reason=None),
        headers=agent_headers,
    ).json()
    assert cleared["next_appointment_date"] is None and cleared["next_appointment_reason"] is None


def test_next_appointment_reason_is_validated(client, agent_headers):
    payload = beneficiary(next_appointment_date="2026-11-12", next_appointment_reason="dentiste")
    assert client.post("/agent/beneficiaries", json=payload, headers=agent_headers).status_code == 422
    payload = beneficiary(next_appointment_date="pas une date")
    assert client.post("/agent/beneficiaries", json=payload, headers=agent_headers).status_code == 422
