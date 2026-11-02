"""Capsules : seules les capsules validées sont publiques ; le personnel de
contenu voit les brouillons via `?status=`."""

import io

CAPSULE = {
    "track": "future_mere",
    "order": 1,
    "translations": {"fr": {"title": "Titre de test", "text": "Texte de test."}},
    "quiz": [{"question": {"fr": "Question ?"}, "choices": [{"fr": "Oui"}, {"fr": "Non"}], "correct_index": 0}],
}


def _create(client, headers, payload=None):
    response = client.post("/learn/capsules", json=payload or CAPSULE, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def test_only_validated_capsules_are_public(client, validator_headers):
    capsule = _create(client, validator_headers)
    assert capsule["status"] == "draft"
    assert capsule["license"] == "CC-BY-4.0"
    assert client.get("/learn/capsules").json() == []
    # Même en le demandant, le public ne voit pas les brouillons.
    assert client.get("/learn/capsules", params={"status": "draft"}).json() == []

    validated = client.post(f"/learn/capsules/{capsule['id']}/validate", headers=validator_headers).json()
    assert validated["status"] == "validated"
    public = client.get("/learn/capsules", params={"lang": "fr", "track": "future_mere"}).json()
    assert [c["id"] for c in public] == [capsule["id"]]
    # Pas de texte mooré : la capsule reste listée, son texte français sert de repli.
    (mos,) = client.get("/learn/capsules", params={"lang": "mos"}).json()
    assert mos["translations"]["fr"]["text"] == "Texte de test."
    assert mos["translations"]["mos"]["text"] == ""
    assert mos["provisional"] is False


def test_content_staff_can_list_drafts(client, validator_headers, admin_headers):
    capsule = _create(client, validator_headers)
    drafts = client.get("/learn/capsules", params={"status": "draft"}, headers=admin_headers).json()
    assert [c["id"] for c in drafts] == [capsule["id"]]


def test_editing_a_validated_capsule_sends_it_back_to_draft(client, validator_headers):
    capsule = _create(client, validator_headers)
    client.post(f"/learn/capsules/{capsule['id']}/validate", headers=validator_headers)
    edited = client.put(
        f"/learn/capsules/{capsule['id']}",
        json={**CAPSULE, "translations": {"fr": {"title": "Nouveau titre", "text": "Texte de test."}}},
        headers=validator_headers,
    ).json()
    assert edited["status"] == "draft"
    assert client.get("/learn/capsules").json() == []


def test_validation_requires_french_and_quiz_must_be_consistent(client, validator_headers):
    no_french = _create(client, validator_headers, {**CAPSULE, "translations": {}})
    assert client.post(f"/learn/capsules/{no_french['id']}/validate", headers=validator_headers).status_code == 409

    bad_quiz = {
        **CAPSULE,
        "quiz": [{"question": {"fr": "Q"}, "choices": [{"fr": "A"}, {"fr": "B"}], "correct_index": 5}],
    }
    assert client.post("/learn/capsules", json=bad_quiz, headers=validator_headers).status_code == 422


def test_writes_are_reserved_to_content_staff(client, agent_headers, woman):
    assert client.post("/learn/capsules", json=CAPSULE).status_code == 401
    assert client.post("/learn/capsules", json=CAPSULE, headers=agent_headers).status_code == 403
    assert client.post("/learn/capsules", json=CAPSULE, headers=woman["headers"]).status_code == 403


def test_audio_and_delete(client, validator_headers, models_loaded):
    capsule = _create(client, validator_headers)
    with_audio = client.post(
        f"/learn/capsules/{capsule['id']}/audio/fr",
        files={"audio": ("voix.ogg", io.BytesIO(b"audio"), "audio/ogg")},
        headers=validator_headers,
    ).json()
    assert with_audio["translations"]["fr"]["audio_kind"] == "human"
    assert client.delete(f"/learn/capsules/{capsule['id']}", headers=validator_headers).status_code == 204


def test_include_drafts_is_honoured_for_content_staff_only(client, validator_headers, agent_headers, woman):
    draft = _create(client, validator_headers)
    validated = _create(client, validator_headers)
    client.post(f"/learn/capsules/{validated['id']}/validate", headers=validator_headers)
    params = {"include_drafts": "true"}

    staff_view = client.get("/learn/capsules", params=params, headers=validator_headers).json()
    assert {c["id"] for c in staff_view} == {draft["id"], validated["id"]}
    for headers in ({}, agent_headers, woman["headers"]):
        assert [c["id"] for c in client.get("/learn/capsules", params=params, headers=headers).json()] == [
            validated["id"]
        ]


def test_archive_and_license_kept_when_omitted(client, validator_headers):
    capsule = _create(client, validator_headers, {**CAPSULE, "license": "CC-BY-SA-4.0"})
    body = {key: value for key, value in CAPSULE.items() if key != "license"}
    kept = client.put(f"/learn/capsules/{capsule['id']}", json=body, headers=validator_headers).json()
    assert kept["license"] == "CC-BY-SA-4.0"
    archived = client.post(f"/learn/capsules/{capsule['id']}/archive", headers=validator_headers).json()
    assert archived["status"] == "archived"
