"""Voix et traduction à distance (Space Hugging Face), SANS aucun appel réseau.

`gradio_client.Client` est remplacé par une doublure qui note chaque appel :
on vérifie ce qui est envoyé au Space, ce qui est rendu à l'application, et
qu'un Space muet ou en panne donne un 503 propre — exactement comme un
serveur sans modèles."""

import uuid
from pathlib import Path
from typing import Any

import numpy as np
import pytest
import soundfile as sf
from helpers import KB_NUTRITION, create_kb_entry, validated_kb_entry

from app import audio_store, media_service, remote_voice
from app.audio_store import synthetic_relative_path
from app.config import Settings, settings
from app.remote_voice import (
    RemoteSpeechService,
    RemoteTranslationService,
    SpaceConnection,
    VoiceSpaceUnavailable,
)
from app.routers import assistant, kb, meta, translation
from app.speech_service import SpeechService, _build_speech_service
from app.translation_service import TranslationService, _build_translation_service

TOKEN = "hf_secret_token_qui_ne_doit_jamais_sortir"
SPACE = "renezongo/laafi-ma-voice"


class FakeJob:
    def __init__(self, space: "FakeSpace", api_name: str, args: tuple) -> None:
        self.space, self.api_name, self.args = space, api_name, args
        self.cancelled = False

    def result(self, timeout: float | None = None) -> Any:
        self.space.timeouts.append(timeout)
        behaviour = self.space.behaviour.get(self.api_name)
        if isinstance(behaviour, BaseException):
            raise behaviour
        if callable(behaviour):
            return behaviour(*self.args)
        return behaviour

    def cancel(self) -> bool:
        self.cancelled = True
        return True


class FakeSpace:
    """Tient lieu à la fois de `Client` (submit) et de sa fabrique."""

    def __init__(self, tmp_path: Path) -> None:
        self.tmp_path = tmp_path
        self.created: list[tuple[str, str | None]] = []
        self.calls: list[tuple[str, tuple]] = []
        self.jobs: list[FakeJob] = []
        self.timeouts: list[float | None] = []
        self.connect_error: Exception | None = None
        self.received_audio: list[tuple[np.ndarray, int]] = []
        self.behaviour: dict[str, Any] = {
            "/translate": lambda text, src, tgt: f"[{tgt}] {text}",
            "/transcribe": self._transcribe,
            "/synthesize": self._synthesize,
        }

    def factory(self, space: str, token: str | None) -> "FakeSpace":
        self.created.append((space, token))
        if self.connect_error is not None:
            raise self.connect_error
        return self

    def submit(self, *args: Any, api_name: str) -> FakeJob:
        self.calls.append((api_name, args))
        job = FakeJob(self, api_name, args)
        self.jobs.append(job)
        return job

    def close(self) -> None:
        pass

    def _transcribe(self, file_arg: dict, lang: str) -> str:
        audio, rate = sf.read(file_arg["path"], dtype="float32")
        self.received_audio.append((audio, rate))
        return f"  texte {lang}  "

    def _synthesize(self, text: str, lang: str) -> str:
        path = self.tmp_path / f"space-{uuid.uuid4().hex}.wav"
        sf.write(path, np.full(1600, 0.25, dtype=np.float32), 16000, subtype="PCM_16")
        return str(path)


@pytest.fixture
def space(tmp_path) -> FakeSpace:
    return FakeSpace(tmp_path)


@pytest.fixture
def connection(space) -> SpaceConnection:
    return SpaceConnection(SPACE, TOKEN, timeout_seconds=12, client_factory=space.factory)


@pytest.fixture
def remote(client, connection, monkeypatch) -> dict[str, Any]:
    """L'app de test en mode « voix à distance » : les objets utilisés par
    les routeurs et audio_store deviennent les services distants."""
    speech = RemoteSpeechService(connection)
    translator = RemoteTranslationService(connection)
    for module in (translation, assistant, meta, audio_store):
        monkeypatch.setattr(module, "speech_service", speech)
    for module in (translation, assistant, kb, meta):
        monkeypatch.setattr(module, "translation_service", translator)
    monkeypatch.setattr(
        media_service, "any_audio_or_video_to_wav_array", lambda raw, hint="input": (np.zeros(16000), 16000)
    )
    return {"speech": speech, "translation": translator}


