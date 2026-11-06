"""Contrat des quatre points d'entrée du Space, avec de FAUX modèles.

Lance la vraie interface Gradio (app.py) sur la machine, mais remplace
`models.py` (torch, carte graphique, plusieurs Go) par des doublures, puis
l'appelle avec `gradio_client`, comme le fait l'API. Vérifie les noms
(`api_name`), les types d'entrée et de sortie, et les refus.

Demande gradio et gradio_client (ignoré sinon) :
`pip install gradio==6.31.0 soundfile scipy pytest`."""

import sys
import types

import numpy as np
import pytest

gr = pytest.importorskip("gradio")
gradio_client = pytest.importorskip("gradio_client")
sf = pytest.importorskip("soundfile")

CALLS: list[tuple] = []


def _fake_models() -> types.ModuleType:
    fake = types.ModuleType("models")
    fake.DEVICE = "cpu"
    fake.LOADED_MODELS = {"fake": True}

    def transcribe_gpu(audio, lang):
        CALLS.append(("transcribe", len(audio), str(audio.dtype), lang))
        return f"texte {lang}"

    def translate_gpu(text, plan):
        CALLS.append(("translate", text, plan))
        return f"[{plan[-1][1]}] {text}"

    def synthesize_gpu(text, lang):
        CALLS.append(("synthesize", text, lang))
        return 16000, np.full(1600, 0.5, dtype=np.float32)

    fake.transcribe_gpu = transcribe_gpu
    fake.translate_gpu = translate_gpu
    fake.synthesize_gpu = synthesize_gpu
    return fake


@pytest.fixture(scope="module")
def client():
    sys.modules["models"] = _fake_models()
    if "spaces" not in sys.modules:
        try:
            import spaces  # noqa: F401
        except ImportError:
            sys.modules["spaces"] = types.ModuleType("spaces")
    import app

    _, url, _ = app.demo.launch(prevent_thread_lock=True, server_name="127.0.0.1", quiet=True)
    try:
        yield gradio_client.Client(url, verbose=False, analytics_enabled=False)
    finally:
        app.demo.close()


def test_health(client):
    body = client.predict(api_name="/health")
    assert body["status"] == "ok"
    assert body["languages"] == ["fr", "mos", "dyu"]


def test_translate_sends_the_pivot_plan(client):
    CALLS.clear()
    assert client.predict("Bonjour", "fr", "mos", api_name="/translate") == "[mos] Bonjour"
    assert CALLS == [("translate", "Bonjour", [("fr", "en", False), ("en", "mos", True)])]


def test_translate_same_language_uses_no_gpu(client):
    CALLS.clear()
    assert client.predict("Bonjour", "fr", "fr", api_name="/translate") == "Bonjour"
    assert CALLS == []


def test_translate_refuses_too_long_text(client):
    with pytest.raises(gradio_client.exceptions.AppError, match="trop long"):
        client.predict("a" * 5001, "fr", "dyu", api_name="/translate")


def test_transcribe_receives_16k_mono_float(client, tmp_path):
    CALLS.clear()
    path = tmp_path / "question.wav"
    sf.write(path, np.zeros((8000, 2), dtype=np.float32), 8000, subtype="PCM_16")
    text = client.predict(gradio_client.handle_file(str(path)), "mos", api_name="/transcribe")
    assert text == "texte mos"
    assert CALLS == [("transcribe", 16000, "float32", "mos")]


def test_synthesize_returns_a_wav_file(client):
    result = client.predict("Bonjour", "dyu", api_name="/synthesize")
    audio, rate = sf.read(result, dtype="float32")
    assert rate == 16000 and len(audio) == 1600
    assert abs(float(audio[0]) - 0.5) < 0.01


def test_synthesize_refuses_unknown_language(client):
    # Refusé par la liste de choix de Gradio, ou par notre propre contrôle.
    with pytest.raises(gradio_client.exceptions.AppError):
        client.predict("Hello", "en", api_name="/synthesize")
