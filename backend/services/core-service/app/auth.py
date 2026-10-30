"""
Authentification par jeton JWT et contrôle des rôles.

Deux sortes de comptes, un seul format de jeton :

1. Les femmes (`woman`) : compte ANONYME créé par l'appareil
   (`POST /auth/device`), sans nom, téléphone ni email. Le jeton dure
   `DEVICE_TOKEN_EXPIRE_DAYS` et se renouvelle avec le code de récupération.
   Ce compte ne sert qu'à la sauvegarde chiffrée optionnelle : l'app
   fonctionne entièrement sans.
2. Le personnel (`agent`, `validator`, `admin`) : email + mot de passe,
   jeton court (`JWT_EXPIRE_MINUTES`).

Pourquoi un JWT : sa signature suffit à prouver qu'il a été émis par nous et
n'a pas expiré, sans consulter la base à chaque requête. On la consulte quand
même ici pour relire le rôle et l'état `active` : un compte désactivé ou
rétrogradé par un admin perd ses droits immédiatement, pas à l'expiration du
jeton.
"""

from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any

import jwt
from fastapi import Depends, Header, HTTPException
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.db_models import ROLE_WOMAN, User

TOKEN_TYPE = "user"


def create_user_token(user: User) -> str:
    if user.role == ROLE_WOMAN:
        lifetime = timedelta(days=settings.device_token_expire_days)
    else:
        lifetime = timedelta(minutes=settings.jwt_expire_minutes)
    payload = {"sub": user.id, "type": TOKEN_TYPE, "exp": datetime.now(UTC) + lifetime}
    return jwt.encode(payload, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)


def _decode_token(authorization: str | None) -> dict[str, Any]:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401, detail="En-tête Authorization manquant ou mal formé (attendu: 'Bearer <jeton>')"
        )

    token = authorization.removeprefix("Bearer ").strip()
    try:
        payload: dict[str, Any] = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
    except jwt.ExpiredSignatureError as e:
        raise HTTPException(status_code=401, detail="Jeton expiré, reconnectez-vous") from e
    except jwt.InvalidTokenError as e:
        raise HTTPException(status_code=401, detail="Jeton invalide") from e

    if payload.get("type") != TOKEN_TYPE or not isinstance(payload.get("sub"), str):
        raise HTTPException(status_code=401, detail="Jeton invalide")
    return payload


def get_current_user(authorization: str | None = Header(default=None), db: Session = Depends(get_db)) -> User:
    """Dépendance FastAPI : le compte authentifié, quel que soit son rôle."""
    payload = _decode_token(authorization)
    user = db.get(User, payload["sub"])
    if user is None:
        raise HTTPException(status_code=401, detail="Compte introuvable (supprimé ?)")
    if not user.active:
        raise HTTPException(status_code=403, detail="Compte désactivé")
    return user


def get_optional_current_user(
    authorization: str | None = Header(default=None), db: Session = Depends(get_db)
) -> User | None:
    """Comme `get_current_user`, mais renvoie `None` au lieu d'une erreur :
    pour les endpoints publics qui offrent un peu plus au personnel connecté
    (ex: la console admin qui liste les capsules en brouillon)."""
    if not authorization:
        return None
    try:
        return get_current_user(authorization, db)
    except HTTPException:
        return None


def require_roles(*roles: str) -> Callable[..., User]:
    """Fabrique de dépendance : exige que le compte ait l'un des rôles donnés.

    403 (et pas 404) : on ne cache pas l'EXISTENCE de ces routes, seulement
    leur accès — cohérent avec le reste de l'API.
    """
    allowed = frozenset(roles)

    def _dependency(current_user: User = Depends(get_current_user)) -> User:
        if current_user.role not in allowed:
            raise HTTPException(status_code=403, detail="Accès refusé pour ce rôle")
        return current_user

    return _dependency
