"""Lecture sûre des fichiers audio envoyés par les clients."""

from typing import Any

from fastapi import HTTPException, UploadFile

from app import media_service
from app.config import settings


def read_audio_upload(upload: UploadFile) -> bytes:
    """Lit un fichier audio en refusant (413) tout ce qui dépasse
    `MAX_AUDIO_UPLOAD_BYTES`.

    Deux contrôles : `upload.size` (annoncé par le client, permet de refuser
    AVANT de lire) puis la taille réellement lue — un client peut mentir sur
    la première, pas sur la seconde. On ne lit jamais plus que la limite + 1
    octet, de quoi savoir qu'elle est dépassée sans tout charger en mémoire.
    """
    limit = settings.max_audio_upload_bytes
    too_large = HTTPException(status_code=413, detail=f"Fichier trop volumineux (max {limit // (1024 * 1024)} Mo)")
    if upload.size is not None and upload.size > limit:
        raise too_large
    data = upload.file.read(limit + 1)
    if len(data) > limit:
        raise too_large
    if not data:
        raise HTTPException(status_code=400, detail="Fichier audio vide")
    return data


def decode_audio(raw_bytes: bytes, filename_hint: str) -> tuple[Any, int]:
    """Décode n'importe quel format audio (wav/webm/ogg/m4a/mp3...) via ffmpeg.
    Un fichier illisible est une erreur DU CLIENT : 400, pas 500."""
    try:
        return media_service.any_audio_or_video_to_wav_array(raw_bytes, filename_hint)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
