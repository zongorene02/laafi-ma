"""
Laafi Ma — voix et traduction (Space Hugging Face, matériel ZeroGPU).

L'API de Laafi Ma (hébergée sur une petite machine sans carte graphique)
appelle ce Space pour la reconnaissance vocale, la traduction mooré/dioula et
la synthèse vocale. Quatre points d'entrée, avec un `api_name` fixe :

- `/transcribe`  (fichier audio, langue)            -> texte
- `/translate`   (texte, langue source, langue cible) -> texte
- `/synthesize`  (texte, langue)                     -> audio (.wav)
- `/health`      ()                                  -> état (sans carte graphique)

Confidentialité : aucun texte ni aucun audio n'est journalisé. Les fichiers
reçus sont effacés dès qu'ils sont lus ; les audios produits restent au plus
une vingtaine de minutes dans le cache de Gradio (`delete_cache`).
"""

import spaces  # noqa: F401 — en premier, avant torch (voir models.py)

# isort: split
import contextlib
import os

import gradio as gr
import models
import numpy as np
import soundfile as sf
import voice_logic as logic

# Toutes les 10 minutes, Gradio efface les fichiers de son cache vieux de plus
# de 10 minutes (audios produits par la synthèse, le temps que l'API les
# télécharge).
DELETE_CACHE = (600, 600)


def _forget(path: str | None) -> None:
    """Efface un fichier reçu dès qu'il est lu (règle de confidentialité)."""
    if path:
        with contextlib.suppress(OSError):
            os.remove(path)


def transcribe(audio_filepath: str | None, lang: str) -> str:
    try:
        logic.check_asr_lang(lang)
        if not audio_filepath:
            raise ValueError("Aucun fichier audio reçu")
        try:
            audio, sampling_rate = sf.read(audio_filepath, dtype="float32")
        except RuntimeError as e:  # soundfile.LibsndfileError en hérite
            raise ValueError("Impossible de lire ce fichier audio") from e
    except ValueError as e:
        raise gr.Error(str(e)) from None
    finally:
        _forget(audio_filepath)
    if len(audio) == 0:
        return ""
    return models.transcribe_gpu(logic.to_mono_16k(audio, sampling_rate), lang)


def translate(text: str, source_lang: str, target_lang: str) -> str:
    try:
        plan = logic.translation_plan(source_lang, target_lang)
        text = logic.check_text(text, logic.MAX_TRANSLATE_CHARS)
    except ValueError as e:
        raise gr.Error(str(e)) from None
    # Même langue, ou rien à traduire : pas de carte graphique (quota).
    if not plan or not text.strip():
        return text
    return models.translate_gpu(text, plan)


def synthesize(text: str, lang: str) -> tuple[int, np.ndarray]:
    try:
        logic.check_tts_lang(lang)
        text = logic.check_text(text, logic.MAX_SYNTHESIZE_CHARS)
        if not text.strip():
            raise ValueError("Texte vide : rien à lire")
    except ValueError as e:
        raise gr.Error(str(e)) from None
    sampling_rate, waveform = models.synthesize_gpu(text, lang)
    return sampling_rate, logic.to_int16(waveform)


def health() -> dict:
    """État du Space, sans carte graphique : ne consomme pas de quota."""
    return {
        "status": "ok",
        "device": models.DEVICE,
        "languages": list(logic.USER_LANGUAGES),
        "models": models.LOADED_MODELS,
        "limits": {
            "translate_max_chars": logic.MAX_TRANSLATE_CHARS,
            "synthesize_max_chars": logic.MAX_SYNTHESIZE_CHARS,
        },
        "gradio": gr.__version__,
    }


ASR_LANGS = sorted(set(logic.WHISPER_LANGUAGE_NAMES) | logic.MMS_ASR_LANGS)
TTS_LANGS = sorted(logic.MMS_TTS_CODES)
TRANSLATE_LANGS = list(logic.NLLB_CODES)

with gr.Blocks(title="Laafi Ma — voix", analytics_enabled=False, delete_cache=DELETE_CACHE) as demo:
    gr.Markdown(
        "# Laafi Ma — voix et traduction\n"
        "Service utilisé par l'API de Laafi Ma (français, mooré, dioula). "
        "Modèles : Whisper, MMS (Meta), NLLB-200 et un adaptateur mooré. "
        "**Usage non commercial uniquement** (licence CC-BY-NC 4.0). "
        "Rien n'est journalisé ; les fichiers sont effacés après usage."
    )
    with gr.Tab("Reconnaissance vocale"):
        asr_audio = gr.Audio(type="filepath", sources=["upload", "microphone"], label="Audio")
        asr_lang = gr.Dropdown(choices=ASR_LANGS, value="fr", label="Langue")
        asr_text = gr.Textbox(label="Texte reconnu")
        gr.Button("Transcrire").click(transcribe, [asr_audio, asr_lang], asr_text, api_name="transcribe")
    with gr.Tab("Traduction"):
        tr_text = gr.Textbox(label="Texte", lines=4, max_length=logic.MAX_TRANSLATE_CHARS)
        tr_source = gr.Dropdown(choices=TRANSLATE_LANGS, value="fr", label="Langue source")
        tr_target = gr.Dropdown(choices=TRANSLATE_LANGS, value="mos", label="Langue cible")
        tr_out = gr.Textbox(label="Traduction")
        gr.Button("Traduire").click(translate, [tr_text, tr_source, tr_target], tr_out, api_name="translate")
    with gr.Tab("Synthèse vocale"):
        tts_text = gr.Textbox(label="Texte", lines=4, max_length=logic.MAX_SYNTHESIZE_CHARS)
        tts_lang = gr.Dropdown(choices=TTS_LANGS, value="fr", label="Langue")
        tts_audio = gr.Audio(type="numpy", format="wav", label="Audio")
        gr.Button("Lire").click(synthesize, [tts_text, tts_lang], tts_audio, api_name="synthesize")
    with gr.Tab("État"):
        health_out = gr.JSON(label="État")
        gr.Button("Vérifier").click(health, None, health_out, api_name="health", concurrency_limit=None)

# File d'attente : une seule demande à la fois par point d'entrée (la carte
# graphique est prêtée à la demande), et pas plus de 32 en attente.
demo.queue(default_concurrency_limit=1, max_size=32)

if __name__ == "__main__":
    demo.launch()
