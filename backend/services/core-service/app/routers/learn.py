"""
Capsules d'apprentissage (module 5).

Lecture publique : capsules VALIDÉES uniquement. Le personnel de contenu
(validateurs, admins) peut aussi lister les brouillons et archives avec
`?include_drafts=true` (tous statuts) ou `?status=` (un statut précis) —
c'est ainsi que la console d'administration les retrouve. Pour tout autre
appelant, ces paramètres sont ignorés.
Création, modification et validation : validateurs et admins. Comme pour la
base de connaissances, toute modification renvoie la capsule en brouillon.
"""

from typing import Any

from fastapi import APIRouter, Depends, File, HTTPException, Response, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import audio_store, uploads
from app.auth import get_optional_current_user, require_roles
from app.content import LANGS, capsule_has_text, capsule_out, mark_edited, translation_of
from app.db import get_db
from app.db_models import ROLE_ADMIN, ROLE_VALIDATOR, STATUS_ARCHIVED, STATUS_DRAFT, STATUS_VALIDATED, Capsule, User
from app.db_types import utc_now
from app.languages import UserLang
from app.routers.common import get_or_404
from app.schemas.common import ContentStatus
from app.schemas.learn import CapsuleIn, CapsuleOut, Track

router = APIRouter(prefix="/learn", tags=["Capsules"])

CONTENT_STAFF = (ROLE_VALIDATOR, ROLE_ADMIN)
require_content_staff = require_roles(*CONTENT_STAFF)
NOT_FOUND = "Capsule introuvable"


def _merged_translations(capsule: Capsule | None, payload: CapsuleIn) -> dict[str, Any]:
    """Même règle de fusion que la base de connaissances : une langue absente
    du corps est conservée, l'enregistrement humain aussi."""
    merged: dict[str, Any] = {lang: translation_of(capsule, lang) for lang in LANGS} if capsule else {}
    for lang, incoming in payload.translations.items():
        previous = merged.get(lang, {})
        merged[lang] = {
            "title": incoming.title.strip(),
            "text": incoming.text.strip(),
            "audio_file": previous.get("audio_file"),
        }
    return {lang: value for lang, value in merged.items() if value}


@router.get("/capsules", response_model=list[CapsuleOut])
def list_capsules(
    lang: UserLang | None = None,
    track: Track | None = None,
    status: ContentStatus | None = None,
    include_drafts: bool = False,
    db: Session = Depends(get_db),
    current_user: User | None = Depends(get_optional_current_user),
) -> list[CapsuleOut]:
    is_content_staff = current_user is not None and current_user.role in CONTENT_STAFF
    # Le public ne voit QUE le validé, quels que soient les paramètres.
    if not is_content_staff:
        status, include_drafts = None, False

    query = select(Capsule).order_by(Capsule.track, Capsule.order)
    if status is not None:
        query = query.where(Capsule.status == status)
    elif not include_drafts:
        query = query.where(Capsule.status == STATUS_VALIDATED)
    if track is not None:
        query = query.where(Capsule.track == track)
    capsules = list(db.scalars(query))
    if lang is not None:
        capsules = [c for c in capsules if capsule_has_text(c, lang)]
    # Vue "servie" (synthèse vocale) seulement pour le contenu validé.
    return [capsule_out(c, served=c.status == STATUS_VALIDATED) for c in capsules]


@router.post("/capsules", response_model=CapsuleOut, status_code=201, dependencies=[Depends(require_content_staff)])
def create_capsule(payload: CapsuleIn, db: Session = Depends(get_db)) -> CapsuleOut:
    capsule = Capsule(
        track=payload.track,
        status=STATUS_DRAFT,
        order=payload.order,
        translations=_merged_translations(None, payload),
        quiz=[q.model_dump() for q in payload.quiz],
        license=payload.license,
    )
    db.add(capsule)
    db.commit()
    db.refresh(capsule)
    return capsule_out(capsule, served=False)


