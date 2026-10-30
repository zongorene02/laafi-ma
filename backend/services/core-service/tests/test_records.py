"""Sauvegarde chiffrée : le serveur stocke un blob OPAQUE, tel quel."""

import base64

from helpers import BACKUP

from app.config import settings
from app.db_models import RecordBackup


def test_backup_round_trip_is_stored_as_is(client, woman, db):
    put = client.put("/records/backup", json=BACKUP, headers=woman["headers"])
    assert put.status_code == 200
    assert put.json()["size_bytes"] == len(base64.b64decode(BACKUP["ciphertext"]))

    got = client.get("/records/backup", headers=woman["headers"]).json()
    assert {k: got[k] for k in BACKUP} == BACKUP
    assert got["updated_at"].endswith("Z")

    stored = db.get(RecordBackup, woman["account_id"])
    assert stored.ciphertext == BACKUP["ciphertext"]  # aucune transformation
    # Le schéma n'a AUCUNE colonne de contenu en clair.
    assert set(RecordBackup.__table__.columns.keys()) == {
        "user_id",
        "ciphertext",
        "nonce",
        "salt",
        "kdf",
        "kdf_iterations",
        "cipher",
        "schema_version",
        "client_updated_at",
        "size_bytes",
        "updated_at",
    }


def test_backup_is_replaced_not_duplicated(client, woman, db):
    client.put("/records/backup", json=BACKUP, headers=woman["headers"])
    client.put("/records/backup", json={**BACKUP, "ciphertext": "bm91dmVhdQ=="}, headers=woman["headers"])
    assert db.query(RecordBackup).count() == 1
    assert client.get("/records/backup", headers=woman["headers"]).json()["ciphertext"] == "bm91dmVhdQ=="


def test_no_backup_is_404_and_delete_is_204(client, woman):
    assert client.get("/records/backup", headers=woman["headers"]).status_code == 404
    client.put("/records/backup", json=BACKUP, headers=woman["headers"])
    assert client.delete("/records/backup", headers=woman["headers"]).status_code == 204
    assert client.get("/records/backup", headers=woman["headers"]).status_code == 404


def test_backup_is_reserved_to_women_accounts(client, agent_headers):
    assert client.get("/records/backup").status_code == 401
    assert client.put("/records/backup", json=BACKUP, headers=agent_headers).status_code == 403


def test_oversized_backup_is_413(client, woman, monkeypatch):
    monkeypatch.setattr(settings, "max_backup_bytes", 10)
    big = base64.b64encode(b"x" * 11).decode()
    assert (
        client.put("/records/backup", json={**BACKUP, "ciphertext": big}, headers=woman["headers"]).status_code == 413
    )


def test_invalid_base64_is_422(client, woman):
    response = client.put("/records/backup", json={**BACKUP, "ciphertext": "pas du base64 !"}, headers=woman["headers"])
    assert response.status_code == 422
