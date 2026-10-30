"""
Traduction vocale pour les agents de santé (reprise de Trad IA) — rôle
`agent`. Permet à un agent de communiquer avec une femme dans une langue
qu'il parle mal : texte <-> texte, voix -> texte, texte -> voix, et le
pipeline voix -> voix complet.

Le même choix "verified" / "fast" est offert sur tous les chemins. Partout,
la valeur par défaut reste "verified" ; la réponse dit toujours quel moteur
a traduit (champ `mode` en JSON, en-tête `X-Translation-Mode` sinon).
"""

import io
from typing import Any
from urllib.parse import quote

import soundfile as sf
from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import Response

from app import uploads
from app.auth import require_roles
from app.db_models import ROLE_AGENT
from app.fast_translation_service import fast_translation_service
from app.languages import USER_LANGUAGES
from app.limiter import limiter
from app.schemas.translation import (
    SpeakRequest,
    TranscribeResponse,
    TranslateRequest,
    TranslateResponse,
    TranslationMode,
)
from app.speech_service import speech_service
from app.translation_service import translation_service

router = APIRouter(tags=["Traduction"])

# /translate et /text-to-speech sont publics (limités par IP) : le bouton
# « Écouter » de l'application lit l'interface en mooré/dioula sans que la
# femme ait de compte, comme /assistant/ask-voice. La reconnaissance vocale
# et le pipeline voix -> voix restent réservés aux agents.
AGENT_ONLY = [Depends(require_roles(ROLE_AGENT))]

# En-tête de réponse des endpoints qui ne renvoient pas de JSON (audio) :
# c'est là, faute de corps JSON, qu'on dit quel moteur a traduit.
TRANSLATION_MODE_HEADER = "X-Translation-Mode"
FAST_MODE_UNAVAILABLE_DETAIL = "Le mode rapide n'est pas disponible sur ce serveur. Utilisez le mode 'verified'."


def _check_lang(*codes: str) -> None:
    for code in codes:
        if code not in USER_LANGUAGES:
            raise HTTPException(
                status_code=400, detail=f"Langue non supportée : '{code}'. Langues disponibles : {list(USER_LANGUAGES)}"
            )


def translation_engine(mode: str) -> Any:
    """Moteur correspondant au mode demandé, ou 503 si le mode rapide est
    demandé sur un serveur qui n'a pas ses modèles (jamais de repli silencieux
    sur l'autre moteur). À appeler AVANT tout travail coûteux."""
    if mode == "fast":
        if not fast_translation_service.is_available():
            raise HTTPException(status_code=503, detail=FAST_MODE_UNAVAILABLE_DETAIL)
        return fast_translation_service
    if not translation_service.is_loaded:
        raise HTTPException(status_code=503, detail="Modèle de traduction non chargé")
    return translation_service


def _require_speech() -> None:
    if not speech_service.is_loaded:
        raise HTTPException(status_code=503, detail="Modèles vocaux non chargés")


def _wav_response(audio_array: Any, sampling_rate: int) -> Response:
    buffer = io.BytesIO()
    sf.write(buffer, audio_array, sampling_rate, format="WAV")
    return Response(content=buffer.getvalue(), media_type="audio/wav")


@router.post("/translate", response_model=TranslateResponse)
@limiter.limit("30/minute")
def translate(request: Request, payload: TranslateRequest) -> TranslateResponse:
    _check_lang(payload.source_lang, payload.target_lang)
    engine = translation_engine(payload.mode)
    try:
        result = engine.translate(payload.text, payload.source_lang, payload.target_lang)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    return TranslateResponse(
        translation=result, source_lang=payload.source_lang, target_lang=payload.target_lang, mode=payload.mode
    )


@router.post("/speech-to-text", response_model=TranscribeResponse, dependencies=AGENT_ONLY)
@limiter.limit("20/minute")
def speech_to_text(request: Request, audio: UploadFile = File(...), language: str = Form(...)) -> TranscribeResponse:
    _check_lang(language)
    _require_speech()
    raw = uploads.read_audio_upload(audio)
    audio_array, sampling_rate = uploads.decode_audio(raw, audio.filename or "input")
    try:
        return TranscribeResponse(text=speech_service.transcribe(audio_array, sampling_rate, language))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e


@router.post("/text-to-speech")
@limiter.limit("20/minute")
def text_to_speech(request: Request, payload: SpeakRequest) -> Response:
    """Renvoie directement un fichier audio .wav (le corps EST l'audio)."""
    _check_lang(payload.language)
    _require_speech()
    try:
        audio_array, sampling_rate = speech_service.synthesize(payload.text, payload.language)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e
    return _wav_response(audio_array, sampling_rate)


@router.post("/translate-voice", dependencies=AGENT_ONLY)
@limiter.limit("10/minute")
def translate_voice(
    request: Request,
    audio: UploadFile = File(...),
    source_lang: str = Form(...),
    target_lang: str = Form(...),
    mode: TranslationMode = Form("verified"),
) -> Response:
    """Voix (langue A) -> texte A -> texte B -> voix (langue B). `mode` ne
    concerne que l'étape texte -> texte, rappelé dans `X-Translation-Mode`.

    Les textes intermédiaires sont renvoyés dans des en-têtes, encodés façon
    URL (`quote`) : un en-tête HTTP n'accepte pas les ɛ/ɔ/ũ du mooré et du
    dioula ; l'app les décode avec `Uri.decodeComponent`."""
    _check_lang(source_lang, target_lang)
    engine = translation_engine(mode)
    _require_speech()
    raw = uploads.read_audio_upload(audio)
    audio_array, sampling_rate = uploads.decode_audio(raw, audio.filename or "input")
    try:
        source_text = speech_service.transcribe(audio_array, sampling_rate, source_lang)
        translated_text = engine.translate(source_text, source_lang, target_lang)
        output_array, output_rate = speech_service.synthesize(translated_text, target_lang)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    response = _wav_response(output_array, output_rate)
    response.headers["X-Source-Text"] = quote(source_text)
    response.headers["X-Translated-Text"] = quote(translated_text)
    response.headers[TRANSLATION_MODE_HEADER] = mode
    return response