# --- Services seuls ------------------------------------------------------------


def test_translate_calls_the_space_once_then_uses_the_cache(space, connection):
    service = RemoteTranslationService(connection)
    assert service.is_loaded
    assert service.translate("Bonjour", "fr", "mos") == "[mos] Bonjour"
    assert service.translate("Bonjour", "fr", "mos") == "[mos] Bonjour"
    assert space.calls == [("/translate", ("Bonjour", "fr", "mos"))]
    assert service.cache_stats() == {"entries": 1, "capacity": 512, "hits": 1, "misses": 1}
    # Le client est créé avec le jeton, une seule fois.
    assert space.created == [(SPACE, TOKEN)]


def test_translate_refuses_like_the_local_engine_without_calling_the_space(space, connection):
    service = RemoteTranslationService(connection)
    assert service.translate("Bonjour", "fr", "fr") == "Bonjour"
    with pytest.raises(ValueError, match="Langue non supportée"):
        service.translate("Bonjour", "fr", "bm")
    with pytest.raises(ValueError, match="trop long"):
        service.translate("a" * 5001, "fr", "dyu")
    assert space.calls == []


def test_language_codes_are_sent_unchanged(space, connection):
    """Le Space attend les codes de l'API (fr, mos, dyu) et fait lui-même la
    correspondance avec NLLB, Whisper et MMS."""
    speech = RemoteSpeechService(connection)
    speech.transcribe(np.zeros(16000), 16000, "dyu")
    speech.synthesize("I ni ce", "mos")
    RemoteTranslationService(connection).translate("Ne y windiga", "mos", "fr")
    assert [(api, args[-1]) for api, args in space.calls] == [("/transcribe", "dyu"), ("/synthesize", "mos")] + [
        ("/translate", "fr")
    ]
    assert space.calls[-1][1] == ("Ne y windiga", "mos", "fr")


def test_transcribe_sends_a_16k_mono_wav_and_deletes_it(space, connection):
    speech = RemoteSpeechService(connection)
    stereo_8k = np.zeros((8000, 2), dtype=np.float32)
    assert speech.transcribe(stereo_8k, 8000, "mos") == "texte mos"
    audio, rate = space.received_audio[0]
    assert rate == 16000 and audio.ndim == 1 and len(audio) == 16000
    sent_path = Path(space.calls[0][1][0]["path"])
    assert not sent_path.exists()


def test_transcribe_refuses_unknown_language(space, connection):
    with pytest.raises(ValueError, match="reconnaissance vocale"):
        RemoteSpeechService(connection).transcribe(np.zeros(160), 16000, "en")
    assert space.calls == []


def test_synthesize_returns_float_audio_and_deletes_the_download(space, connection):
    audio, rate = RemoteSpeechService(connection).synthesize("Bonjour", "fr")
    assert rate == 16000 and audio.dtype == np.float32 and len(audio) == 1600
    assert abs(float(audio[0]) - 0.25) < 0.01
    assert list(space.tmp_path.glob("space-*.wav")) == []


def test_synthesize_refuses_before_calling_the_space(space, connection):
    speech = RemoteSpeechService(connection)
    with pytest.raises(ValueError, match="synthèse vocale"):
        speech.synthesize("Hello", "en")
    with pytest.raises(ValueError, match="trop long"):
        speech.synthesize("a" * 20001, "fr")
    assert space.calls == []


def test_timeout_gives_503_and_cancels_the_job(space, connection):
    space.behaviour["/translate"] = TimeoutError()
    with pytest.raises(VoiceSpaceUnavailable) as raised:
        RemoteTranslationService(connection).translate("Bonjour", "fr", "mos")
    assert raised.value.status_code == 503
    assert space.jobs[0].cancelled
    # Le délai de la configuration est bien transmis à l'attente du résultat.
    assert 1 <= space.timeouts[0] <= 12