@router.put("/capsules/{capsule_id}", response_model=CapsuleOut, dependencies=[Depends(require_content_staff)])
def update_capsule(capsule_id: str, payload: CapsuleIn, db: Session = Depends(get_db)) -> CapsuleOut:
    capsule = get_or_404(db, Capsule, capsule_id, NOT_FOUND)
    translations = _merged_translations(capsule, payload)
    quiz = [q.model_dump() for q in payload.quiz]
    # La console n'envoie pas `license` : absente du corps, elle est conservée.
    license_ = payload.license if "license" in payload.model_fields_set else capsule.license
    changed = (
        capsule.track != payload.track
        or capsule.order != payload.order
        or capsule.license != license_
        or quiz != list(capsule.quiz or [])
        or translations != {lang: translation_of(capsule, lang) for lang in LANGS if translation_of(capsule, lang)}
    )
    if changed:
        capsule.track = payload.track
        capsule.order = payload.order
        capsule.license = license_
        capsule.quiz = quiz
        capsule.translations = translations
        mark_edited(capsule)
        db.commit()
        db.refresh(capsule)
    return capsule_out(capsule, served=False)


@router.delete("/capsules/{capsule_id}", status_code=204, dependencies=[Depends(require_content_staff)])
def delete_capsule(capsule_id: str, db: Session = Depends(get_db)) -> Response:
    capsule = get_or_404(db, Capsule, capsule_id, NOT_FOUND)
    audio_files = [translation_of(capsule, lang).get("audio_file") for lang in LANGS]
    db.delete(capsule)
    db.commit()
    for audio_file in audio_files:
        audio_store.delete_media_file(audio_file)
    return Response(status_code=204)


@router.post("/capsules/{capsule_id}/validate", response_model=CapsuleOut)
def validate_capsule(
    capsule_id: str, db: Session = Depends(get_db), current_user: User = Depends(require_content_staff)
) -> CapsuleOut:
    capsule = get_or_404(db, Capsule, capsule_id, NOT_FOUND)
    if not capsule_has_text(capsule, "fr"):
        raise HTTPException(status_code=409, detail="Le titre et le texte en français sont obligatoires")
    now = utc_now()
    capsule.status = STATUS_VALIDATED
    capsule.validated_by_id = current_user.id
    capsule.validated_at = now
    capsule.updated_at = now
    db.commit()
    db.refresh(capsule)
    return capsule_out(capsule, served=False)


@router.post("/capsules/{capsule_id}/archive", response_model=CapsuleOut, dependencies=[Depends(require_content_staff)])
def archive_capsule(capsule_id: str, db: Session = Depends(get_db)) -> CapsuleOut:
    capsule = get_or_404(db, Capsule, capsule_id, NOT_FOUND)
    capsule.status = STATUS_ARCHIVED
    capsule.updated_at = utc_now()
    db.commit()
    db.refresh(capsule)
    return capsule_out(capsule, served=False)


@router.post(
    "/capsules/{capsule_id}/audio/{lang}", response_model=CapsuleOut, dependencies=[Depends(require_content_staff)]
)
def upload_capsule_audio(
    capsule_id: str, lang: UserLang, audio: UploadFile = File(...), db: Session = Depends(get_db)
) -> CapsuleOut:
    capsule = get_or_404(db, Capsule, capsule_id, NOT_FOUND)
    raw = uploads.read_audio_upload(audio)
    try:
        relative_path = audio_store.save_human_audio("capsules", capsule.id, lang, raw, audio.filename or "audio")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    translations = {lg: translation_of(capsule, lg) for lg in LANGS if translation_of(capsule, lg)}
    previous_file = translations.get(lang, {}).get("audio_file")
    translations[lang] = {**translations.get(lang, {}), "audio_file": relative_path}
    capsule.translations = translations
    mark_edited(capsule)
    db.commit()
    db.refresh(capsule)
    audio_store.delete_media_file(previous_file)
    return capsule_out(capsule, served=False)
