"""
Annuaire d'aide et de protection (module 3).

Lecture publique (sans compte) : une femme en danger ne doit avoir aucune
étape à franchir pour trouver un numéro. Écriture réservée aux admins.

`verified_at` : date à laquelle l'équipe a confirmé le numéro (en
l'appelant). `null` = pas encore confirmé, et l'app doit l'afficher comme tel
— un numéro qui ne répond pas, au moment où l'on en a besoin, est pire que
pas de numéro du tout.
"""

from fastapi import APIRouter, Depends, Response
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.auth import get_optional_current_user, require_roles
from app.db import get_db
from app.db_models import ROLE_ADMIN, HelpService, User
from app.db_types import utc_now
from app.routers.common import get_or_404
from app.schemas.help import HelpCategory, HelpServiceIn, HelpServiceOut

router = APIRouter(prefix="/help", tags=["Aide et protection"])

require_admin = require_roles(ROLE_ADMIN)
NOT_FOUND = "Service introuvable"


def _to_out(service: HelpService) -> HelpServiceOut:
    return HelpServiceOut(
        id=service.id,
        name=service.name,
        category=service.category,
        phone=service.phone,
        city=service.city,
        region=service.region,
        address=service.address,
        hours=service.hours,
        free_call=service.free_call,
        languages=list(service.languages or []),
        source_url=service.source_url,
        verified_at=service.verified_at,
        active=service.active,
    )


@router.get("/services", response_model=list[HelpServiceOut])
def list_services(
    city: str | None = None,
    category: HelpCategory | None = None,
    include_inactive: bool = False,
    db: Session = Depends(get_db),
    current_user: User | None = Depends(get_optional_current_user),
) -> list[HelpServiceOut]:
    """Services ACTIFS uniquement — sauf `include_inactive=true` envoyé par un
    admin (console), ignoré pour tout autre appelant. Le filtre `city` garde
    aussi les services sans ville (numéros nationaux, ex: le numéro vert
    VBG) : ils sont joignables de partout, les masquer serait une erreur grave."""
    query = select(HelpService)
    if not (include_inactive and current_user is not None and current_user.role == ROLE_ADMIN):
        query = query.where(HelpService.active.is_(True))
    if city and city.strip():
        query = query.where(or_(HelpService.city.is_(None), func.lower(HelpService.city) == city.strip().lower()))
    if category is not None:
        query = query.where(HelpService.category == category)
    query = query.order_by(HelpService.city.is_not(None), HelpService.category, HelpService.name)
    return [_to_out(s) for s in db.scalars(query)]


@router.post("/services", response_model=HelpServiceOut, status_code=201, dependencies=[Depends(require_admin)])
def create_service(payload: HelpServiceIn, db: Session = Depends(get_db)) -> HelpServiceOut:
    service = HelpService(**payload.model_dump())
    db.add(service)
    db.commit()
    db.refresh(service)
    return _to_out(service)


@router.put("/services/{service_id}", response_model=HelpServiceOut, dependencies=[Depends(require_admin)])
def update_service(service_id: str, payload: HelpServiceIn, db: Session = Depends(get_db)) -> HelpServiceOut:
    service = get_or_404(db, HelpService, service_id, NOT_FOUND)
    # Un numéro modifié n'est plus celui qui avait été vérifié.
    if payload.phone.strip() != service.phone.strip():
        service.verified_at = None
    for field, value in payload.model_dump().items():
        setattr(service, field, value)
    service.updated_at = utc_now()
    db.commit()
    db.refresh(service)
    return _to_out(service)


@router.delete("/services/{service_id}", status_code=204, dependencies=[Depends(require_admin)])
def delete_service(service_id: str, db: Session = Depends(get_db)) -> Response:
    db.delete(get_or_404(db, HelpService, service_id, NOT_FOUND))
    db.commit()
    return Response(status_code=204)


@router.post("/services/{service_id}/verify", response_model=HelpServiceOut, dependencies=[Depends(require_admin)])
def verify_service(service_id: str, db: Session = Depends(get_db)) -> HelpServiceOut:
    service = get_or_404(db, HelpService, service_id, NOT_FOUND)
    service.verified_at = utc_now().date()
    service.updated_at = utc_now()
    db.commit()
    db.refresh(service)
    return _to_out(service)
