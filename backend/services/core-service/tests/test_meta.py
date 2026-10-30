"""État du service et fichiers audio : la synthèse n'est produite QUE pour un
texte validé, et seulement pour sa version actuelle."""

from helpers import KB_NUTRITION, create_kb_entry, validated_kb_entry

from app.audio_store import synthetic_relative_path


def test_health_without_models(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "translation_model_loaded": False,
        "speech_model_loaded": False,
        "fast_mode_available": False,
        "database": "ok",
    }


def test_health_reports_loaded_models(client, models_loaded):
    body = client.get("/health").json()
    assert body["translation_model_loaded"] is True and body["speech_model_loaded"] is True


def test_media_never_escapes_the_media_directory(client):
    assert client.get("/media/../app/config.py").status_code == 404
    assert client.get("/media/kb/human/inexistant.wav").status_code == 404


def test_synthetic_audio_is_generated_lazily_then_cached(client, validator_headers, models_loaded):
    entry = validated_kb_entry(client, validator_headers)
    url = client.get("/assistant/faq").json()["entries"][0]["audio_url"]
    assert url.startswith("/media/kb/tts/")

    first = client.get(url)
    assert first.status_code == 200
    assert first.content[:4] == b"RIFF"
    assert client.get(url).content == first.content

    # Le texte change : l'ancienne URL ne sert plus rien (404), même en
    # cache — jamais un audio qui ne correspond pas au texte validé.
    payload = {**KB_NUTRITION, "translations": {"fr": {**KB_NUTRITION["translations"]["fr"], "answer": "Nouveau."}}}
    client.put(f"/kb/entries/{entry['id']}", json=payload, headers=validator_headers)
    client.post(f"/kb/entries/{entry['id']}/validate", headers=validator_headers)
    new_url = client.get("/assistant/faq").json()["entries"][0]["audio_url"]
    assert new_url != url
    assert client.get(url).status_code == 404
    assert client.get(new_url).status_code == 200


def test_no_synthesis_for_draft_content(client, validator_headers, models_loaded):
    entry = create_kb_entry(client, validator_headers)
    path = synthetic_relative_path("kb", entry["id"], "fr", KB_NUTRITION["translations"]["fr"]["answer"])
    assert client.get(f"/media/{path}").status_code == 404


def test_no_synthesis_without_speech_model(client, validator_headers):
    entry = validated_kb_entry(client, validator_headers)
    path = synthetic_relative_path("kb", entry["id"], "fr", KB_NUTRITION["translations"]["fr"]["answer"])
    assert client.get(f"/media/{path}").status_code == 503
