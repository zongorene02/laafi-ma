"""
Voix et traduction À DISTANCE, sur un Space Hugging Face (matériel ZeroGPU).

Pourquoi : l'hébergement gratuit de l'API (Render, 512 Mo de RAM) ne peut pas
charger les modèles (environ 6 Go). Le Space `hf-space/` les fait tourner sur
une carte graphique prêtée à la demande, et ce module l'appelle avec
`gradio_client`.

Les deux classes ci-dessous ont EXACTEMENT les méthodes que les routeurs et
`audio_store` utilisent sur `speech_service` et `translation_service`
(`is_loaded`, `load`, `transcribe`, `synthesize`, `translate`,
`cache_stats`) : quand `VOICE_SPACE` est réglé et que les modèles ne sont
pas chargés ici, ce sont elles qui deviennent ces deux objets (voir la fin de
speech_service.py et de translation_service.py). Aucun routeur ne change.

En cas d'échec du Space (endormi trop longtemps, quota épuisé, réseau...),
on lève `VoiceSpaceUnavailable`, une réponse 503 : l'application se comporte
comme sans modèles, elle n'affiche jamais une erreur 500.

Confidentialité :
- aucun texte ni audio n'est journalisé, seulement le nom de l'opération,
  sa durée et le TYPE d'erreur ;
- le jeton Hugging Face n'apparaît jamais dans un log ni dans un message
  d'erreur (`raise ... from None` coupe la chaîne d'exceptions d'origine) ;
- les fichiers audio temporaires sont effacés aussitôt après l'appel.

Ce module n'importe NI speech_service NI translation_service en tête :
eux l'importent à leur création, et l'inverse ferait une boucle d'imports.
"""

import contextlib
import os
import tempfile
import threading
import time
from collections import OrderedDict
from collections.abc import Callable
from pathlib import Path
from typing import Any

import numpy as np
import soundfile as sf
from fastapi import HTTPException

from app.config import settings
from app.languages import to_nllb_code
from app.logging_config import get_logger

logger = get_logger(__name__)

TARGET_SAMPLE_RATE = 16000

# Mêmes limites que le Space (hf-space/voice_logic.py, vérifié par
# tests/test_hf_space_parity.py) : les plus longs textes que l'API envoie
# (réponse d'une fiche pour la traduction, texte d'une capsule pour la voix).
MAX_TRANSLATE_CHARS = 5000
MAX_SYNTHESIZE_CHARS = 20000

# Même taille de cache que le moteur local (translation_service.py) : une
# phrase déjà traduite ne consomme pas une deuxième fois le quota du Space.
DEFAULT_CACHE_SIZE = 512

# Après un échec, on répond 503 tout de suite pendant ce délai, au lieu de
# bloquer chaque requête jusqu'à `VOICE_SPACE_TIMEOUT_SECONDS`.
FAILURE_COOLDOWN_SECONDS = 30.0
# Pause entre deux tentatives de connexion pendant le réveil du Space.
CONNECT_RETRY_SECONDS = 5.0

VOICE_SPACE_UNAVAILABLE = "Service vocal momentanément indisponible, réessayez dans quelques minutes"

# Dossier où gradio_client dépose les audios reçus (effacés après lecture).
DOWNLOAD_DIR = Path(tempfile.gettempdir()) / "laafi-ma-voice"

# Erreurs qu'un nouvel essai ne corrigera pas : Space introuvable, jeton refusé.
_PERMANENT_ERRORS = {"RepositoryNotFoundError", "AuthenticationError", "GatedRepoError"}


class VoiceSpaceUnavailable(HTTPException):
    """Le Space n'a pas répondu à temps, ou a répondu par une erreur.

    C'est une HTTPException 503 : elle traverse les routeurs (qui n'attrapent
    que ValueError, pour les 400) et arrive au client comme un « modèles non
    chargés »."""

    def __init__(self) -> None:
        super().__init__(status_code=503, detail=VOICE_SPACE_UNAVAILABLE, headers={"Retry-After": "60"})


def _new_client(space: str, token: str | None) -> Any:
    """Connexion gradio_client. Importée ici seulement : inutile de payer
    son import quand la voix à distance n'est pas utilisée."""
    # gradio_client envoie sinon des statistiques d'usage à Hugging Face.
    os.environ.setdefault("GRADIO_ANALYTICS_ENABLED", "False")
    from gradio_client import Client

    DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)
    return Client(space, token=token, verbose=False, download_files=str(DOWNLOAD_DIR), analytics_enabled=False)


