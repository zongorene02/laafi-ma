"""
Conversion de formats audio/vidéo via ffmpeg.

Pourquoi ffmpeg : nos modèles voix (Whisper, MMS) ne comprennent qu'un
format précis (audio brut, 16 000 Hz, mono). Mais un fichier envoyé par un
utilisateur peut être un .m4a (enregistreur Android/iOS), un .webm/.ogg
(navigateur), un .mp3... — ffmpeg est
l'outil standard de l'industrie pour convertir entre A PEU PRÈS tous les
formats audio/vidéo existants. On utilise `imageio-ffmpeg`, un paquet Python
qui embarque directement un exécutable ffmpeg prêt à l'emploi (pas
d'installation système séparée à faire sur la machine).

On pilote ffmpeg en ligne de commande (`subprocess`) plutôt que via une
librairie Python : c'est l'usage normal de ffmpeg, qui est fondamentalement
un programme en ligne de commande — la plupart des "librairies ffmpeg pour
Python" ne sont que de fines couches autour de ces mêmes appels.
"""

import subprocess
import tempfile
from pathlib import Path
from typing import Any

import imageio_ffmpeg
import soundfile as sf

from app.logging_config import get_logger

logger = get_logger(__name__)

FFMPEG_EXE = imageio_ffmpeg.get_ffmpeg_exe()
TARGET_SAMPLE_RATE = 16000

# Extensions dont on accepte de conserver le suffixe pour aider ffmpeg à
# détecter le format. Tout le reste retombe sur un nom neutre.
_ALLOWED_SUFFIXES = {
    ".wav",
    ".mp3",
    ".m4a",
    ".aac",
    ".ogg",
    ".oga",
    ".opus",
    ".flac",
    ".wma",
    ".webm",
    ".mp4",
    ".mov",
    ".mkv",
    ".avi",
    ".3gp",
}


def safe_temp_filename(filename_hint: str, fallback: str = "input") -> str:
    """Construit un nom de fichier SÛR à partir d'un nom fourni par le client.

    Indispensable : `UploadFile.filename` vient directement de l'en-tête HTTP
    envoyé par le client, qui peut y mettre n'importe quoi — dont
    `../../app/main.py`. Concaténé tel quel à un dossier temporaire, ça
    permettait d'écrire un fichier ARBITRAIRE ailleurs sur le disque du
    serveur (écrasement de code = exécution de code à distance).

    On ne garde donc que l'extension, et seulement si elle fait partie des
    formats attendus : elle sert uniquement d'indice de format à ffmpeg, le
    nom lui-même n'a aucune importance fonctionnelle.
    """
    suffix = Path(filename_hint).suffix.lower()
    if suffix not in _ALLOWED_SUFFIXES:
        suffix = ""
    return f"{fallback}{suffix}"


def any_audio_or_video_to_wav_array(raw_bytes: bytes, filename_hint: str = "input") -> tuple[Any, int]:
    """Convertit n'importe quel fichier audio/vidéo (bytes) en tableau audio
    16kHz mono, en passant par un fichier .wav intermédiaire sur disque.

    On utilise des fichiers temporaires plutôt que de tout faire "en mémoire"
    parce que ffmpeg est un programme externe : il a besoin de vrais chemins
    de fichiers (ou de flux stdin/stdout, plus délicats à orchestrer
    correctement côté Windows). `tempfile.TemporaryDirectory` garantit que
    ces fichiers sont supprimés automatiquement à la fin, même en cas
    d'erreur.
    """
    with tempfile.TemporaryDirectory() as tmp_dir:
        input_path = Path(tmp_dir) / safe_temp_filename(filename_hint)
        output_path = Path(tmp_dir) / "converted.wav"
        input_path.write_bytes(raw_bytes)

        result = subprocess.run(
            [
                FFMPEG_EXE,
                "-y",
                "-i",
                str(input_path),
                "-ar",
                str(TARGET_SAMPLE_RATE),  # fréquence d'échantillonnage cible
                "-ac",
                "1",  # mono (1 seul canal audio)
                "-vn",  # ignore la piste vidéo si le fichier en a une
                str(output_path),
            ],
            capture_output=True,
        )
        if result.returncode != 0:
            # Le détail ffmpeg va dans les logs SERVEUR uniquement : il
            # contient des chemins internes, qui n'aident pas l'utilisateur
            # et renseignent un attaquant sur l'arborescence du serveur.
            logger.warning("ffmpeg.decode_failed", stderr=result.stderr.decode(errors="replace")[-1000:])
            raise ValueError("Impossible de lire ce fichier audio/vidéo (format non reconnu ou fichier abîmé).")

        audio_array, sampling_rate = sf.read(str(output_path))
        return audio_array, sampling_rate
