"""
Logique du Space SANS modèle : langues, routage par le pivot, limites, audio.

Ce fichier n'importe ni torch, ni transformers, ni gradio : on peut le tester
sur n'importe quelle machine, sans carte graphique (voir tests/).

Tout ce qui est ici RECOPIE le comportement de l'API (dossier
`backend/services/core-service/app/`) : mêmes codes de langue, mêmes codes
NLLB, même pivot anglais pour le mooré, mêmes réglages de génération. Un test
de l'API (`tests/test_hf_space_parity.py`) compare les deux et échoue dès
qu'ils divergent : on ne doit jamais avoir deux comportements différents
selon l'endroit où tournent les modèles.
"""

from typing import Any

import numpy as np

# --- Modèles (identiques à speech_service.py et translation_service.py) ---

WHISPER_MODEL = "openai/whisper-small"
MMS_ASR_MODEL = "facebook/mms-1b-all"
NLLB_MODEL = "facebook/nllb-200-distilled-600M"
MMS_TTS_MODEL_TEMPLATE = "facebook/mms-tts-{code}"

# Reconnaissance vocale : Whisper pour le français, MMS-ASR pour le mooré et
# le dioula (Whisper ne les connaît pas).
WHISPER_LANGUAGE_NAMES = {"fr": "french"}
MMS_ASR_LANGS = {"mos", "dyu"}

# Synthèse vocale : un modèle MMS-TTS par langue.
MMS_TTS_CODES = {"fr": "fra", "mos": "mos", "dyu": "dyu"}

# Langues proposées aux utilisatrices (voir languages.py de l'API).
USER_LANGUAGES = ("fr", "mos", "dyu")

# Traduction : codes NLLB. L'anglais sert UNIQUEMENT de pivot interne.
PIVOT_LANG = "en"
NLLB_CODES = {
    "fr": "fra_Latn",
    "mos": "mos_Latn",
    "dyu": "dyu_Latn",
    PIVOT_LANG: "eng_Latn",
}
MOORE_LANG = "mos"

# Réglages de génération (voir translation_service.py, `_translate_one_hop`).
NUM_BEAMS = 5
MAX_LENGTH = 200
NO_REPEAT_NGRAM_SIZE = 3
REPETITION_PENALTY = 1.3

SAMPLE_RATE = 16000

# --- Limites de texte ---
# Les plus longs textes que l'API peut envoyer, pas plus :
# - traduction : la réponse d'une fiche (5000 caractères, traduite par la
#   console avec POST /kb/entries/{id}/translate) ;
# - synthèse : le texte d'une capsule (20000 caractères, lu par /media).
MAX_TRANSLATE_CHARS = 5000
MAX_SYNTHESIZE_CHARS = 20000

# --- Durées demandées à ZeroGPU (secondes) ---
# C'est un MAXIMUM : le quota ne compte que le temps réellement utilisé. Une
# durée courte donne une meilleure place dans la file d'attente.
MAX_GPU_SECONDS = 120


def nllb_code(lang: str) -> str:
    """Même contrôle et même message que `to_nllb_code` de l'API."""
    try:
        return NLLB_CODES[lang]
    except KeyError as e:
        raise ValueError(f"Langue non supportée : '{lang}'. Langues disponibles : {sorted(USER_LANGUAGES)}") from e


def check_asr_lang(lang: str) -> None:
    if lang not in WHISPER_LANGUAGE_NAMES and lang not in MMS_ASR_LANGS:
        raise ValueError(f"Pas de reconnaissance vocale disponible pour la langue '{lang}'")


def check_tts_lang(lang: str) -> None:
    if lang not in MMS_TTS_CODES:
        raise ValueError(f"Pas de synthèse vocale disponible pour la langue '{lang}'")


def check_text(text: Any, max_chars: int) -> str:
    if not isinstance(text, str):
        raise ValueError("Le texte doit être une chaîne de caractères")
    if len(text) > max_chars:
        raise ValueError(f"Texte trop long (maximum {max_chars} caractères)")
    return text


def translation_plan(source_lang: str, target_lang: str) -> list[tuple[str, str, bool]]:
    """Étapes de traduction : (langue source, langue cible, adaptateur mooré ?).

    Même routage que `TranslationService._translate_uncached` :
    - même langue : aucune étape (le texte est rendu tel quel) ;
    - sans mooré : une étape, modèle de base ;
    - mooré <-> anglais : une étape, avec l'adaptateur ;
    - mooré <-> autre langue : deux étapes par l'anglais, l'adaptateur
      seulement pour l'étape qui touche le mooré.
    """
    nllb_code(source_lang)
    nllb_code(target_lang)
    if source_lang == target_lang:
        return []
    if MOORE_LANG not in (source_lang, target_lang):
        return [(source_lang, target_lang, False)]
    if {source_lang, target_lang} == {MOORE_LANG, PIVOT_LANG}:
        return [(source_lang, target_lang, True)]
    if source_lang == MOORE_LANG:
        return [(MOORE_LANG, PIVOT_LANG, True), (PIVOT_LANG, target_lang, False)]
    return [(source_lang, PIVOT_LANG, False), (PIVOT_LANG, MOORE_LANG, True)]


def to_mono_16k(audio: np.ndarray, sampling_rate: int) -> np.ndarray:
    """Audio en 16 kHz mono, float32, le seul format que comprennent Whisper
    et MMS. L'API envoie déjà ce format ; la conversion ne sert que pour un
    fichier déposé à la main dans l'interface du Space."""
    data = np.asarray(audio, dtype=np.float32)
    if data.ndim == 2:
        data = data.mean(axis=1)
    if sampling_rate != SAMPLE_RATE:
        from math import gcd

        from scipy.signal import resample_poly

        divisor = gcd(int(sampling_rate), SAMPLE_RATE)
        data = resample_poly(data, SAMPLE_RATE // divisor, int(sampling_rate) // divisor).astype(np.float32)
    return data


def to_int16(waveform: np.ndarray) -> np.ndarray:
    """Onde en [-1, 1] -> entiers 16 bits, le format d'un fichier .wav."""
    clipped = np.clip(np.asarray(waveform, dtype=np.float32), -1.0, 1.0)
    return (clipped * 32767).astype(np.int16)


def _capped(seconds: float) -> int:
    return int(min(MAX_GPU_SECONDS, max(10, seconds)))


def transcribe_duration(audio: np.ndarray, lang: str) -> int:
    """Même signature que la fonction GPU de transcription (règle ZeroGPU)."""
    audio_seconds = len(audio) / SAMPLE_RATE
    return _capped(20 + audio_seconds / 2)


def translate_duration(text: str, plan: list[tuple[str, str, bool]]) -> int:
    return _capped(15 + 15 * len(plan))


def synthesize_duration(text: str, lang: str) -> int:
    return _capped(15 + len(text) / 100)