class SpaceConnection:
    """Connexion paresseuse, partagée et protégée par un verrou, au Space.

    Rien n'est contacté au démarrage : la première requête vocale ouvre la
    connexion. Pendant le réveil d'un Space endormi (plusieurs minutes), la
    connexion est retentée jusqu'au délai maximal."""

    def __init__(
        self,
        space: str,
        token: str,
        timeout_seconds: float,
        client_factory: Callable[[str, str | None], Any] = _new_client,
    ) -> None:
        self.space = space.strip()
        self._token = token or None
        self.timeout_seconds = timeout_seconds
        self._client_factory = client_factory
        self._client: Any = None
        self._lock = threading.Lock()
        self._unavailable_until = 0.0

    @classmethod
    def from_settings(cls) -> "SpaceConnection":
        return cls(
            settings.voice_space,
            settings.hf_token.get_secret_value(),
            settings.voice_space_timeout_seconds,
        )

    @property
    def configured(self) -> bool:
        return bool(self.space)

    def __repr__(self) -> str:  # jamais le jeton
        return f"SpaceConnection(space={self.space!r})"

    def call(self, operation: str, api_name: str, *args: Any) -> Any:
        """Appelle un point d'entrée du Space. Lève VoiceSpaceUnavailable en
        cas d'échec ou de dépassement du délai."""
        if time.monotonic() < self._unavailable_until:
            raise VoiceSpaceUnavailable()
        started = time.monotonic()
        deadline = started + self.timeout_seconds
        try:
            client = self._get_client(deadline)
            job = client.submit(*args, api_name=api_name)
            try:
                result = job.result(timeout=max(1.0, deadline - time.monotonic()))
            except TimeoutError:
                job.cancel()
                raise
        except Exception as error:  # noqa: BLE001 — tout échec distant devient un 503
            self._mark_failed(operation, error)
            raise VoiceSpaceUnavailable() from None
        logger.info("voice_space.call_ok", operation=operation, seconds=round(time.monotonic() - started, 2))
        return result

    def _get_client(self, deadline: float) -> Any:
        if not self._lock.acquire(timeout=max(0.0, deadline - time.monotonic())):
            raise TimeoutError("Connexion au Space déjà en cours")
        try:
            while self._client is None:
                try:
                    self._client = self._client_factory(self.space, self._token)
                except Exception as error:
                    if type(error).__name__ in _PERMANENT_ERRORS:
                        raise
                    if time.monotonic() + CONNECT_RETRY_SECONDS >= deadline:
                        raise
                    # Space endormi ou en train de démarrer : on patiente.
                    logger.info("voice_space.waiting", error_type=type(error).__name__)
                    time.sleep(CONNECT_RETRY_SECONDS)
            return self._client
        finally:
            self._lock.release()

    def _mark_failed(self, operation: str, error: Exception) -> None:
        # Seulement le TYPE d'erreur : son message pourrait contenir une
        # adresse, un texte ou un en-tête.
        logger.warning("voice_space.call_failed", operation=operation, error_type=type(error).__name__)
        self._unavailable_until = time.monotonic() + FAILURE_COOLDOWN_SECONDS
        # Le Space a pu redémarrer : on se reconnectera proprement.
        client, self._client = self._client, None
        if client is not None:
            with contextlib.suppress(Exception):  # fermeture de courtoisie
                client.close()


_shared_connection: SpaceConnection | None = None
_shared_lock = threading.Lock()


def shared_connection() -> SpaceConnection:
    """Une seule connexion pour la voix et la traduction."""
    global _shared_connection
    with _shared_lock:
        if _shared_connection is None:
            _shared_connection = SpaceConnection.from_settings()
        return _shared_connection


def _to_16k_mono(audio_array: Any, sampling_rate: int) -> np.ndarray:
    """`uploads.decode_audio` rend déjà du 16 kHz mono ; ceci n'est qu'un
    filet de sécurité pour un autre appelant."""
    data = np.asarray(audio_array, dtype=np.float32)
    if data.ndim == 2:
        data = data.mean(axis=1)
    if sampling_rate != TARGET_SAMPLE_RATE and len(data) > 0:
        duration = len(data) / sampling_rate
        new_length = max(1, round(duration * TARGET_SAMPLE_RATE))
        positions = np.linspace(0, len(data) - 1, new_length)
        data = np.interp(positions, np.arange(len(data)), data).astype(np.float32)
    return data


def _result_path(result: Any) -> Path:
    """gradio_client rend le chemin du fichier audio téléchargé."""
    if isinstance(result, dict) and result.get("path"):
        return Path(str(result["path"]))
    if isinstance(result, str | os.PathLike):
        return Path(result)
    raise TypeError(f"Réponse audio inattendue du Space : {type(result).__name__}")


