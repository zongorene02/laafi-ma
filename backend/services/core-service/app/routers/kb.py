"""
Base de connaissances, signes de danger et questions sans réponse —
réservé aux validateurs (sages-femmes, médecins) et aux admins.

Circuit : `draft` -> `validated` -> `archived`. Toute modification d'un
contenu (texte, mots-clés, audio, traduction automatique) le renvoie en
`draft` : seul un contenu relu tel quel est servi à l'app.
"""

from typing import Any

from fastapi import APIRouter, Depends, File, HTTPException, Response, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import audio_store, uploads
from app.auth import require_roles
from app.content import (
    LANGS,
    danger_sign_out,
    danger_sign_translation,
    kb_entry_out,
    mark_edited,
    translation_of,
)
from app.db import get_db
from app.db_models import (
    ROLE_ADMIN,
    ROLE_VALIDATOR,
    STATUS_ARCHIVED,
    STATUS_DRAFT,
    STATUS_VALIDATED,
    DangerSign,
    KbEntry,
    UnansweredQuestion,
    User,
)
from app.db_types import utc_now
from app.languages import UserLang
from app.logging_config import get_logger
from app.matching import basic_normalize
from app.routers.common import get_or_404
from app.schemas.common import ContentStatus
from app.schemas.kb import (
    DangerSignIn,
    DangerSignOut,
    KbEntryIn,
    KbEntryOut,
    Topic,
    UnansweredOut,
)
from app.translation_service import translation_service

require_kb_staff = require_roles(ROLE_VALIDATOR, ROLE_ADMIN)

router = APIRouter(prefix="/kb", tags=["Base de connaissances"], dependencies=[Depends(require_kb_staff)])
logger = get_logger(__name__)

ENTRY_NOT_FOUND = "Entrée introuvable"
SIGN_NOT_FOUND = "Signe de danger introuvable"


# --- Entrées de la base de connaissances --------------------------------------


def _clean_variants(variants: list[str]) -> list[str]:
    return [v.strip() for v in variants if v.strip()]


def _merged_kb_translations(entry: KbEntry | None, payload: KbEntryIn) -> dict[str, Any]:
    """Fusionne les textes reçus avec ceux déjà stockés.

    - Une langue absente du corps est conservée telle quelle (une console qui
      n'envoie que le français n'efface pas le mooré).
    - L'enregistrement humain d'une langue est conservé (il se remplace par
      POST /audio/{lang}).
    - `machine_translated` reste vrai tant que le texte n'a pas été retouché
      par un humain, et redevient faux dès qu'il l'est.
    """
    merged: dict[str, Any] = {lang: translation_of(entry, lang) for lang in LANGS} if entry else {}
    for lang, incoming in payload.translations.items():
        previous = merged.get(lang, {})
        new = {
            "question": incoming.question.strip(),
            "variants": _clean_variants(incoming.variants),
            "answer": incoming.answer.strip(),
        }
        unchanged_text = previous.get("question", "") == new["question"] and previous.get("answer", "") == new["answer"]
        merged[lang] = {
            **new,
            "audio_file": previous.get("audio_file"),
            "machine_translated": bool(previous.get("machine_translated")) and unchanged_text,
        }
    return {lang: value for lang, value in merged.items() if value}


@router.get("/entries", response_model=list[KbEntryOut])
def list_entries(
    status: ContentStatus | None = None,
    topic: Topic | None = None,
    q: str | None = None,
    db: Session = Depends(get_db),
) -> list[KbEntryOut]:
    query = select(KbEntry).order_by(KbEntry.updated_at.desc())
    if status is not None:
        query = query.where(KbEntry.status == status)
    if topic is not None:
        query = query.where(KbEntry.topic == topic)
    entries = list(db.scalars(query))

    # Recherche faite en Python, sur les textes NORMALISÉS (sans accents) :
    # la base est petite, et une recherche SQL dans une colonne JSON n'est ni
    # portable entre SQLite et PostgreSQL, ni insensible aux accents.
    if q and q.strip():
        needle = basic_normalize(q)
        entries = [
            e
            for e in entries
            if any(
                needle
                in basic_normalize(" ".join([t.get("question", ""), t.get("answer", ""), *t.get("variants", [])]))
                for t in (translation_of(e, lang) for lang in LANGS)
            )
        ]
    return [kb_entry_out(e) for e in entries]


