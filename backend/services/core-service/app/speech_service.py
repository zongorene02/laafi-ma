"""
Service voix : reconnaissance vocale (STT) et synthèse vocale (TTS).

Répartition des modèles par langue :
- STT (voix -> texte) : Whisper pour le français ; MMS-ASR
  (facebook/mms-1b-all) pour le Mooré et le Dioula, que Whisper ne connaît
  pas du tout.
- TTS (texte -> voix) : MMS-TTS pour toutes les langues ici (un modèle
  distinct par langue, chargé à la demande — voir _get_tts_model).

Point d'architecture important pour MMS-ASR : c'est UN SEUL modèle partagé
par toutes ses langues, avec un "adaptateur" (une petite partie des poids,
spécifique à chaque langue) qu'on active avant chaque inférence via
`load_adapter(langue)`. Comme ce modèle est partagé entre toutes les requêtes
qui arrivent en même temps sur le serveur, on protège son utilisation avec un
verrou (`threading.Lock`) : si deux requêtes dans deux langues différentes
arrivaient exactement en même temps, l'une pourrait changer l'adaptateur actif
pendant que l'autre est en train de l'utiliser, et mélanger les résultats.
C'est un problème classique de "model serving" : un modèle avec un état
interne mutable (ici : la langue actuellement active) n'est pas automatiquement
sûr à partager entre requêtes concurrentes. Le verrou sacrifie un peu de
parallélisme (les requêtes mos/dyu s'exécutent une par une) pour garantir
des résultats corrects — un compromis raisonnable pour un prototype.
"""

import threading
from typing import TYPE_CHECKING, Any

import numpy as np

if TYPE_CHECKING:
    from app.remote_voice import RemoteSpeechService

WHISPER_MODEL = "openai/whisper-small"
MMS_ASR_MODEL = "facebook/mms-1b-all"

# Nom de langue attendu par Whisper (en anglais, format spécifique à ce modèle)
WHISPER_LANGUAGE_NAMES = {
    "fr": "french",
}

# Langues locales : reconnaissance vocale via MMS-ASR (le code est le même
# que celui utilisé partout ailleurs dans le projet)
MMS_ASR_LANGS = {"mos", "dyu"}

# Langues pour lesquelles un modèle MMS-TTS existe (facebook/mms-tts-<code>).
MMS_TTS_CODES = {
    "fr": "fra",
    "mos": "mos",
    "dyu": "dyu",
}


class SpeechService:
    def __init__(self) -> None:
        # `Any` : objets transformers, importés paresseusement (voir load()).
        self._whisper: Any = None
        self._mms_asr_model: Any = None
        self._mms_asr_processor: Any = None
        self._mms_asr_lock = threading.Lock()
        self._tts_models: dict[str, tuple[Any, Any]] = {}
        # Voir _get_tts_model : protège le CHARGEMENT (pas l'utilisation) des
        # modèles TTS, qui se fait à la demande.
        self._tts_load_lock = threading.Lock()

    def load(self) -> None:
        """Charge les modèles STT au démarrage. Les modèles TTS, eux, sont
        chargés à la demande (voir _get_tts_model) pour économiser de la
        mémoire tant qu'une langue n'a pas encore été utilisée.

        Imports de transformers ici et pas en tête de module : torch et
        transformers ne sont chargés en mémoire que si l'on charge vraiment
        les modèles (voir translation_service.py, même raison)."""
        from transformers import AutoProcessor, Wav2Vec2ForCTC, pipeline

        self._whisper = pipeline("automatic-speech-recognition", model=WHISPER_MODEL)
        self._mms_asr_processor = AutoProcessor.from_pretrained(MMS_ASR_MODEL)
        self._mms_asr_model = Wav2Vec2ForCTC.from_pretrained(MMS_ASR_MODEL)

    @property
    def is_loaded(self) -> bool:
        return self._whisper is not None

    def transcribe(self, audio_array: np.ndarray, sampling_rate: int, language: str) -> str:
        if language in WHISPER_LANGUAGE_NAMES:
            assert self._whisper is not None, "Whisper non chargé — appeler load() avant transcribe()."
            result = self._whisper(
                {"raw": audio_array, "sampling_rate": sampling_rate},
                generate_kwargs={"language": WHISPER_LANGUAGE_NAMES[language]},
            )
            return result["text"].strip()

        if language in MMS_ASR_LANGS:
            assert self._mms_asr_processor is not None and self._mms_asr_model is not None, (
                "Modèle MMS-ASR non chargé — appeler load() avant transcribe()."
            )
            import torch

            with self._mms_asr_lock:
                self._mms_asr_processor.tokenizer.set_target_lang(language)
                self._mms_asr_model.load_adapter(language)
                inputs = self._mms_asr_processor(audio_array, sampling_rate=sampling_rate, return_tensors="pt")
                with torch.no_grad():
                    logits = self._mms_asr_model(**inputs).logits
                predicted_ids = torch.argmax(logits, dim=-1)
                return self._mms_asr_processor.decode(predicted_ids[0]).strip()

        raise ValueError(f"Pas de reconnaissance vocale disponible pour la langue '{language}'")

    def _get_tts_model(self, language: str) -> tuple[Any, Any]:
        """Charge (une seule fois) le modèle TTS d'une langue, à la demande.

        Le verrou couvre le CHARGEMENT, pas la synthèse : FastAPI exécute nos
        endpoints dans un pool de threads, donc deux requêtes simultanées dans
        la même langue jamais encore utilisée entraient toutes les deux dans
        le `if` et chargeaient chacune leur copie du modèle — de la mémoire
        gaspillée sur une machine qui n'en a pas de trop, et un premier appel
        deux fois plus lent. Vérification refaite APRÈS l'attente du verrou
        ("double-checked locking") : le deuxième thread trouve alors le modèle
        déjà en place et n'a plus rien à charger.
        """
        if language not in self._tts_models:
            if language not in MMS_TTS_CODES:
                raise ValueError(f"Pas de synthèse vocale disponible pour la langue '{language}'")
            with self._tts_load_lock:
                if language not in self._tts_models:
                    from transformers import AutoTokenizer, VitsModel

                    model_name = f"facebook/mms-tts-{MMS_TTS_CODES[language]}"
                    model = VitsModel.from_pretrained(model_name)
                    tokenizer = AutoTokenizer.from_pretrained(model_name)
                    self._tts_models[language] = (model, tokenizer)
        return self._tts_models[language]

    def synthesize(self, text: str, language: str) -> tuple[np.ndarray, int]:
        import torch

        model, tokenizer = self._get_tts_model(language)
        inputs = tokenizer(text, return_tensors="pt")
        with torch.no_grad():
            waveform = model(**inputs).waveform
        return waveform.squeeze().numpy(), model.config.sampling_rate


def _build_speech_service() -> "SpeechService | RemoteSpeechService":
    """Modèles sur cette machine, ou sur le Space Hugging Face quand
    VOICE_SPACE est réglé et que les modèles ne sont pas chargés ici (voir
    remote_voice.py). Import paresseux : sans Space, rien ne change."""
    from app.config import settings

    if settings.remote_voice_enabled:
        from app.remote_voice import RemoteSpeechService

        return RemoteSpeechService()
    return SpeechService()


speech_service = _build_speech_service()
