"""
Administration (console React, voir `admin/`) — rôle `admin` sur TOUT le
routeur : impossible d'oublier la protection sur un futur endpoint.

Règle de confidentialité : les comptes `woman` ne sont JAMAIS listés ni
manipulables individuellement ici. L'admin ne voit que leur NOMBRE.
"""

import os
import shutil
from datetime import timedelta
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.audio_store import media_root
from app.auth import require_roles
from app.db import get_db
from app.db_models import (
    ROLE_ADMIN,
    ROLE_AGENT,
    ROLE_VALIDATOR,
    ROLE_WOMAN,
    STAFF_ROLES,
    STATUS_DRAFT,
    STATUS_SOURCED,
    STATUS_VALIDATED,
    Capsule,
    District,
    EventCount,
    KbEntry,
    UnansweredQuestion,
    User,
)
from app.db_types import utc_now
from app.logging_config import get_logger
from app.routers.meta import health_payload
from app.schemas.auth import (
    AdminStatsResponse,
    AdminUser,
    CreateUserRequest,
    CreateUserResponse,
    DraftValidatedCount,
    StaffRole,
    TemporaryPasswordResponse,
    UpdateUserRequest,
)
from app.security import generate_temporary_password, hash_password

require_admin = require_roles(ROLE_ADMIN)
router = APIRouter(prefix="/admin", tags=["Administration"], dependencies=[Depends(require_admin)])
logger = get_logger(__name__)

NOT_FOUND = "Utilisateur introuvable"


def _staff_or_404(db: Session, user_id: str) -> User:
    """404 aussi pour un compte `woman` : ils n'existent pas pour la console."""
    user = db.get(User, user_id)
    if user is None or user.role not in STAFF_ROLES:
        raise HTTPException(status_code=404, detail=NOT_FOUND)
    return user


def _check_district(db: Session, district_id: str | None) -> None:
    if district_id is not None and db.get(District, district_id) is None:
        raise HTTPException(status_code=422, detail="District inconnu")


def _count(db: Session, *conditions: Any, model: Any = User) -> int:
    return db.scalar(select(func.count()).select_from(model).where(*conditions)) or 0


@router.get("/users", response_model=list[AdminUser])
def list_users(role: StaffRole | None = None, db: Session = Depends(get_db)) -> list[User]:
    query = select(User).where(User.role.in_(STAFF_ROLES)).order_by(User.created_at.desc())
    if role is not None:
        query = query.where(User.role == role)
    return list(db.scalars(query))


@router.post("/users", response_model=CreateUserResponse, status_code=201)
def create_user(payload: CreateUserRequest, db: Session = Depends(get_db)) -> CreateUserResponse:
    _check_district(db, payload.district_id)
    email = payload.email.lower()
    if db.scalar(select(User).where(func.lower(User.email) == email)) is not None:
        raise HTTPException(status_code=409, detail="Un compte existe déjà avec cet email")

    temporary_password = generate_temporary_password()
    user = User(
        role=payload.role,
        email=email,
        full_name=payload.full_name.strip(),
        district_id=payload.district_id,
        hashed_password=hash_password(temporary_password),
    )
    db.add(user)
    try:
        db.commit()
    except IntegrityError as e:
        # Deux créations simultanées du même email : seule la contrainte
        # d'unicité les départage vraiment.
        db.rollback()
        raise HTTPException(status_code=409, detail="Un compte existe déjà avec cet email") from e
    db.refresh(user)
    logger.info("admin.user_created", user_id=user.id, role=user.role)
    return CreateUserResponse(user=AdminUser.model_validate(user), temporary_password=temporary_password)


@router.patch("/users/{user_id}", response_model=AdminUser)
def update_user(
    user_id: str,
    payload: UpdateUserRequest,
    db: Session = Depends(get_db),
    current_admin: User = Depends(require_admin),
) -> User:
    user = _staff_or_404(db, user_id)
    fields = payload.model_fields_set
    if user.id == current_admin.id and (
        ("role" in fields and payload.role != ROLE_ADMIN) or ("active" in fields and payload.active is False)
    ):
        raise HTTPException(status_code=400, detail="Vous ne pouvez pas retirer vos propres droits d'administration")

    if "role" in fields and payload.role is not None:
        user.role = payload.role
    if "full_name" in fields and payload.full_name is not None:
        user.full_name = payload.full_name.strip()
    if "district_id" in fields:
        _check_district(db, payload.district_id)
        user.district_id = payload.district_id
    if "active" in fields and payload.active is not None:
        user.active = payload.active
    db.commit()
    db.refresh(user)
    return user


@router.post("/users/{user_id}/reset-password", response_model=TemporaryPasswordResponse)
def reset_password(user_id: str, db: Session = Depends(get_db)) -> TemporaryPasswordResponse:
    """Pas de réinitialisation par email : l'admin génère un mot de passe
    temporaire qu'il transmet lui-même à la personne (montré une seule fois)."""
    user = _staff_or_404(db, user_id)
    temporary_password = generate_temporary_password()
    user.hashed_password = hash_password(temporary_password)
    db.commit()
    logger.info("admin.password_reset", user_id=user.id)
    return TemporaryPasswordResponse(temporary_password=temporary_password)


@router.delete("/users/{user_id}", status_code=204)
def delete_user(user_id: str, db: Session = Depends(get_db), current_admin: User = Depends(require_admin)) -> Response:
    if user_id == current_admin.id:
        raise HTTPException(
            status_code=400, detail="Vous ne pouvez pas supprimer votre propre compte depuis la console"
        )
    user = _staff_or_404(db, user_id)
    db.delete(user)
    db.commit()
    logger.info("admin.user_deleted", user_id=user_id)
    return Response(status_code=204)


@router.get("/stats", response_model=AdminStatsResponse)
def get_stats(db: Session = Depends(get_db)) -> AdminStatsResponse:
    since = (utc_now() - timedelta(days=30)).date()
    events = db.scalar(select(func.coalesce(func.sum(EventCount.count), 0)).where(EventCount.occurred_on >= since))
    return AdminStatsResponse(
        women_accounts=_count(db, User.role == ROLE_WOMAN),
        agents=_count(db, User.role == ROLE_AGENT),
        validators=_count(db, User.role == ROLE_VALIDATOR),
        kb=DraftValidatedCount(
            draft=_count(db, KbEntry.status == STATUS_DRAFT, model=KbEntry),
            sourced=_count(db, KbEntry.status == STATUS_SOURCED, model=KbEntry),
            validated=_count(db, KbEntry.status == STATUS_VALIDATED, model=KbEntry),
        ),
        capsules=DraftValidatedCount(
            draft=_count(db, Capsule.status == STATUS_DRAFT, model=Capsule),
            sourced=_count(db, Capsule.status == STATUS_SOURCED, model=Capsule),
            validated=_count(db, Capsule.status == STATUS_VALIDATED, model=Capsule),
        ),
        unanswered_open=_count(db, UnansweredQuestion.resolved.is_(False), model=UnansweredQuestion),
        events_last_30_days=int(events or 0),
    )


@router.get("/health")
def get_health() -> dict[str, Any]:
    """Comme /health, plus l'état du disque qui héberge les fichiers audio
    (synthèses mises en cache, enregistrements humains)."""
    payload = health_payload()
    root = media_root()
    usage = shutil.disk_usage(root)
    payload["disk"] = {
        "media_dir": str(root),
        "media_dir_writable": os.access(root, os.W_OK),
        "free_bytes": usage.free,
        "total_bytes": usage.total,
    }
    return payload
