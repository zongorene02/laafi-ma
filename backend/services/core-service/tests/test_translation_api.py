"""Traduction : /translate et /text-to-speech publics (bouton « Écouter »),
voix -> texte et voix -> voix réservés au rôle `agent`, choix explicite du moteur
("verified" par défaut, "fast" seulement sur demande), et la réponse dit
toujours quel moteur a traduit. Aucun modèle chargé : doublures."""

import io

import pytest

from app import main
from app.fast_translation_service import fast_translation_service
from app.translation_service import translation_service


@pytest.fixture
def engines(models_loaded, monkeypatch):
    calls: list[str] = []

    def verified(text, source_lang, target_lang):
        calls.append("verified")
        return f"[verifie] {text}"

    def fast(text, source_lang, target_lang):
        calls.append("fast")
        return f"[rapide] {text}"

    monkeypatch.setattr(translation_service, "translate", verified)
    monkeypatch.setattr(fast_translation_service, "translate", fast)
    monkeypatch.setattr(fast_translation_service, "is_available", lambda: True)
    return calls


def _translate(client, headers, **extra):
    return client.post(
        "/translate", json={"text": "Bonjour", "source_lang": "fr", "target_lang": "mos", **extra}, headers=headers
    )


def test_text_translation_and_speech_are_public(client, woman, engines):
    # Bouton « Écouter » : aucun compte requis, et un jeton de femme ne gêne pas.
    assert _translate(client, {}).status_code == 200
    assert _translate(client, woman["headers"]).status_code == 200
    response = client.post("/text-to-speech", json={"text": "Bonjour", "language": "fr"})
    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/wav"


def test_voice_input_is_reserved_to_agents(client, validator_headers, woman, engines):
    form = {"language": "fr"}
    files = {"audio": ("a.wav", io.BytesIO(b"RIFF"), "audio/wav")}
    assert client.post("/speech-to-text", data=form, files=files).status_code == 401
    assert client.post("/speech-to-text", data=form, files=files, headers=validator_headers).status_code == 403
    assert client.post("/speech-to-text", data=form, files=files, headers=woman["headers"]).status_code == 403
    voice = {"source_lang": "fr", "target_lang": "mos"}
    assert client.post("/translate-voice", data=voice, files=files, headers=woman["headers"]).status_code == 403


def test_default_mode_is_verified(client, agent_headers, engines):
    body = _translate(client, agent_headers).json()
    assert body == {"translation": "[verifie] Bonjour", "source_lang": "fr", "target_lang": "mos", "mode": "verified"}
    assert engines == ["verified"]


def test_fast_mode_only_when_asked(client, agent_headers, engines):
    body = _translate(client, agent_headers, mode="fast").json()
    assert body["mode"] == "fast"
    assert engines == ["fast"]


def test_fast_mode_refuses_clearly_when_absent(client, agent_headers, engines, monkeypatch):
    monkeypatch.setattr(fast_translation_service, "is_available", lambda: False)
    response = _translate(client, agent_headers, mode="fast")
    assert response.status_code == 503
    assert "rapide" in response.json()["detail"].lower()
    assert engines == []


def test_verified_mode_without_model_is_503(client, agent_headers):
    assert _translate(client, agent_headers).status_code == 503


@pytest.mark.parametrize("lang", ["en", "bam", "es"])
def test_languages_outside_laafi_ma_are_400(client, agent_headers, engines, lang):
    assert _translate(client, agent_headers, target_lang=lang).status_code == 400


def test_unknown_mode_is_422(client, agent_headers, engines):
    assert _translate(client, agent_headers, mode="turbo").status_code == 422


@pytest.mark.parametrize("mode", ["verified", "fast"])
def test_voice_pipeline_states_the_engine(client, agent_headers, engines, mode):
    response = client.post(
        "/translate-voice",
        files={"audio": ("phrase.wav", io.BytesIO(b"audio"), "audio/wav")},
        data={"source_lang": "fr", "target_lang": "mos", "mode": mode},
        headers=agent_headers,
    )
    assert response.status_code == 200
    assert response.headers["X-Translation-Mode"] == mode
    signature = "rapide" if mode == "fast" else "verifie"
    assert response.headers["X-Translated-Text"] == f"%5B{signature}%5D%20Bonjour"
    assert response.content[:4] == b"RIFF"


def test_speech_to_text_and_text_to_speech(client, agent_headers, engines):
    stt = client.post(
        "/speech-to-text",
        files={"audio": ("phrase.wav", io.BytesIO(b"audio"), "audio/wav")},
        data={"language": "dyu"},
        headers=agent_headers,
    )
    assert stt.json() == {"text": "Bonjour"}
    tts = client.post("/text-to-speech", json={"text": "Bonjour", "language": "mos"}, headers=agent_headers)
    assert tts.headers["content-type"] == "audio/wav"


def test_voice_without_speech_model_is_503(client, agent_headers):
    response = client.post("/text-to-speech", json={"text": "Bonjour", "language": "fr"}, headers=agent_headers)
    assert response.status_code == 503


def test_translation_headers_are_readable_by_a_browser():
    cors = next(m for m in main.app.user_middleware if m.cls is main.CORSMiddleware)
    assert "X-Translation-Mode" in cors.kwargs["expose_headers"]
