"""Administration : comptes du personnel (jamais les femmes individuellement),
statistiques, état du service."""

import pytest
from conftest import login_headers


def _create_user(client, headers, **overrides):
    payload = {
        "email": "agent@laafi-ma.bf",
        "full_name": "Agent Test",
        "role": "agent",
        "district_id": None,
        **overrides,
    }
    return client.post("/admin/users", json=payload, headers=headers)


@pytest.mark.parametrize("path", ["/admin/users", "/admin/stats", "/admin/health"])
def test_admin_routes_are_reserved_to_admins(client, validator_headers, agent_headers, woman, path):
    assert client.get(path).status_code == 401
    for headers in (validator_headers, agent_headers, woman["headers"]):
        assert client.get(path, headers=headers).status_code == 403


def test_women_are_never_listed(client, admin_headers, woman):
    users = client.get("/admin/users", headers=admin_headers).json()
    assert all(u["role"] != "woman" for u in users)
    assert woman["account_id"] not in [u["id"] for u in users]
    assert client.get("/admin/users", params={"role": "woman"}, headers=admin_headers).status_code == 422
    # ...ni modifiables ou supprimables par leur identifiant.
    assert (
        client.patch(f"/admin/users/{woman['account_id']}", json={"active": False}, headers=admin_headers).status_code
        == 404
    )
    assert client.delete(f"/admin/users/{woman['account_id']}", headers=admin_headers).status_code == 404


def test_create_user_with_a_temporary_password(client, admin_headers):
    response = _create_user(client, admin_headers)
    assert response.status_code == 201
    body = response.json()
    assert body["user"]["role"] == "agent"
    assert body["user"]["active"] is True
    assert len(body["temporary_password"]) >= 10
    login_headers(client, "agent@laafi-ma.bf", body["temporary_password"])

    assert _create_user(client, admin_headers, email="AGENT@laafi-ma.bf").status_code == 409
    assert _create_user(client, admin_headers, email="x@laafi-ma.bf", role="woman").status_code == 422
    assert _create_user(client, admin_headers, email="y@laafi-ma.bf", district_id="inconnu").status_code == 422

    agents = client.get("/admin/users", params={"role": "agent"}, headers=admin_headers).json()
    assert [u["email"] for u in agents] == ["agent@laafi-ma.bf"]


def test_patch_reset_and_delete(client, admin_headers):
    user = _create_user(client, admin_headers).json()["user"]
    district = client.post("/districts", json={"name": "D", "region": "R"}, headers=admin_headers).json()

    patched = client.patch(
        f"/admin/users/{user['id']}",
        json={"role": "validator", "district_id": district["id"], "full_name": "Nouveau nom"},
        headers=admin_headers,
    ).json()
    assert (patched["role"], patched["district_id"], patched["full_name"]) == (
        "validator",
        district["id"],
        "Nouveau nom",
    )
    cleared = client.patch(f"/admin/users/{user['id']}", json={"district_id": None}, headers=admin_headers).json()
    assert cleared["district_id"] is None and cleared["role"] == "validator"

    reset = client.post(f"/admin/users/{user['id']}/reset-password", headers=admin_headers).json()
    login_headers(client, "agent@laafi-ma.bf", reset["temporary_password"])

    deactivated = client.patch(f"/admin/users/{user['id']}", json={"active": False}, headers=admin_headers).json()
    assert deactivated["active"] is False
    assert client.delete(f"/admin/users/{user['id']}", headers=admin_headers).status_code == 204


def test_an_admin_cannot_lock_themselves_out(client, admin_headers):
    me = client.get("/auth/me", headers=admin_headers).json()
    assert client.patch(f"/admin/users/{me['id']}", json={"role": "agent"}, headers=admin_headers).status_code == 400
    assert client.patch(f"/admin/users/{me['id']}", json={"active": False}, headers=admin_headers).status_code == 400
    assert client.delete(f"/admin/users/{me['id']}", headers=admin_headers).status_code == 400


def test_stats(client, admin_headers, woman, validator_headers):
    client.post("/events", json={"events": [{"type": "app_opened", "lang": "fr", "occurred_on": "2026-10-28"}]})
    stats = client.get("/admin/stats", headers=admin_headers).json()
    assert stats["women_accounts"] == 1
    assert stats["validators"] == 1
    assert stats["agents"] == 0
    assert stats["kb"] == {"draft": 0, "sourced": 0, "validated": 0}
    assert stats["capsules"] == {"draft": 0, "sourced": 0, "validated": 0}
    assert stats["unanswered_open"] == 0
    assert stats["events_last_30_days"] in (0, 1)  # dépend de la date du jour


def test_health_adds_disk_checks(client, admin_headers):
    body = client.get("/admin/health", headers=admin_headers).json()
    assert body["database"] == "ok"
    assert body["disk"]["media_dir_writable"] is True
    assert body["disk"]["free_bytes"] > 0
