"""
État du service, langues, et fichiers audio (`/media`).
"""

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.responses import FileResponse
from sqlalchemy import text
from sqlalchemy.orm import Session

from app import audio_store
from app.content import is_served, translation_of
from app.db import engine, get_db
from app.db_models import Capsule, KbEntry
from app.fast_translation_service import fast_translation_service
from app.languages import USER_LANGUAGES
from app.logging_config import get_logger
from app.remote_voice import RemoteSpeechService, RemoteTranslationService
from app.speech_service import speech_service
from app.translation_service import translation_service

router = APIRouter(tags=["Santé du service"])
logger = get_logger(__name__)


def database_is_reachable() -> bool:
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        return True
    except Exception as e:  # noqa: BLE001 — on veut le diagnostic, pas l'exception
        logger.warning("health.database_unreachable", error=str(e))
        return False


def voice_backend() -> str:
    """Où tournent la voix et la traduction : "local" (modèles sur cette
    machine), "remote" (Space Hugging Face, voir remote_voice.py) ou "none".
    "remote" dit que le Space est CONFIGURÉ, pas qu'il répond : /health ne le
    sonde pas, pour ne pas le réveiller ni consommer son quota."""
    if isinstance(speech_service, RemoteSpeechService) or isinstance(translation_service, RemoteTranslationService):
        return "remote"
    if speech_service.is_loaded or translation_service.is_loaded:
        return "local"
    return "none"


def health_payload() -> dict[str, Any]:
    database_ok = database_is_reachable()
    return {
        "status": "ok" if database_ok else "degraded",
        "translation_model_loaded": translation_service.is_loaded,
        "speech_model_loaded": speech_service.is_loaded,
        # Permet à un client de savoir s'il peut proposer le mode rapide, au
        # lieu de l'afficher puis d'échouer au premier appel.
        "fast_mode_available": fast_translation_service.is_available(),
        "voice_backend": voice_backend(),
        "database": "ok" if database_ok else "error",
    }


@router.get("/health")
def health(response: Response) -> dict[str, Any]:
    """Utilisé par l'hébergeur (Render) pour décider si ce service doit
    recevoir du trafic. On vérifie la seule dépendance dont TOUT dépend (la
    base) et on renvoie 503 si elle est injoignable. Les modèles d'IA non
    chargés ne rendent PAS le service malsain : l'assistant texte en français,
    la base de connaissances, l'espace agent... fonctionnent sans eux."""
    payload = health_payload()
    if payload["database"] != "ok":
        response.status_code = 503
    return payload


@router.get("/languages")
def list_languages() -> list[dict[str, str]]:
    return [{"code": code, "name": name} for code, name in USER_LANGUAGES.items()]


def _served_text_for(db: Session, request: audio_store.SyntheticRequest) -> str | None:
    """Texte SERVI correspondant à une URL de synthèse, ou None. Jamais de
    synthèse pour un brouillon : seul un contenu servi au public est lu."""
    if request.kind == "kb":
        entry = db.get(KbEntry, request.object_id)
        if entry is None or not is_served(entry):
            return None
        return str(translation_of(entry, request.lang).get("answer", "")) or None
    capsule = db.get(Capsule, request.object_id)
    if capsule is None or not is_served(capsule):
        return None
    return str(translation_of(capsule, request.lang).get("text", "")) or None


@router.get("/media/{path:path}", tags=["Médias"])
def get_media(path: str, db: Session = Depends(get_db)) -> FileResponse:
    """Fichiers audio : enregistrements humains, et synthèses MMS-TTS
    générées à la PREMIÈRE lecture puis mises en cache sur disque.

    L'empreinte du texte fait partie du nom de fichier : une URL de synthèse
    périmée (texte modifié depuis) répond 404 au lieu de lire un ancien
    texte."""
    not_found = HTTPException(status_code=404, detail="Fichier introuvable")
    target = audio_store.resolve_media_path(path)
    if target is None:
        raise not_found

    synthetic = audio_store.parse_synthetic_path(path)
    if synthetic is None:
        # Enregistrement humain : servi tel quel s'il existe.
        if target.is_file():
            return FileResponse(target, media_type="audio/wav")
        raise not_found

    # Synthèse : on revérifie À CHAQUE FOIS que l'URL correspond au texte
    # servi ACTUEL, même si le fichier est déjà en cache — un audio périmé
    # (texte modifié, contenu dé-validé) n'est jamais servi.
    served_text = _served_text_for(db, synthetic)
    if served_text is None or audio_store.text_digest(served_text) != synthetic.digest:
        raise not_found
    if target.is_file():
        return FileResponse(target, media_type="audio/wav")
    if not audio_store.speech_available():
        raise HTTPException(status_code=503, detail="Synthèse vocale indisponible")
    try:
        generated = audio_store.generate_synthetic(path, served_text, synthetic.lang)
    except ValueError as e:
        raise HTTPException(status_code=503, detail="Synthèse vocale indisponible") from e
    return FileResponse(generated, media_type="audio/wav")
