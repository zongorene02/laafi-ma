"""Logique du Space sans modèle : langues, pivot, limites, audio.

Ne demande que numpy et scipy (pas de torch, pas de gradio, pas de carte
graphique) : `python -m pytest hf-space/tests/test_voice_logic.py`."""

import numpy as np
import pytest
import voice_logic as logic


@pytest.mark.parametrize(
    ("source", "target", "expected"),
    [
        ("fr", "fr", []),
        ("fr", "dyu", [("fr", "dyu", False)]),
        ("dyu", "fr", [("dyu", "fr", False)]),
        ("mos", "en", [("mos", "en", True)]),
        ("en", "mos", [("en", "mos", True)]),
        ("fr", "mos", [("fr", "en", False), ("en", "mos", True)]),
        ("mos", "fr", [("mos", "en", True), ("en", "fr", False)]),
        ("mos", "dyu", [("mos", "en", True), ("en", "dyu", False)]),
    ],
)
def test_translation_plan_uses_the_pivot_only_for_moore(source, target, expected):
    assert logic.translation_plan(source, target) == expected


def test_translation_plan_refuses_unknown_languages():
    with pytest.raises(ValueError, match="Langue non supportée : 'bm'"):
        logic.translation_plan("fr", "bm")


def test_language_checks():
    for lang in ("fr", "mos", "dyu"):
        logic.check_asr_lang(lang)
        logic.check_tts_lang(lang)
    with pytest.raises(ValueError, match="reconnaissance vocale"):
        logic.check_asr_lang("en")
    with pytest.raises(ValueError, match="synthèse vocale"):
        logic.check_tts_lang("en")


def test_text_limits():
    assert logic.check_text("a" * logic.MAX_TRANSLATE_CHARS, logic.MAX_TRANSLATE_CHARS)
    with pytest.raises(ValueError, match="trop long"):
        logic.check_text("a" * (logic.MAX_TRANSLATE_CHARS + 1), logic.MAX_TRANSLATE_CHARS)
    with pytest.raises(ValueError):
        logic.check_text(None, 10)


def test_audio_is_converted_to_16k_mono():
    stereo_48k = np.zeros((48000, 2), dtype=np.float32)
    converted = logic.to_mono_16k(stereo_48k, 48000)
    assert converted.ndim == 1 and converted.dtype == np.float32
    assert len(converted) == 16000
    already_ok = np.ones(16000, dtype=np.float32)
    assert np.array_equal(logic.to_mono_16k(already_ok, 16000), already_ok)


def test_int16_conversion_clips():
    out = logic.to_int16(np.array([-2.0, -1.0, 0.0, 1.0, 2.0]))
    assert out.dtype == np.int16
    assert out.tolist() == [-32767, -32767, 0, 32767, 32767]


def test_gpu_durations_stay_short():
    long_audio = np.zeros(16000 * 600, dtype=np.float32)
    assert logic.transcribe_duration(np.zeros(16000 * 5), "fr") < 60
    assert logic.transcribe_duration(long_audio, "mos") == logic.MAX_GPU_SECONDS
    assert logic.translate_duration("x", logic.translation_plan("fr", "mos")) <= 60
    assert logic.synthesize_duration("x" * logic.MAX_SYNTHESIZE_CHARS, "fr") == logic.MAX_GPU_SECONDS
    assert logic.synthesize_duration("Bonjour", "fr") >= 10
