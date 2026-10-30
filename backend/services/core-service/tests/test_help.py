"""Annuaire d'aide : lecture publique (services actifs), écriture admin."""

SERVICE = {
    "name": "Centre de test",
    "category": "vbg_center",
    "phone": "00 00 00 00",
    "city": "Ville de test",
    "region": "Région de test",
    "free_call": False,
    "languages": ["fr", "mos"],
}
NATIONAL = {**SERVICE, "name": "Ligne nationale de test", "category": "hotline", "city": None, "region": None}


def _create(client, headers, payload):
    response = client.post("/help/services", json=payload, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def test_public_listing_shows_active_services_only(client, admin_headers):
    active = _create(client, admin_headers, SERVICE)
    _create(client, admin_headers, {**SERVICE, "name": "Fermé", "active": False})
    listed = client.get("/help/services").json()
    assert [s["id"] for s in listed] == [active["id"]]
    assert listed[0]["verified_at"] is None


def test_city_filter_keeps_national_services(client, admin_headers):
    local = _create(client, admin_headers, SERVICE)
    national = _create(client, admin_headers, NATIONAL)
    _create(client, admin_headers, {**SERVICE, "city": "Autre ville"})
    ids = {s["id"] for s in client.get("/help/services", params={"city": "ville de TEST"}).json()}
    assert ids == {local["id"], national["id"]}
    by_category = client.get("/help/services", params={"category": "hotline"}).json()
    assert [s["id"] for s in by_category] == [national["id"]]


def test_verify_then_changing_the_phone_unverifies(client, admin_headers):
    service = _create(client, admin_headers, SERVICE)
    verified = client.post(f"/help/services/{service['id']}/verify", headers=admin_headers).json()
    assert verified["verified_at"] is not None

    same_phone = client.put(
        f"/help/services/{service['id']}", json={**SERVICE, "hours": "8h-17h"}, headers=admin_headers
    )
    assert same_phone.json()["verified_at"] is not None
    new_phone = client.put(
        f"/help/services/{service['id']}", json={**SERVICE, "phone": "11 11 11 11"}, headers=admin_headers
    )
    assert new_phone.json()["verified_at"] is None


def test_delete(client, admin_headers):
    service = _create(client, admin_headers, SERVICE)
    assert client.delete(f"/help/services/{service['id']}", headers=admin_headers).status_code == 204
    assert client.delete(f"/help/services/{service['id']}", headers=admin_headers).status_code == 404


def test_only_admins_can_write(client, validator_headers, agent_headers):
    assert client.post("/help/services", json=SERVICE).status_code == 401
    assert client.post("/help/services", json=SERVICE, headers=validator_headers).status_code == 403
    assert client.post("/help/services", json=SERVICE, headers=agent_headers).status_code == 403


def test_include_inactive_is_honoured_for_admins_only(client, admin_headers, validator_headers):
    _create(client, admin_headers, SERVICE)
    _create(client, admin_headers, {**SERVICE, "name": "Fermé", "active": False})
    params = {"include_inactive": "true"}
    assert len(client.get("/help/services", params=params, headers=admin_headers).json()) == 2
    assert len(client.get("/help/services", params=params, headers=validator_headers).json()) == 1
    assert len(client.get("/help/services", params=params).json()) == 1


def test_emergency_category_is_accepted_and_filterable(client, admin_headers):
    _create(client, admin_headers, NATIONAL)
    emergency = _create(client, admin_headers, {**NATIONAL, "name": "Urgences de test", "category": "emergency"})
    assert emergency["category"] == "emergency"
    listed = client.get("/help/services", params={"category": "emergency"}).json()
    assert [s["id"] for s in listed] == [emergency["id"]]
    assert (
        client.post("/help/services", json={**SERVICE, "category": "bidon"}, headers=admin_headers).status_code == 422
    )
