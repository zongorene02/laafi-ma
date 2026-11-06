"""
Modèles d'IA du Space, chargés UNE fois au démarrage et placés sur `cuda`.

Règles de ZeroGPU (https://huggingface.co/docs/hub/spaces-zerogpu) :
- `import spaces` AVANT torch ;
- les modèles sont placés sur `cuda` ici, au niveau du module : hors des
  fonctions `@spaces.GPU`, ZeroGPU simule la carte graphique, et c'est à
  l'intérieur de ces fonctions qu'une vraie carte est prêtée ;
- chaque fonction `@spaces.GPU` reçoit une durée maximale courte, calculée
  selon la taille de la demande (voir voice_logic.py).

Mêmes modèles que l'API (speech_service.py, translation_service.py), en
pleine précision (float32) comme elle : les sorties restent les mêmes.

Différence voulue avec l'API : l'adaptateur mooré est greffé dès le
démarrage, pas à la première requête mooré. Une fonction `@spaces.GPU` peut
tourner dans un processus à part : ce qu'elle modifie n'est pas gardé pour
l'appel suivant. Le résultat ne change pas : l'API, une fois l'adaptateur
greffé, le désactive (`disable_adapter`) pour toute étape sans mooré, comme
ici.
"""

import spaces  # en premier : ZeroGPU doit préparer torch avant son import

# isort: split
from contextlib import nullcontext
from pathlib import Path

import numpy as np
import torch
import voice_logic as logic
from huggingface_hub import hf_hub_download
from peft import PeftModel
from transformers import (
    AutoModelForSeq2SeqLM,
    AutoProcessor,
    AutoTokenizer,
    VitsModel,
    Wav2Vec2ForCTC,
    pipeline,
)

DEVICE = "cuda"
MOORE_ADAPTER_DIR = Path(__file__).resolve().parent / "moore-nllb-lora-adapter"

# --- Reconnaissance vocale ---
whisper = pipeline("automatic-speech-recognition", model=logic.WHISPER_MODEL, device=DEVICE)
mms_asr_processor = AutoProcessor.from_pretrained(logic.MMS_ASR_MODEL)
mms_asr_model = Wav2Vec2ForCTC.from_pretrained(logic.MMS_ASR_MODEL).to(DEVICE)
# Les adaptateurs de langue MMS (quelques Mo) sont téléchargés maintenant,
# pas pendant le temps de carte graphique compté dans le quota.
for _lang in sorted(logic.MMS_ASR_LANGS):
    hf_hub_download(logic.MMS_ASR_MODEL, f"adapter.{_lang}.safetensors")

# --- Traduction ---
nllb_tokenizer = AutoTokenizer.from_pretrained(logic.NLLB_MODEL)
_nllb_base = AutoModelForSeq2SeqLM.from_pretrained(logic.NLLB_MODEL).to(DEVICE)
nllb_model = PeftModel.from_pretrained(_nllb_base, str(MOORE_ADAPTER_DIR))
nllb_model.eval()

# --- Synthèse vocale : un modèle par langue ---
tts_models = {}
for _lang, _code in logic.MMS_TTS_CODES.items():
    _name = logic.MMS_TTS_MODEL_TEMPLATE.format(code=_code)
    tts_models[_lang] = (VitsModel.from_pretrained(_name).to(DEVICE), AutoTokenizer.from_pretrained(_name))


@spaces.GPU(duration=logic.transcribe_duration)
def transcribe_gpu(audio: np.ndarray, lang: str) -> str:
    """Audio 16 kHz mono (float32) -> texte. Même code que
    `SpeechService.transcribe`."""
    if lang in logic.WHISPER_LANGUAGE_NAMES:
        result = whisper(
            {"raw": audio, "sampling_rate": logic.SAMPLE_RATE},
            generate_kwargs={"language": logic.WHISPER_LANGUAGE_NAMES[lang]},
        )
        return result["text"].strip()

    mms_asr_processor.tokenizer.set_target_lang(lang)
    mms_asr_model.load_adapter(lang)
    inputs = mms_asr_processor(audio, sampling_rate=logic.SAMPLE_RATE, return_tensors="pt").to(DEVICE)
    with torch.no_grad():
        logits = mms_asr_model(**inputs).logits
    predicted_ids = torch.argmax(logits, dim=-1)
    return mms_asr_processor.decode(predicted_ids[0].cpu()).strip()


def _translate_one_hop(text: str, source_lang: str, target_lang: str, use_moore_adapter: bool) -> str:
    """Une étape de traduction. Mêmes réglages que
    `TranslationService._translate_one_hop`."""
    nllb_tokenizer.src_lang = logic.nllb_code(source_lang)
    forced_bos_token_id = nllb_tokenizer.convert_tokens_to_ids(logic.nllb_code(target_lang))
    inputs = nllb_tokenizer(text, return_tensors="pt").to(DEVICE)
    # Sans mooré, le modèle doit se comporter comme le modèle de base.
    mode = nullcontext() if use_moore_adapter else nllb_model.disable_adapter()
    with mode:
        output_tokens = nllb_model.generate(
            **inputs,
            forced_bos_token_id=forced_bos_token_id,
            max_length=logic.MAX_LENGTH,
            num_beams=logic.NUM_BEAMS,
            no_repeat_ngram_size=logic.NO_REPEAT_NGRAM_SIZE,
            repetition_penalty=logic.REPETITION_PENALTY,
        )
    return nllb_tokenizer.batch_decode(output_tokens, skip_special_tokens=True)[0]


@spaces.GPU(duration=logic.translate_duration)
def translate_gpu(text: str, plan: list[tuple[str, str, bool]]) -> str:
    """Toutes les étapes d'une traduction (pivot compris) dans UN SEUL prêt
    de carte graphique."""
    for source_lang, target_lang, use_moore_adapter in plan:
        text = _translate_one_hop(text, source_lang, target_lang, use_moore_adapter)
    return text


@spaces.GPU(duration=logic.synthesize_duration)
def synthesize_gpu(text: str, lang: str) -> tuple[int, np.ndarray]:
    """Texte -> (fréquence, onde float32). Même code que
    `SpeechService.synthesize`."""
    model, tokenizer = tts_models[lang]
    inputs = tokenizer(text, return_tensors="pt").to(DEVICE)
    with torch.no_grad():
        waveform = model(**inputs).waveform
    return model.config.sampling_rate, waveform.squeeze().float().cpu().numpy()


LOADED_MODELS = {
    "speech_to_text": {"fr": logic.WHISPER_MODEL, "mos": logic.MMS_ASR_MODEL, "dyu": logic.MMS_ASR_MODEL},
    "translation": {"base": logic.NLLB_MODEL, "moore_adapter": MOORE_ADAPTER_DIR.name},
    "text_to_speech": {
        lang: logic.MMS_TTS_MODEL_TEMPLATE.format(code=code) for lang, code in logic.MMS_TTS_CODES.items()
    },
}