def test_after_a_failure_requests_fail_fast_for_a_while(space, connection):
    space.behaviour["/translate"] = RuntimeError("queue full")
    service = RemoteTranslationService(connection)
    with pytest.raises(VoiceSpaceUnavailable):
        service.translate("Bonjour", "fr", "mos")
    with pytest.raises(VoiceSpaceUnavailable):
        service.translate("Bonsoir", "fr", "mos")
    assert len(space.calls) == 1  # le second appel n'a pas attendu le Space


def test_unknown_space_is_not_retried(space, connection, monkeypatch):
    class RepositoryNotFoundError(Exception):
        pass

    sleeps: list[float] = []
    monkeypatch.setattr(remote_voice.time, "sleep", sleeps.append)
    space.connect_error = RepositoryNotFoundError("404")
    with pytest.raises(VoiceSpaceUnavailable):
        RemoteTranslationService(connection).translate("Bonjour", "fr", "mos")
    assert len(space.created) == 1 and sleeps == []


def test_sleeping_space_is_retried_until_the_deadline(space, connection, monkeypatch):
    sleeps: list[float] = []
    clock = {"now": 1000.0}

    def fake_sleep(seconds: float) -> None:
        sleeps.append(seconds)
        clock["now"] += seconds

    monkeypatch.setattr(remote_voice.time, "sleep", fake_sleep)
    monkeypatch.setattr(remote_voice.time, "monotonic", lambda: clock["now"])
    space.connect_error = ValueError("Could not fetch config")
    with pytest.raises(VoiceSpaceUnavailable):
        RemoteTranslationService(connection).translate("Bonjour", "fr", "mos")
    # 12 s de délai, une tentative toutes les 5 s : à 0, 5 et 10 s.
    assert len(space.created) == 3 and sleeps == [5.0, 5.0]


def test_token_never_appears_in_logs_or_errors(space, connection, capsys, caplog):
    space.behaviour["/translate"] = RuntimeError(f"401 Unauthorized, token={TOKEN}")
    with pytest.raises(VoiceSpaceUnavailable) as raised:
        RemoteTranslationService(connection).translate("Bonjour", "fr", "mos")
    captured = capsys.readouterr()
    assert TOKEN not in captured.out + captured.err + caplog.text
    assert TOKEN not in str(raised.value.detail)
    assert raised.value.__cause__ is None and raised.value.__suppress_context__
    assert TOKEN not in repr(connection)
    # Le texte de la question n'est pas journalisé non plus.
    assert "Bonjour" not in captured.out


def test_token_is_hidden_in_settings_repr():
    configured = Settings(hf_token=TOKEN, voice_space=SPACE)
    assert TOKEN not in repr(configured) and TOKEN not in str(configured.model_dump())
    assert configured.hf_token.get_secret_value() == TOKEN


# --- Choix local / distant -------------------------------------------------------


def test_default_without_space_keeps_local_services(monkeypatch):
    monkeypatch.setattr(settings, "voice_space", "")
    monkeypatch.setattr(settings, "load_models_on_startup", False)
    assert type(_build_speech_service()) is SpeechService
    assert type(_build_translation_service()) is TranslationService


def test_space_is_used_only_without_local_models(monkeypatch):
    monkeypatch.setattr(remote_voice, "_shared_connection", None)
    monkeypatch.setattr(settings, "voice_space", SPACE)
    monkeypatch.setattr(settings, "load_models_on_startup", False)
    speech, translator = _build_speech_service(), _build_translation_service()
    assert isinstance(speech, RemoteSpeechService) and isinstance(translator, RemoteTranslationService)
    assert speech._space is translator._space  # une seule connexion partagée

    monkeypatch.setattr(settings, "load_models_on_startup", True)
    assert type(_build_speech_service()) is SpeechService
    assert type(_build_translation_service()) is TranslationService


