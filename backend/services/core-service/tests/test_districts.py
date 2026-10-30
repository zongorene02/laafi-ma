"""Districts : liste vide par défaut, gérée par les admins."""

from conftest import create_staff

from app.db_models import User

DISTRICT = {"name": "District de test", "region": "Région de test"}


def test_empty_until_an_admin_enters_the_real_list(client):
    assert client.get("/districts").json() == []


def test_admin_crud(client, admin_headers):
    created = client.post("/districts", json=DISTRICT, headers=admin_headers)
    assert created.status_code == 201
    district = created.json()
    assert client.post("/districts", json=DISTRICT, headers=admin_headers).status_code == 409

    renamed = client.put(f"/districts/{district['id']}", json={**DISTRICT, "name": "Renommé"}, headers=admin_headers)
    assert renamed.json()["name"] == "Renommé"
    assert client.get("/districts").json() == [{"id": district["id"], "name": "Renommé", "region": "Région de test"}]


def test_deleting_a_district_detaches_staff(client, admin_headers, db):
    district = client.post("/districts", json=DISTRICT, headers=admin_headers).json()
    agent = create_staff(db, "agent", district_id=district["id"])
    assert client.delete(f"/districts/{district['id']}", headers=admin_headers).status_code == 204
    db.expire_all()
    assert db.get(User, agent.id).district_id is None


def test_only_admins_can_write(client, validator_headers):
    assert client.post("/districts", json=DISTRICT).status_code == 401
    assert client.post("/districts", json=DISTRICT, headers=validator_headers).status_code == 403
