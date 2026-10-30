"""
Comptes : appareil anonyme (femmes), connexion du personnel, profil.

Une femme n'a jamais besoin de compte : l'app fonctionne entièrement hors
ligne. Le compte "appareil" ne sert qu'à la sauvegarde chiffrée facultative ;
il ne contient ni nom, ni téléphone, ni email — seulement l'empreinte d'un
code de récupération montré une seule fois.
"""

import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.auth import create_user_token, get_current_user, require_roles
from app.db import get_db
from app.db_models import ROLE_ADMIN, ROLE_WOMAN, STAFF_ROLES, User
from app.limiter import limiter
from app.logging_config import get_logger
from app.schemas.auth import (
    ChangePasswordRequest,
    DeviceAccountResponse,
    LoginRequest,
    MeResponse,
    RecoverRequest,
    TokenResponse,
)
from app.security import (
    generate_recovery_code,
    hash_password,
    normalize_recovery_code,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["Authentification"])
logger = get_logger(__name__)


@router.post("/device", response_model=DeviceAccountResponse, status_code=201)
@limiter.limit("5/minute")
def create_device_account(request: Request, db: Session = Depends(get_db)) -> DeviceAccountResponse:
    """Crée un compte anonyme `woman`. Le code de récupération n'est renvoyé
    QU'ICI : le serveur n'en garde que l'empreinte bcrypt et ne pourra jamais
    le redonner."""
    recovery_code = generate_recovery_code()
    user = User(role=ROLE_WOMAN, recovery_code_hash=hash_password(recovery_code))
    db.add(user)
    db.commit()
    db.refresh(user)
    # Aucune donnée d'identification dans les logs : l'identifiant du compte
    # anonyme lui-même n'y figure pas.
    logger.info("device_account.created")
    return DeviceAccountResponse(access_token=create_user_token(user), account_id=user.id, recovery_code=recovery_code)


@router.post("/device/recover", response_model=TokenResponse)
@limiter.limit("5/minute")
def recover_device_account(request: Request, payload: RecoverRequest, db: Session = Depends(get_db)) -> TokenResponse:
    """Nouveau jeton à partir du couple (identifiant, code de récupération) :
    sert à la fois au renouvellement du jeton et à la restauration sur un
    nouveau téléphone. Même réponse 401 quel que soit ce qui est faux."""
    invalid = HTTPException(status_code=401, detail="Identifiant ou code de récupération incorrect")
    try:
        account_id = str(uuid.UUID(payload.account_id))
    except ValueError as e:
        raise invalid from e

    user = db.get(User, account_id)
    if user is None or user.role != ROLE_WOMAN or not user.active:
        raise invalid
    if not verify_password(normalize_recovery_code(payload.recovery_code), user.recovery_code_hash):
        raise invalid
    return TokenResponse(access_token=create_user_token(user))


@router.post("/login", response_model=TokenResponse)
@limiter.limit("20/minute")  # ralentit une attaque par force brute sur le mot de passe
def login(request: Request, payload: LoginRequest, db: Session = Depends(get_db)) -> TokenResponse:
    """Connexion du personnel (agent, validateur, admin).

    Message d'erreur IDENTIQUE que l'email n'existe pas ou que le mot de
    passe soit faux : sinon un attaquant pourrait deviner quels emails ont un
    compte chez nous."""
    user = db.scalar(select(User).where(func.lower(User.email) == payload.email.lower()))
    invalid_credentials = HTTPException(status_code=401, detail="Email ou mot de passe incorrect")
    if user is None or user.role not in STAFF_ROLES:
        raise invalid_credentials
    if not verify_password(payload.password, user.hashed_password):
        raise invalid_credentials
    if not user.active:
        raise HTTPException(status_code=403, detail="Compte désactivé")

    logger.info("staff.login", user_id=user.id, role=user.role)
    return TokenResponse(access_token=create_user_token(user))


@router.get("/me", response_model=MeResponse)
def get_me(current_user: User = Depends(get_current_user)) -> User:
    return current_user


@router.post("/change-password", status_code=204)
@limiter.limit("10/minute")
def change_password(
    request: Request,
    payload: ChangePasswordRequest,
    current_user: User = Depends(require_roles(*STAFF_ROLES)),
    db: Session = Depends(get_db),
) -> Response:
    # 400 et pas 401 : la personne EST authentifiée (jeton valide) ; un 401
    # pousserait l'app cliente à la déconnecter pour une simple faute de frappe.
    if not verify_password(payload.current_password, current_user.hashed_password):
        raise HTTPException(status_code=400, detail="Mot de passe actuel incorrect")

    current_user.hashed_password = hash_password(payload.new_password)
    db.commit()
    logger.info("staff.password_changed", user_id=current_user.id)
    return Response(status_code=204)


@router.delete("/me", status_code=204)
def delete_account(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> Response:
    """Supprime définitivement le compte ET tout ce qui y est rattaché
    (sauvegarde chiffrée ; pour un agent : bénéficiaires, visites et
    orientations). L'app doit faire confirmer l'action AVANT l'appel.

    Seule exception : le dernier admin actif ne peut pas se supprimer, sinon
    plus personne ne pourrait administrer la plateforme."""
    if current_user.role == ROLE_ADMIN:
        active_admins = db.scalar(
            select(func.count()).select_from(User).where(User.role == ROLE_ADMIN, User.active.is_(True))
        )
        if (active_admins or 0) <= 1:
            raise HTTPException(status_code=409, detail="Impossible de supprimer le dernier compte administrateur")

    if current_user.role != ROLE_WOMAN:
        logger.info("staff.account_deleted", user_id=current_user.id)
    db.delete(current_user)
    db.commit()
    return Response(status_code=204)
