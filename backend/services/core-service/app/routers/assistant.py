"""
Assistant santé (module 1) : questions écrites ou vocales, FAQ hors ligne,
signes de danger.

Pipeline d'une question :

    voix (mos/dyu/fr) --STT--> texte --traduction--> français
        --rapprochement--> entrée SERVIE --> réponse dans la langue demandée
        +--détection--> signes de danger SERVIS (indépendamment du rapprochement)

Rien n'est jamais généré : la réponse servie est TOUJOURS un texte relu par
une sage-femme ou un médecin (règle de confidentialité n°5, voir
docs/API.md), ou, si SERVE_SOURCED_CONTENT=true, un texte tiré d'une source
citée et signalé `provisional: true`. Une question sans réponse servie assez
proche est enregistrée anonymement pour que les validateurs enrichissent la
base.

Un texte qui manque dans la langue demandée est remplacé par le français.

`ask-text` en français ne dépend d'aucun modèle d'IA : il fonctionne même sur
un serveur démarré sans modèles (LOAD_MODELS_ON_STARTUP=false).
"""

from collections.abc import Iterable

from fastapi import APIRouter, Depends, File, Form, HTTPException, Request, UploadFile
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app import uploads
from app.config import settings
from app.content import (
    danger_sign_aid,
    danger_sign_text,
    is_provisional,
    kb_has_text,
    kb_served_audio,
    kb_serving_lang,
    served_statuses,
    translation_of,
)
from app.db import get_db
from app.db_models import DangerSign, KbEntry, UnansweredQuestion
from app.languages import UserLang
from app.limiter import limiter
from app.logging_config import get_logger
from app.matching import Candidate, basic_normalize, best_match, contains_keyword
from app.schemas.common import iso_utc
from app.schemas.kb import (
    AskResponse,
    AskTextRequest,
    AssistantEntry,
    DangerSignBrief,
    DangerSignPublic,
    FaqEntry,
    FaqResponse,
    TranscribeResponse,
)
from app.speech_service import speech_service
from app.translation_service import translation_service

router = APIRouter(prefix="/assistant", tags=["Assistant"])
logger = get_logger(__name__)

VOICE_UNAVAILABLE = "Assistant vocal indisponible"
TRANSLATION_UNAVAILABLE = "Traduction indisponible : l'assistant ne répond pour l'instant qu'en français écrit"


def _fallback_message(lang: str) -> str:
    messages = settings.assistant_fallback_messages
    return messages.get(lang) or messages.get("fr") or ""


def _served_entries(db: Session) -> list[KbEntry]:
    return list(db.scalars(select(KbEntry).where(KbEntry.status.in_(served_statuses()))))


def _served_danger_signs(db: Session) -> list[DangerSign]:
    return list(db.scalars(select(DangerSign).where(DangerSign.status.in_(served_statuses()))))


def _to_french(text: str, lang: str) -> str:
    """Traduit la question en français avec le moteur VÉRIFIÉ (jamais le
    rapide, non relu). 503 si le modèle n'est pas chargé."""
    if not translation_service.is_loaded:
        raise HTTPException(status_code=503, detail=TRANSLATION_UNAVAILABLE)
    try:
        return translation_service.translate(text, lang, "fr")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e


def detect_danger_signs(text_fr: str, signs: list[DangerSign], lang: str) -> list[DangerSignBrief]:
    normalized = basic_normalize(text_fr)
    found: list[DangerSignBrief] = []
    for sign in signs:
        if contains_keyword(normalized, sign.keywords_fr or []):
            label, advice = danger_sign_text(sign, lang)
            found.append(
                DangerSignBrief(
                    id=sign.id, label=label, advice=advice, provisional=is_provisional(sign), source=sign.source
                )
            )
    return found


def kb_candidates(entries: Iterable[KbEntry]) -> list[Candidate]:
    """Formulations françaises (question + variantes) comparées à la question."""
    candidates: list[Candidate] = []
    for entry in entries:
        fr = translation_of(entry, "fr")
        for phrasing in [fr.get("question", ""), *fr.get("variants", [])]:
            if str(phrasing).strip():
                candidates.append(Candidate(entry_id=entry.id, text=str(phrasing)))
    return candidates


def answer_question(db: Session, *, text_fr: str, lang: str, transcript: str | None) -> AskResponse:
    """Cœur de l'assistant, commun aux questions écrites et vocales."""
    question_fr = None if lang == "fr" else text_fr
    danger_signs = detect_danger_signs(text_fr, _served_danger_signs(db), lang)

    entries = {entry.id: entry for entry in _served_entries(db)}
    match = best_match(text_fr, kb_candidates(entries.values())) if text_fr.strip() else None
    confidence = match.confidence if match is not None else 0.0

    if match is not None and confidence >= settings.assistant_min_confidence:
        entry = entries[match.entry_id]
        served_lang = kb_serving_lang(entry, lang)
        served = translation_of(entry, served_lang)
        audio_url, audio_kind = kb_served_audio(entry, served_lang)
        return AskResponse(
            transcript=transcript,
            question_fr=question_fr,
            matched=True,
            confidence=confidence,
            entry=AssistantEntry(
                id=entry.id,
                topic=entry.topic,
                question=str(served.get("question", "")),
                answer=str(served.get("answer", "")),
                audio_url=audio_url,
                audio_kind=audio_kind,  # type: ignore[arg-type]
                provisional=is_provisional(entry),
                source=entry.source,
            ),
            danger=bool(danger_signs),
            danger_signs=danger_signs,
            fallback_message=None,
        )

    # Pas de réponse servie assez proche : on garde la question (en
    # français, sans aucun identifiant) pour les validateurs.
    if text_fr.strip():
        db.add(UnansweredQuestion(text_fr=text_fr.strip()[:1000], lang=lang))
        db.commit()
    return AskResponse(
        transcript=transcript,
        question_fr=question_fr,
        matched=False,
        confidence=confidence,
        entry=None,
        danger=bool(danger_signs),
        danger_signs=danger_signs,
        fallback_message=_fallback_message(lang),
    )


