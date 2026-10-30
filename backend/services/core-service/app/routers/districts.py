"""
Districts sanitaires. Liste VIDE tant qu'un admin n'a pas saisi la liste
officielle : aucun district n'est inventé ni pré-rempli.
"""

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.auth import require_roles
from app.db import get_db
from app.db_models import ROLE_ADMIN, District, User
from app.routers.common import get_or_404
from app.schemas.misc import DistrictIn, DistrictOut

router = APIRouter(prefix="/districts", tags=["Districts"])
require_admin = require_roles(ROLE_ADMIN)
NOT_FOUND = "District introuvable"
DUPLICATE = "Ce district existe déjà dans cette région"


@router.get("", response_model=list[DistrictOut])
def list_districts(db: Session = Depends(get_db)) -> list[District]:
    return list(db.scalars(select(District).order_by(District.region, District.name)))


@router.post("", response_model=DistrictOut, status_code=201, dependencies=[Depends(require_admin)])
def create_district(payload: DistrictIn, db: Session = Depends(get_db)) -> District:
    district = District(name=payload.name.strip(), region=payload.region.strip())
    db.add(district)
    try:
        db.commit()
    except IntegrityError as e:
        db.rollback()
        raise HTTPException(status_code=409, detail=DUPLICATE) from e
    db.refresh(district)
    return district


@router.put("/{district_id}", response_model=DistrictOut, dependencies=[Depends(require_admin)])
def update_district(district_id: str, payload: DistrictIn, db: Session = Depends(get_db)) -> District:
    district = get_or_404(db, District, district_id, NOT_FOUND)
    district.name = payload.name.strip()
    district.region = payload.region.strip()
    try:
        db.commit()
    except IntegrityError as e:
        db.rollback()
        raise HTTPException(status_code=409, detail=DUPLICATE) from e
    db.refresh(district)
    return district


@router.delete("/{district_id}", status_code=204, dependencies=[Depends(require_admin)])
def delete_district(district_id: str, db: Session = Depends(get_db)) -> Response:
    district = get_or_404(db, District, district_id, NOT_FOUND)
    # Détache explicitement les comptes du personnel (en plus du
    # `ON DELETE SET NULL` du schéma, que SQLite n'applique que si les clés
    # étrangères sont activées sur la connexion).
    db.execute(update(User).where(User.district_id == district.id).values(district_id=None))
    db.delete(district)
    db.commit()
    return Response(status_code=204)