@router.post("/entries", response_model=KbEntryOut, status_code=201)
def create_entry(payload: KbEntryIn, db: Session = Depends(get_db)) -> KbEntryOut:
    entry = KbEntry(
        topic=payload.topic,
        status=STATUS_DRAFT,
        is_danger_topic=payload.is_danger_topic,
        translations=_merged_kb_translations(None, payload),
        source=payload.source,
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)
    return kb_entry_out(entry)


@router.get("/entries/{entry_id}", response_model=KbEntryOut)
def get_entry(entry_id: str, db: Session = Depends(get_db)) -> KbEntryOut:
    return kb_entry_out(get_or_404(db, KbEntry, entry_id, ENTRY_NOT_FOUND))


@router.put("/entries/{entry_id}", response_model=KbEntryOut)
def update_entry(entry_id: str, payload: KbEntryIn, db: Session = Depends(get_db)) -> KbEntryOut:
    entry = get_or_404(db, KbEntry, entry_id, ENTRY_NOT_FOUND)
    translations = _merged_kb_translations(entry, payload)
    changed = (
        entry.topic != payload.topic
        or entry.is_danger_topic != payload.is_danger_topic
        or entry.source != payload.source
        or translations != {lang: translation_of(entry, lang) for lang in LANGS if translation_of(entry, lang)}
    )
    # Un "Enregistrer" sans aucune modification ne dé-valide pas l'entrée.
    if changed:
        entry.topic = payload.topic
        entry.is_danger_topic = payload.is_danger_topic
        entry.source = payload.source
        entry.translations = translations
        mark_edited(entry)
        db.commit()
        db.refresh(entry)
    return kb_entry_out(entry)


@router.delete("/entries/{entry_id}", status_code=204)
def delete_entry(entry_id: str, db: Session = Depends(get_db)) -> Response:
    entry = get_or_404(db, KbEntry, entry_id, ENTRY_NOT_FOUND)
    audio_files = [translation_of(entry, lang).get("audio_file") for lang in LANGS]
    db.delete(entry)
    db.commit()
    for audio_file in audio_files:
        audio_store.delete_media_file(audio_file)
    return Response(status_code=204)


@router.post("/entries/{entry_id}/validate", response_model=KbEntryOut)
def validate_entry(
    entry_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_kb_staff),
) -> KbEntryOut:
    entry = get_or_404(db, KbEntry, entry_id, ENTRY_NOT_FOUND)
    fr = translation_of(entry, "fr")
    if not str(fr.get("question", "")).strip() or not str(fr.get("answer", "")).strip():
        raise HTTPException(status_code=409, detail="La question et la réponse en français sont obligatoires")
    now = utc_now()
    entry.status = STATUS_VALIDATED
    entry.validated_by_id = current_user.id
    entry.validated_at = now
    entry.updated_at = now
    db.commit()
    db.refresh(entry)
    logger.info("kb.entry_validated", entry_id=entry.id, validator_id=current_user.id)
    return kb_entry_out(entry)


@router.post("/entries/{entry_id}/archive", response_model=KbEntryOut)
def archive_entry(entry_id: str, db: Session = Depends(get_db)) -> KbEntryOut:
    entry = get_or_404(db, KbEntry, entry_id, ENTRY_NOT_FOUND)
    entry.status = STATUS_ARCHIVED
    entry.updated_at = utc_now()
    db.commit()
    db.refresh(entry)
    return kb_entry_out(entry)