# --- À travers l'API ---------------------------------------------------------------


def test_health_reports_remote_backend(client, remote, space):
    body = client.get("/health").json()
    assert body["voice_backend"] == "remote"
    assert body["translation_model_loaded"] is True and body["speech_model_loaded"] is True
    assert space.created == []  # /health ne réveille pas le Space


def test_api_translate_and_text_to_speech_through_the_space(client, remote):
    response = client.post("/translate", json={"text": "Bonjour", "source_lang": "fr", "target_lang": "mos"})
    assert response.status_code == 200, response.text
    assert response.json()["translation"] == "[mos] Bonjour"

    audio = client.post("/text-to-speech", json={"text": "Bonjour", "language": "fr"})
    assert audio.status_code == 200
    assert audio.content[:4] == b"RIFF"


def test_api_voice_question_through_the_space(client, remote):
    response = client.post(
        "/assistant/transcribe", files={"audio": ("q.wav", b"RIFF....", "audio/wav")}, data={"lang": "mos"}
    )
    assert response.status_code == 200, response.text
    assert response.json() == {"transcript": "texte mos", "question_fr": "[fr] texte mos"}


def test_api_returns_503_when_the_space_times_out(client, remote, space, validator_headers):
    space.behaviour["/translate"] = TimeoutError()
    response = client.post("/translate", json={"text": "Bonjour", "source_lang": "fr", "target_lang": "mos"})
    assert response.status_code == 503
    assert response.json()["detail"] == remote_voice.VOICE_SPACE_UNAVAILABLE
    # Pendant la pause qui suit l'échec, tout ce qui passe par le Space
    # répond 503 sans attendre.
    assert client.post("/text-to-speech", json={"text": "Bonjour", "language": "fr"}).status_code == 503
    assert client.post("/assistant/ask-text", json={"text": "Ne y windiga", "lang": "mos"}).status_code == 503
    entry = create_kb_entry(client, validator_headers)
    assert client.post(f"/kb/entries/{entry['id']}/translate", headers=validator_headers).status_code == 503


def test_french_text_question_never_needs_the_space(client, remote, space):
    space.behaviour["/translate"] = TimeoutError()
    response = client.post("/assistant/ask-text", json={"text": "Que manger enceinte ?", "lang": "fr"})
    assert response.status_code == 200
    assert space.calls == []


def test_console_kb_translation_through_the_space(client, remote, space, validator_headers):
    fr = KB_NUTRITION["translations"]["fr"]
    entry = create_kb_entry(client, validator_headers, {**KB_NUTRITION, "translations": {"fr": fr}})
    response = client.post(f"/kb/entries/{entry['id']}/translate", headers=validator_headers)
    assert response.status_code == 200, response.text
    translations = response.json()["translations"]
    assert translations["mos"]["answer"] == f"[mos] {fr['answer']}"
    assert translations["dyu"]["question"] == f"[dyu] {fr['question']}"
    assert translations["mos"]["machine_translated"] is True
    assert {args[2] for api, args in space.calls} == {"mos", "dyu"}


def test_synthetic_audio_is_cached_on_disk_to_save_gpu_quota(client, remote, space, validator_headers):
    validated_kb_entry(client, validator_headers)
    url = client.get("/assistant/faq").json()["entries"][0]["audio_url"]
    assert url.startswith("/media/kb/tts/")
    first = client.get(url)
    assert first.status_code == 200 and first.content[:4] == b"RIFF"
    assert client.get(url).content == first.content
    assert [api for api, _ in space.calls] == ["/synthesize"]  # une seule fois


def test_synthetic_audio_gives_503_when_the_space_fails(client, remote, space, validator_headers):
    space.behaviour["/synthesize"] = ConnectionError()
    entry = validated_kb_entry(client, validator_headers)
    path = synthetic_relative_path("kb", entry["id"], "fr", KB_NUTRITION["translations"]["fr"]["answer"])
    assert client.get(f"/media/{path}").status_code == 503