@router.post("/ask-text", response_model=AskResponse)
@limiter.limit("30/minute")
def ask_text(request: Request, payload: AskTextRequest, db: Session = Depends(get_db)) -> AskResponse:
    text_fr = payload.text if payload.lang == "fr" else _to_french(payload.text, payload.lang)
    return answer_question(db, text_fr=text_fr, lang=payload.lang, transcript=None)


def _transcribe_voice(audio: UploadFile, lang: str) -> tuple[str, str]:
    """(transcription, texte en français) d'une question vocale, commun à
    `ask-voice` et `transcribe`. Les modèles sont vérifiés AVANT de lire et
    décoder le fichier : inutile de faire travailler ffmpeg pour finir sur
    un 503."""
    if not speech_service.is_loaded or (lang != "fr" and not translation_service.is_loaded):
        raise HTTPException(status_code=503, detail=VOICE_UNAVAILABLE)

    raw = uploads.read_audio_upload(audio)
    audio_array, sampling_rate = uploads.decode_audio(raw, audio.filename or "question")
    try:
        transcript = speech_service.transcribe(audio_array, sampling_rate, lang).strip()
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    text_fr = transcript if lang == "fr" or not transcript else _to_french(transcript, lang)
    return transcript, text_fr


@router.post("/ask-voice", response_model=AskResponse)
@limiter.limit("10/minute")
def ask_voice(
    request: Request,
    audio: UploadFile = File(...),
    lang: UserLang = Form(...),
    db: Session = Depends(get_db),
) -> AskResponse:
    """Question vocale : transcription, traduction, puis même réponse que
    `ask-text`."""
    transcript, text_fr = _transcribe_voice(audio, lang)
    return answer_question(db, text_fr=text_fr, lang=lang, transcript=transcript)


@router.post("/transcribe", response_model=TranscribeResponse)
@limiter.limit("10/minute")
def transcribe(request: Request, audio: UploadFile = File(...), lang: UserLang = Form(...)) -> TranscribeResponse:
    """Transcription SEULE, sans réponse : l'app affiche « Vous avez
    demandé : … ? » pour confirmation, ou compare le texte SUR L'APPAREIL à
    la phrase d'aide secrète (code vocal, module 3). Rien n'est enregistré
    ni journalisé — ni question sans réponse, ni événement, ni texte dans
    les logs : la phrase secrète ne doit laisser aucune trace sur le
    serveur. Pas de session de base de données, par construction."""
    transcript, text_fr = _transcribe_voice(audio, lang)
    return TranscribeResponse(transcript=transcript, question_fr=None if lang == "fr" else text_fr)


@router.get("/faq", response_model=FaqResponse)
def faq(lang: UserLang = "fr", db: Session = Depends(get_db)) -> FaqResponse:
    """Toutes les entrées servies, dans la langue demandée ou en français si
    ce texte manque (comme `ask-*`), pour la mise en cache hors ligne dans
    l'app.

    `version` = date de dernière modification de la base (tous statuts
    confondus : un archivage doit aussi invalider le cache de l'app)."""
    latest = db.scalar(select(func.max(KbEntry.updated_at)))
    entries: list[FaqEntry] = []
    for entry in sorted(_served_entries(db), key=lambda e: (e.topic, e.created_at)):
        served_lang = kb_serving_lang(entry, lang)
        if not kb_has_text(entry, served_lang):
            continue
        t = translation_of(entry, served_lang)
        audio_url, audio_kind = kb_served_audio(entry, served_lang)
        entries.append(
            FaqEntry(
                id=entry.id,
                topic=entry.topic,
                question=str(t.get("question", "")),
                answer=str(t.get("answer", "")),
                audio_url=audio_url,
                audio_kind=audio_kind,  # type: ignore[arg-type]
                provisional=is_provisional(entry),
                source=entry.source,
                is_danger_topic=entry.is_danger_topic,
            )
        )
    return FaqResponse(version=iso_utc(latest) if latest is not None else "", entries=entries)


@router.get("/danger-signs", response_model=list[DangerSignPublic])
def public_danger_signs(lang: UserLang = "fr", db: Session = Depends(get_db)) -> list[DangerSignPublic]:
    """Signes de danger SERVIS, avec leurs mots-clés (français), pour la
    détection sur l'appareil quand il est hors ligne, et la fiche d'aide à
    la décision de l'agent (questions à poser, quand orienter)."""
    result = []
    for sign in _served_danger_signs(db):
        label, advice = danger_sign_text(sign, lang)
        agent_questions, refer_when = danger_sign_aid(sign, lang)
        result.append(
            DangerSignPublic(
                id=sign.id,
                label=label,
                advice=advice,
                provisional=is_provisional(sign),
                source=sign.source,
                keywords=list(sign.keywords_fr or []),
                agent_questions=agent_questions,
                refer_when=refer_when,
            )
        )
    return result