@router.post("/entries/{entry_id}/audio/{lang}", response_model=KbEntryOut)
def upload_entry_audio(
    entry_id: str, lang: UserLang, audio: UploadFile = File(...), db: Session = Depends(get_db)
) -> KbEntryOut:
    """Enregistrement HUMAIN de la réponse dans une langue. C'est un nouveau
    contenu à écouter avant diffusion : l'entrée repasse en brouillon."""
    entry = get_or_404(db, KbEntry, entry_id, ENTRY_NOT_FOUND)
    raw = uploads.read_audio_upload(audio)
    try:
        relative_path = audio_store.save_human_audio("kb", entry.id, lang, raw, audio.filename or "audio")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    translations = {lg: translation_of(entry, lg) for lg in LANGS if translation_of(entry, lg)}
    previous_file = translations.get(lang, {}).get("audio_file")
    translations[lang] = {**translations.get(lang, {}), "audio_file": relative_path}
    entry.translations = translations
    mark_edited(entry)
    db.commit()
    db.refresh(entry)
    audio_store.delete_media_file(previous_file)
    return kb_entry_out(entry)


@router.post("/entries/{entry_id}/translate", response_model=KbEntryOut)
def machine_translate_entry(entry_id: str, db: Session = Depends(get_db)) -> KbEntryOut:
    """Remplit les textes mooré/dioula MANQUANTS par traduction automatique
    (moteur vérifié), marqués `machine_translated: true` jusqu'à ce qu'un
    humain les retouche. L'entrée repasse en brouillon : une traduction
    automatique doit être relue avant d'être servie."""
    entry = get_or_404(db, KbEntry, entry_id, ENTRY_NOT_FOUND)
    fr = translation_of(entry, "fr")
    question_fr = str(fr.get("question", "")).strip()
    answer_fr = str(fr.get("answer", "")).strip()
    if not question_fr or not answer_fr:
        raise HTTPException(status_code=409, detail="La question et la réponse en français sont obligatoires")
    if not translation_service.is_loaded:
        raise HTTPException(status_code=503, detail="Modèle de traduction non chargé")

    translations = {lg: translation_of(entry, lg) for lg in LANGS if translation_of(entry, lg)}
    filled = False
    for lang in ("mos", "dyu"):
        current = translations.get(lang, {})
        missing_question = not str(current.get("question", "")).strip()
        missing_answer = not str(current.get("answer", "")).strip()
        if not (missing_question or missing_answer):
            continue
        try:
            question = (
                translation_service.translate(question_fr, "fr", lang) if missing_question else current["question"]
            )
            answer = translation_service.translate(answer_fr, "fr", lang) if missing_answer else current["answer"]
        except ValueError as e:
            raise HTTPException(status_code=400, detail=str(e)) from e
        translations[lang] = {
            "question": question,
            "variants": current.get("variants", []),
            "answer": answer,
            "audio_file": current.get("audio_file"),
            "machine_translated": True,
        }
        filled = True

    if filled:
        entry.translations = translations
        mark_edited(entry)
        db.commit()
        db.refresh(entry)
    return kb_entry_out(entry)


# --- Signes de danger ---------------------------------------------------------


def _stored_danger_translations(sign: DangerSign) -> dict[str, Any]:
    """Traductions actuelles sous leur forme complète (voir
    `danger_sign_translation`) : sert de base à la fusion ET à la détection
    d'une vraie modification."""
    return {lang: value for lang in LANGS if (value := danger_sign_translation(sign, lang))}


def _danger_translations(payload: DangerSignIn, sign: DangerSign | None) -> dict[str, Any]:
    merged: dict[str, Any] = _stored_danger_translations(sign) if sign else {}
    for lang, incoming in payload.translations.items():
        refer_when = (incoming.refer_when or "").strip()
        merged[lang] = {
            "label": incoming.label.strip(),
            "advice": incoming.advice.strip(),
            "agent_questions": _clean_variants(incoming.agent_questions),
            "refer_when": refer_when or None,
        }
    return {lang: value for lang, value in merged.items() if value}


def _clean_keywords(keywords: list[str]) -> list[str]:
    seen: list[str] = []
    for keyword in keywords:
        cleaned = keyword.strip()
        if cleaned and cleaned not in seen:
            seen.append(cleaned)
    return seen