class RemoteSpeechService:
    """Même interface que `SpeechService`, modèles sur le Space."""

    def __init__(self, connection: SpaceConnection | None = None) -> None:
        self._space = connection or shared_connection()

    def load(self) -> None:
        """Rien à charger sur cette machine."""

    @property
    def is_loaded(self) -> bool:
        # « Configuré », pas « joignable » : on ne sonde pas le Space à chaque
        # requête (cela consommerait du temps et réveillerait le Space).
        return self._space.configured

    def transcribe(self, audio_array: np.ndarray, sampling_rate: int, language: str) -> str:
        from app.speech_service import MMS_ASR_LANGS, WHISPER_LANGUAGE_NAMES

        if language not in WHISPER_LANGUAGE_NAMES and language not in MMS_ASR_LANGS:
            raise ValueError(f"Pas de reconnaissance vocale disponible pour la langue '{language}'")
        from gradio_client import handle_file

        fd, name = tempfile.mkstemp(prefix="laafi-ma-", suffix=".wav")
        os.close(fd)
        path = Path(name)
        try:
            sf.write(path, _to_16k_mono(audio_array, sampling_rate), TARGET_SAMPLE_RATE, subtype="PCM_16")
            result = self._space.call("transcribe", "/transcribe", handle_file(str(path)), language)
        finally:
            path.unlink(missing_ok=True)
        return str(result).strip()

    def synthesize(self, text: str, language: str) -> tuple[np.ndarray, int]:
        from app.speech_service import MMS_TTS_CODES

        if language not in MMS_TTS_CODES:
            raise ValueError(f"Pas de synthèse vocale disponible pour la langue '{language}'")
        if len(text) > MAX_SYNTHESIZE_CHARS:
            raise ValueError(f"Texte trop long (maximum {MAX_SYNTHESIZE_CHARS} caractères)")
        if not text.strip():
            raise ValueError("Texte vide : rien à lire")
        result = self._space.call("synthesize", "/synthesize", text, language)
        try:
            path = _result_path(result)
            try:
                audio, rate = sf.read(path, dtype="float32")
            finally:
                path.unlink(missing_ok=True)
        except (TypeError, RuntimeError, OSError) as error:
            logger.warning("voice_space.bad_audio", error_type=type(error).__name__)
            raise VoiceSpaceUnavailable() from None
        return audio, int(rate)


class RemoteTranslationService:
    """Même interface que `TranslationService`, modèle sur le Space.

    Le Space applique le même routage (pivot anglais pour le mooré,
    adaptateur seulement pour le mooré) et les mêmes réglages : les
    traductions sont celles du moteur vérifié. Le cache reste ici, en
    mémoire, comme pour le moteur local."""

    def __init__(self, connection: SpaceConnection | None = None, cache_size: int = DEFAULT_CACHE_SIZE) -> None:
        self._space = connection or shared_connection()
        self._cache_lock = threading.Lock()
        self._cache: OrderedDict[tuple[str, str, str], str] = OrderedDict()
        self._cache_size = max(0, cache_size)
        self.cache_hits = 0
        self.cache_misses = 0

    def load(self) -> None:
        """Rien à charger sur cette machine."""

    @property
    def is_loaded(self) -> bool:
        return self._space.configured

    def cache_stats(self) -> dict[str, int]:
        with self._cache_lock:
            size = len(self._cache)
        return {"entries": size, "capacity": self._cache_size, "hits": self.cache_hits, "misses": self.cache_misses}

    def translate(self, text: str, source_lang: str, target_lang: str) -> str:
        if source_lang == target_lang:
            return text
        # Mêmes refus (ValueError -> 400) que le moteur local, AVANT l'appel.
        to_nllb_code(source_lang)
        to_nllb_code(target_lang)
        if len(text) > MAX_TRANSLATE_CHARS:
            raise ValueError(f"Texte trop long (maximum {MAX_TRANSLATE_CHARS} caractères)")
        if not text.strip():
            return text

        key = (source_lang, target_lang, text)
        if self._cache_size:
            with self._cache_lock:
                if key in self._cache:
                    self._cache.move_to_end(key)
                    self.cache_hits += 1
                    return self._cache[key]
            self.cache_misses += 1

        result = str(self._space.call("translate", "/translate", text, source_lang, target_lang))

        if self._cache_size:
            with self._cache_lock:
                self._cache[key] = result
                self._cache.move_to_end(key)
                while len(self._cache) > self._cache_size:
                    self._cache.popitem(last=False)
        return result
