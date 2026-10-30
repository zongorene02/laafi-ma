"""
Fichiers audio servis sous `/media` : enregistrements humains et synthèses
MMS-TTS mises en cache sur disque.

Deux sortes d'audio pour une réponse validée ou une capsule :

- "human" : un enregistrement fait par une personne (sage-femme, animatrice
  radio...), téléversé par l'équipe. Toujours préféré quand il existe.
- "synthetic" : une synthèse MMS-TTS du texte validé, générée PARESSEUSEMENT
  à la première lecture (`GET /media/.../tts/...`), puis mise en cache.

Le nom du fichier synthétique contient une empreinte du texte : dès qu'un
texte change, son URL change aussi — un ancien audio ne peut jamais être
servi pour un nouveau texte, et le cache de l'app se met à jour tout seul.
"""

import hashlib
import io
import os
import re
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Literal

import soundfile as sf

from app import media_service
from app.config import settings
from app.speech_service import speech_service

MediaKind = Literal["kb", "capsules"]
MEDIA_URL_PREFIX = "/media/"

_SYNTHETIC_PATTERN = re.compile(
    r"^(?P<kind>kb|capsules)/tts/(?P<id>[0-9a-f-]{36})_(?P<lang>fr|mos|dyu)_(?P<digest>[0-9a-f]{12})\.wav$"
)


def media_root() -> Path:
    root = Path(settings.media_dir).resolve()
    root.mkdir(parents=True, exist_ok=True)
    return root


def resolve_media_path(relative_path: str) -> Path | None:
    """Chemin absolu SÛR d'un fichier média, ou `None` s'il sort du dossier
    média (ex: `../../app/config.py`) — le chemin vient de l'URL, donc du
    client, et ne doit jamais permettre de lire un autre fichier du serveur."""
    root = media_root()
    candidate = (root / relative_path).resolve()
    if not candidate.is_relative_to(root) or candidate == root:
        return None
    return candidate


def media_url(relative_path: str) -> str:
    return MEDIA_URL_PREFIX + relative_path


def text_digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:12]


def synthetic_relative_path(kind: MediaKind, object_id: str, lang: str, text: str) -> str:
    return f"{kind}/tts/{object_id}_{lang}_{text_digest(text)}.wav"


@dataclass(frozen=True)
class SyntheticRequest:
    kind: MediaKind
    object_id: str
    lang: str
    digest: str


def parse_synthetic_path(relative_path: str) -> SyntheticRequest | None:
    match = _SYNTHETIC_PATTERN.match(relative_path)
    if match is None:
        return None
    kind: MediaKind = "kb" if match["kind"] == "kb" else "capsules"
    return SyntheticRequest(kind=kind, object_id=match["id"], lang=match["lang"], digest=match["digest"])


def speech_available() -> bool:
    """La synthèse n'est proposée que si les modèles voix ont été chargés au
    démarrage : sinon on renvoie `audio_url: null` plutôt qu'une URL qui
    échouerait à la lecture."""
    return speech_service.is_loaded


def audio_for(
    kind: MediaKind, object_id: str, lang: str, translation: dict[str, Any], text: str
) -> tuple[str | None, str | None]:
    """(audio_url, audio_kind) à servir pour un texte validé."""
    human_file = translation.get("audio_file")
    if human_file:
        return media_url(human_file), "human"
    if text and speech_available():
        return media_url(synthetic_relative_path(kind, object_id, lang, text)), "synthetic"
    return None, None


def _write_atomically(path: Path, data: bytes) -> None:
    """Écrit dans un fichier temporaire puis renomme : deux lectures
    simultanées du même audio jamais généré ne doivent pas servir un fichier
    à moitié écrit."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = path.with_name(f".{path.name}.{uuid.uuid4().hex}.tmp")
    tmp_path.write_bytes(data)
    os.replace(tmp_path, path)


def generate_synthetic(relative_path: str, text: str, lang: str) -> Path:
    """Synthétise `text` (MMS-TTS) et le met en cache. Bloquant (CPU) :
    à appeler depuis un endpoint `def`, que FastAPI exécute dans un thread."""
    target = resolve_media_path(relative_path)
    if target is None:
        raise ValueError("Chemin média invalide")
    if target.exists():
        return target
    audio_array, sampling_rate = speech_service.synthesize(text, lang)
    buffer = io.BytesIO()
    sf.write(buffer, audio_array, sampling_rate, format="WAV")
    _write_atomically(target, buffer.getvalue())
    return target


def save_human_audio(kind: MediaKind, object_id: str, lang: str, raw_bytes: bytes, filename_hint: str) -> str:
    """Décode un enregistrement téléversé (n'importe quel format audio) et le
    stocke en .wav 16 kHz mono. Le décodage par ffmpeg vérifie au passage
    que c'est bien de l'audio. Renvoie le chemin relatif au dossier média.
    Lève ValueError si le fichier est illisible."""
    audio_array, sampling_rate = media_service.any_audio_or_video_to_wav_array(raw_bytes, filename_hint)
    relative_path = f"{kind}/human/{object_id}_{lang}_{uuid.uuid4().hex[:8]}.wav"
    target = resolve_media_path(relative_path)
    assert target is not None  # chemin construit par nous, jamais par le client
    buffer = io.BytesIO()
    sf.write(buffer, audio_array, sampling_rate, format="WAV")
    _write_atomically(target, buffer.getvalue())
    return relative_path


def delete_media_file(relative_path: str | None) -> None:
    """Suppression best-effort (fichier remplacé ou objet supprimé)."""
    if not relative_path:
        return
    target = resolve_media_path(relative_path)
    if target is not None and target.is_file():
        target.unlink(missing_ok=True)
