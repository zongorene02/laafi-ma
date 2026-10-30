"""Fabriques de données de test partagées (contenus validés, etc.)."""

from typing import Any

from fastapi.testclient import TestClient

KB_NUTRITION: dict[str, Any] = {
    "topic": "nutrition",
    "is_danger_topic": False,
    "translations": {
        "fr": {
            "question": "Que dois-je manger pendant la grossesse ?",
            "variants": ["Quels aliments manger quand on est enceinte"],
            "answer": "Réponse de test validée (fr).",
        },
        "mos": {"question": "Question de test (mos)", "variants": [], "answer": "Réponse de test (mos)"},
    },
    "source": "Source de test",
}

BACKUP: dict[str, Any] = {
    "ciphertext": "Y2hpZmZyZQ==",
    "nonce": "bm9uY2U=",
    "salt": "c2Vs",
    "kdf": "pbkdf2-sha256",
    "kdf_iterations": 310000,
    "cipher": "aes-256-gcm",
    "schema_version": 1,
    "client_updated_at": "2026-10-29T10:15:00Z",
}

DANGER_BLEEDING: dict[str, Any] = {
    "translations": {"fr": {"label": "Saignement pendant la grossesse", "advice": "Allez au centre de santé."}},
    "keywords_fr": ["saigne", "saignement", "sang"],
    "source": "Source de test",
}


def create_kb_entry(client: TestClient, headers: dict[str, str], payload: dict[str, Any] | None = None) -> dict:
    response = client.post("/kb/entries", json=payload or KB_NUTRITION, headers=headers)
    assert response.status_code == 201, response.text
    return response.json()


def validated_kb_entry(client: TestClient, headers: dict[str, str], payload: dict[str, Any] | None = None) -> dict:
    entry = create_kb_entry(client, headers, payload)
    response = client.post(f"/kb/entries/{entry['id']}/validate", headers=headers)
    assert response.status_code == 200, response.text
    return response.json()


def create_danger_sign(client: TestClient, headers: dict[str, str], validate: bool = True) -> dict:
    response = client.post("/kb/danger-signs", json=DANGER_BLEEDING, headers=headers)
    assert response.status_code == 201, response.text
    sign = response.json()
    if validate:
        response = client.post(f"/kb/danger-signs/{sign['id']}/validate", headers=headers)
        assert response.status_code == 200, response.text
        sign = response.json()
    return sign