@router.get("/danger-signs", response_model=list[DangerSignOut])
def list_danger_signs(status: ContentStatus | None = None, db: Session = Depends(get_db)) -> list[DangerSignOut]:
    query = select(DangerSign).order_by(DangerSign.created_at)
    if status is not None:
        query = query.where(DangerSign.status == status)
    return [danger_sign_out(s) for s in db.scalars(query)]


@router.post("/danger-signs", response_model=DangerSignOut, status_code=201)
def create_danger_sign(payload: DangerSignIn, db: Session = Depends(get_db)) -> DangerSignOut:
    sign = DangerSign(
        status=STATUS_DRAFT,
        translations=_danger_translations(payload, None),
        keywords_fr=_clean_keywords(payload.keywords_fr),
        source=payload.source,
    )
    db.add(sign)
    db.commit()
    db.refresh(sign)
    return danger_sign_out(sign)


@router.put("/danger-signs/{sign_id}", response_model=DangerSignOut)
def update_danger_sign(sign_id: str, payload: DangerSignIn, db: Session = Depends(get_db)) -> DangerSignOut:
    sign = get_or_404(db, DangerSign, sign_id, SIGN_NOT_FOUND)
    translations = _danger_translations(payload, sign)
    keywords = _clean_keywords(payload.keywords_fr)
    changed = (
        translations != _stored_danger_translations(sign)
        or keywords != list(sign.keywords_fr or [])
        or payload.source != sign.source
    )
    if changed:
        sign.translations = translations
        sign.keywords_fr = keywords
        sign.source = payload.source
        mark_edited(sign)
        db.commit()
        db.refresh(sign)
    return danger_sign_out(sign)


@router.delete("/danger-signs/{sign_id}", status_code=204)
def delete_danger_sign(sign_id: str, db: Session = Depends(get_db)) -> Response:
    db.delete(get_or_404(db, DangerSign, sign_id, SIGN_NOT_FOUND))
    db.commit()
    return Response(status_code=204)


@router.post("/danger-signs/{sign_id}/validate", response_model=DangerSignOut)
def validate_danger_sign(
    sign_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_kb_staff),
) -> DangerSignOut:
    sign = get_or_404(db, DangerSign, sign_id, SIGN_NOT_FOUND)
    fr = translation_of(sign, "fr")
    if not str(fr.get("label", "")).strip() or not str(fr.get("advice", "")).strip():
        raise HTTPException(status_code=409, detail="Le libellé et le conseil en français sont obligatoires")
    now = utc_now()
    sign.status = STATUS_VALIDATED
    sign.validated_by_id = current_user.id
    sign.validated_at = now
    sign.updated_at = now
    db.commit()
    db.refresh(sign)
    logger.info("kb.danger_sign_validated", sign_id=sign.id, validator_id=current_user.id)
    return danger_sign_out(sign)


@router.post("/danger-signs/{sign_id}/archive", response_model=DangerSignOut)
def archive_danger_sign(sign_id: str, db: Session = Depends(get_db)) -> DangerSignOut:
    sign = get_or_404(db, DangerSign, sign_id, SIGN_NOT_FOUND)
    sign.status = STATUS_ARCHIVED
    sign.updated_at = utc_now()
    db.commit()
    db.refresh(sign)
    return danger_sign_out(sign)


# --- Questions sans réponse ---------------------------------------------------


@router.get("/unanswered", response_model=list[UnansweredOut])
def list_unanswered(resolved: bool | None = None, db: Session = Depends(get_db)) -> list[UnansweredQuestion]:
    query = select(UnansweredQuestion).order_by(UnansweredQuestion.created_at.desc())
    if resolved is not None:
        query = query.where(UnansweredQuestion.resolved.is_(resolved))
    return list(db.scalars(query))


@router.post("/unanswered/{question_id}/resolve", status_code=204)
def resolve_unanswered(question_id: str, db: Session = Depends(get_db)) -> Response:
    question = get_or_404(db, UnansweredQuestion, question_id, "Question introuvable")
    if not question.resolved:
        question.resolved = True
        question.resolved_at = utc_now()
        db.commit()
    return Response(status_code=204)
