"""Comptes : appareil anonyme (femmes), personnel, profil, suppression."""

import re
from datetime import UTC, datetime

import jwt
from conftest import STAFF_PASSWORD, create_staff, login_headers
from helpers import BACKUP

from app.config import settings
from app.db_models import Beneficiary, RecordBackup, User, Visit


def _token_lifetime_seconds(token: str) -> float:
    payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
    return payload["exp"] - datetime.now(UTC).timestamp()


# --- Compte appareil anonyme --------------------------------------------------


def test_device_account_is_anonymous_and_recovery_code_is_only_hashed(client, db):
    response = client.post("/auth/device")
    assert response.status_code == 201
    body = response.json()
    assert body["token_type"] == "bearer"
    assert re.fullmatch(r"[0-9A-Z]{4}(-[0-9A-Z]{4}){3}", body["recovery_code"])

    user = db.get(User, body["account_id"])
    assert user.role == "woman"
    assert user.email is None and user.full_name is None and user.hashed_password is None
    assert user.recovery_code_hash and body["recovery_code"] not in user.recovery_code_hash


def test_device_token_lasts_days_and_staff_token_minutes(client, db):
    device_token = client.post("/auth/device").json()["access_token"]
    assert _token_lifetime_seconds(device_token) > 29 * 86400

    staff = create_staff(db, "agent")
    staff_token = client.post("/auth/login", json={"email": staff.email, "password": STAFF_PASSWORD}).json()
    assert _token_lifetime_seconds(staff_token["access_token"]) <= settings.jwt_expire_minutes * 60


def test_me_for_a_woman_has_no_identifying_data(client, woman):
    body = client.get("/auth/me", headers=woman["headers"]).json()
    assert body["role"] == "woman"
    assert body["id"] == woman["account_id"]
    assert body["email"] is None and body["full_name"] is None and body["district_id"] is None
    assert body["active"] is True
    assert body["created_at"].endswith("Z")


def test_recover_with_the_right_pair_gives_a_new_token(client, woman):
    response = client.post(
        "/auth/device/recover", json={"account_id": woman["account_id"], "recovery_code": woman["recovery_code"]}
    )
    assert response.status_code == 200
    token = response.json()["access_token"]
    assert client.get("/auth/me", headers={"Authorization": f"Bearer {token}"}).json()["id"] == woman["account_id"]


def test_recover_tolerates_a_hand_typed_code(client, woman):
    sloppy = woman["recovery_code"].replace("-", " ").lower()
    response = client.post("/auth/device/recover", json={"account_id": woman["account_id"], "recovery_code": sloppy})
    assert response.status_code == 200


def test_recover_with_a_wrong_pair_is_401(client, woman, db):
    wrong_code = client.post(
        "/auth/device/recover", json={"account_id": woman["account_id"], "recovery_code": "AAAA-AAAA-AAAA-AAAA"}
    )
    not_a_uuid = client.post("/auth/device/recover", json={"account_id": "nope", "recovery_code": "x"})
    staff = create_staff(db, "agent")
    staff_id = client.post("/auth/device/recover", json={"account_id": staff.id, "recovery_code": "x"})
    assert wrong_code.status_code == not_a_uuid.status_code == staff_id.status_code == 401


def test_device_creation_is_rate_limited(client):
    statuses = [client.post("/auth/device").status_code for _ in range(6)]
    assert statuses[:5] == [201] * 5
    assert statuses[5] == 429


# --- Personnel ----------------------------------------------------------------


def test_staff_login_and_me(client, db):
    staff = create_staff(db, "validator", email="sage-femme@laafi-ma.bf")
    headers = login_headers(client, "SAGE-FEMME@laafi-ma.bf")
    body = client.get("/auth/me", headers=headers).json()
    assert body["role"] == "validator"
    assert body["email"] == "sage-femme@laafi-ma.bf"
    assert body["id"] == staff.id


def test_login_errors_do_not_reveal_whether_the_email_exists(client, db):
    create_staff(db, "agent", email="agent@laafi-ma.bf")
    wrong_password = client.post("/auth/login", json={"email": "agent@laafi-ma.bf", "password": "faux-mot-de-passe"})
    unknown = client.post("/auth/login", json={"email": "inconnu@laafi-ma.bf", "password": "faux-mot-de-passe"})
    assert wrong_password.status_code == unknown.status_code == 401
    assert wrong_password.json() == unknown.json()


def test_deactivated_staff_cannot_log_in_nor_use_an_existing_token(client, db):
    staff = create_staff(db, "agent")
    headers = login_headers(client, staff.email)
    staff.active = False
    db.commit()
    assert client.post("/auth/login", json={"email": staff.email, "password": STAFF_PASSWORD}).status_code == 403
    assert client.get("/auth/me", headers=headers).status_code == 403


def test_missing_or_invalid_token_is_401(client):
    assert client.get("/auth/me").status_code == 401
    assert client.get("/auth/me", headers={"Authorization": "Bearer pas-un-jwt"}).status_code == 401


def test_change_password(client, db):
    staff = create_staff(db, "agent")
    headers = login_headers(client, staff.email)

    wrong = client.post(
        "/auth/change-password",
        json={"current_password": "pas-le-bon-mdp", "new_password": "nouveau-mot-de-passe"},
        headers=headers,
    )
    too_short = client.post(
        "/auth/change-password", json={"current_password": STAFF_PASSWORD, "new_password": "court"}, headers=headers
    )
    ok = client.post(
        "/auth/change-password",
        json={"current_password": STAFF_PASSWORD, "new_password": "nouveau-mot-de-passe"},
        headers=headers,
    )
    assert wrong.status_code == 400
    assert too_short.status_code == 422
    assert ok.status_code == 204
    login_headers(client, staff.email, "nouveau-mot-de-passe")


def test_a_woman_has_no_password_to_change(client, woman):
    response = client.post(
        "/auth/change-password",
        json={"current_password": "x", "new_password": "nouveau-mot-de-passe"},
        headers=woman["headers"],
    )
    assert response.status_code == 403


# --- Suppression du compte ----------------------------------------------------


def test_deleting_a_woman_account_deletes_her_backup(client, woman, db):
    assert client.put("/records/backup", json=BACKUP, headers=woman["headers"]).status_code == 200
    assert client.delete("/auth/me", headers=woman["headers"]).status_code == 204
    assert db.get(User, woman["account_id"]) is None
    assert db.get(RecordBackup, woman["account_id"]) is None


def test_deleting_an_agent_deletes_beneficiaries_and_visits(client, db):
    agent = create_staff(db, "agent")
    headers = login_headers(client, agent.email)
    beneficiary_id = "11111111-1111-4111-8111-111111111111"
    client.post(
        "/agent/beneficiaries",
        json={
            "id": beneficiary_id,
            "pseudonym": "B1",
            "age_range": "20-24",
            "consent_given_at": "2026-10-01T08:00:00Z",
        },
        headers=headers,
    )
    client.post(
        "/agent/visits",
        json={
            "id": "22222222-2222-4222-8222-222222222222",
            "beneficiary_id": beneficiary_id,
            "visit_date": "2026-10-02",
            "type": "prenatal",
        },
        headers=headers,
    )
    assert client.delete("/auth/me", headers=headers).status_code == 204
    db.expire_all()
    assert db.query(Beneficiary).count() == 0
    assert db.query(Visit).count() == 0


def test_the_last_admin_cannot_delete_their_own_account(client, admin_headers):
    assert client.delete("/auth/me", headers=admin_headers).status_code == 409
