"""Le Space Hugging Face (`hf-space/`) doit se comporter EXACTEMENT comme l'API
avec ses modèles locaux : mêmes modèles, mêmes langues, même pivot anglais
pour le mooré, mêmes réglages de génération, mêmes limites de texte.

Ce test lit `hf-space/voice_logic.py` (sans torch ni gradio) et le compare au
code de l'API. Il échoue dès que l'un change sans l'autre."""

import importlib.util
from pathlib import Path

import pytest
from test_translation_service_modes import _RecordingService

from app import remote_voice, speech_service, translation_service
from app.languages import NLLB_CODES, PIVOT_LANG, USER_LANGUAGES
from app.schemas.kb import KbTranslationIn
from app.schemas.learn import CapsuleTranslationIn

VOICE_LOGIC = Path(__file__).resolve().parents[4] / "hf-space" / "voice_logic.py"


@pytest.fixture(scope="module")
def logic():
    if not VOICE_LOGIC.exists():
        pytest.skip("dossier hf-space/ absent")
    spec = importlib.util.spec_from_file_location("hf_space_voice_logic", VOICE_LOGIC)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_same_models_and_languages(logic):
    assert logic.WHISPER_MODEL == speech_service.WHISPER_MODEL
    assert logic.MMS_ASR_MODEL == speech_service.MMS_ASR_MODEL
    assert logic.NLLB_MODEL == translation_service.MODEL_NAME
    assert logic.WHISPER_LANGUAGE_NAMES == speech_service.WHISPER_LANGUAGE_NAMES
    assert logic.MMS_ASR_LANGS == speech_service.MMS_ASR_LANGS
    assert logic.MMS_TTS_CODES == speech_service.MMS_TTS_CODES
    assert logic.NLLB_CODES == NLLB_CODES
    assert logic.PIVOT_LANG == PIVOT_LANG
    assert list(logic.USER_LANGUAGES) == list(USER_LANGUAGES)
    assert logic.NUM_BEAMS == translation_service.DEFAULT_NUM_BEAMS


def test_same_generation_settings(logic):
    """Les réglages écrits en dur dans `_translate_one_hop` de l'API."""
    source = Path(translation_service.__file__).read_text(encoding="utf-8")
    assert f"max_length={logic.MAX_LENGTH}," in source
    assert f"no_repeat_ngram_size={logic.NO_REPEAT_NGRAM_SIZE}," in source
    assert f"repetition_penalty={logic.REPETITION_PENALTY}," in source


def test_same_text_limits(logic):
    assert logic.MAX_TRANSLATE_CHARS == remote_voice.MAX_TRANSLATE_CHARS
    assert logic.MAX_SYNTHESIZE_CHARS == remote_voice.MAX_SYNTHESIZE_CHARS
    # Les plus longs textes que l'API traduit ou lit passent les limites.
    answer_max = KbTranslationIn.model_fields["answer"].metadata[0].max_length
    capsule_max = CapsuleTranslationIn.model_fields["text"].metadata[0].max_length
    assert answer_max <= logic.MAX_TRANSLATE_CHARS
    assert capsule_max <= logic.MAX_SYNTHESIZE_CHARS


@pytest.mark.parametrize("source", sorted(NLLB_CODES))
@pytest.mark.parametrize("target", sorted(NLLB_CODES))
def test_same_pivot_routing_as_the_local_engine(logic, source, target):
    local = _RecordingService()
    local.translate("texte", source, target)
    assert logic.translation_plan(source, target) == local.steps
