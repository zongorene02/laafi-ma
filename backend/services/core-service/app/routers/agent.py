"""
Espace agent de santé communautaire (module 4) — rôle `agent`.

Tout est CLOISONNÉ par agent : un agent ne voit et ne modifie que ses propres
fiches. Les identifiants sont créés sur l'appareil (UUID v4), ce qui permet
de saisir des fiches hors ligne en brousse puis de les synchroniser plus
tard.

Synchronisation (`POST /agent/sync`) :
- dernier-écrit-gagne sur `updated_at` (horodatage de l'appareil) : une
  version reçue n'écrase la version du serveur que si elle est plus récente ;
- `deleted: true` est une suppression LOGIQUE, propagée aux autres appareils ;
- le serveur renvoie ce qui a changé depuis `since`, mesuré sur `synced_at`
  (horloge du SERVEUR) — voir db_models.Beneficiary.

Un enregistrement qui ne peut pas être appliqué pendant une synchronisation
(identifiant appartenant à un autre agent, visite d'un bénéficiaire inconnu)
est ignoré et journalisé, sans faire échouer tout le lot : un appareil hors
ligne ne doit pas rester bloqué indéfiniment par une seule fiche.
"""

from datetime import datetime, timedelta
from enum import Enum

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.auth import require_roles
from app.db import get_db
from app.db_models import ROLE_AGENT, Beneficiary, GbvReferral, User, Visit
from app.db_types import utc_now
from app.logging_config import get_logger
from app.schemas.agent import (
    AgentSummary,
    BeneficiaryIn,
    BeneficiaryOut,
    GbvReferralIn,
    GbvReferralOut,
    SyncRequest,
    SyncResponse,
    VisitIn,
    VisitOut,
)

require_agent = require_roles(ROLE_AGENT)
router = APIRouter(prefix="/agent", tags=["Espace agent"])
logger = get_logger(__name__)


class Outcome(Enum):
    APPLIED = "applied"
    STALE = "stale"  # version reçue plus ancienne (ou égale) : ignorée
    FOREIGN = "foreign"  # identifiant déjà utilisé par un autre agent
    ORPHAN = "orphan"  # visite d'un bénéficiaire inconnu de cet agent


# --- Conversions --------------------------------------------------------------


def _beneficiary_out(b: Beneficiary) -> BeneficiaryOut:
    return BeneficiaryOut(
        id=b.id,
        pseudonym=b.pseudonym,
        village=b.village,
        age_range=b.age_range,
        pregnant=b.pregnant,
        expected_due_date=b.expected_due_date,
        children_under_5=b.children_under_5,
        next_appointment_date=b.next_appointment_date,
        next_appointment_reason=b.next_appointment_reason,
        consent_given_at=b.consent_given_at,
        notes=b.notes,
        updated_at=b.updated_at,
        deleted=b.deleted,
    )


def _visit_out(v: Visit) -> VisitOut:
    return VisitOut(
        id=v.id,
        beneficiary_id=v.beneficiary_id,
        visit_date=v.visit_date,
        type=v.type,
        danger_sign_ids=list(v.danger_sign_ids or []),
        referred=v.referred,
        referred_to=v.referred_to,
        notes=v.notes,
        updated_at=v.updated_at,
        deleted=v.deleted,
    )


def _referral_out(r: GbvReferral) -> GbvReferralOut:
    return GbvReferralOut(
        id=r.id, referral_date=r.referral_date, service_id=r.service_id, category=r.category, updated_at=r.updated_at
    )


# --- Écritures (dernier-écrit-gagne) ------------------------------------------


def _upsert_beneficiary(db: Session, agent: User, data: BeneficiaryIn, now: datetime) -> Outcome:
    incoming_at = data.updated_at or now
    existing = db.get(Beneficiary, data.id)
    if existing is not None and existing.agent_id != agent.id:
        return Outcome.FOREIGN
    if existing is not None and incoming_at <= existing.updated_at:
        return Outcome.STALE
    b = existing or Beneficiary(id=data.id, agent_id=agent.id)
    b.pseudonym = data.pseudonym
    b.village = data.village
    b.age_range = data.age_range
    b.pregnant = data.pregnant
    b.expected_due_date = data.expected_due_date
    b.children_under_5 = data.children_under_5
    b.next_appointment_date = data.next_appointment_date
    b.next_appointment_reason = data.next_appointment_reason
    b.consent_given_at = data.consent_given_at
    b.notes = data.notes
    b.deleted = data.deleted
    b.updated_at = incoming_at
    b.synced_at = now
    if existing is None:
        db.add(b)
    db.flush()
    return Outcome.APPLIED


def _upsert_visit(db: Session, agent: User, data: VisitIn, now: datetime) -> Outcome:
    incoming_at = data.updated_at or now
    existing = db.get(Visit, data.id)
    if existing is not None and existing.agent_id != agent.id:
        return Outcome.FOREIGN
    beneficiary = db.get(Beneficiary, data.beneficiary_id)
    if beneficiary is None or beneficiary.agent_id != agent.id:
        return Outcome.ORPHAN
    if existing is not None and incoming_at <= existing.updated_at:
        return Outcome.STALE
    v = existing or Visit(id=data.id, agent_id=agent.id)
    v.beneficiary_id = data.beneficiary_id
    v.visit_date = data.visit_date
    v.type = data.type
    v.danger_sign_ids = list(data.danger_sign_ids)
    v.referred = data.referred
    v.referred_to = data.referred_to
    v.notes = data.notes
    v.deleted = data.deleted
    v.updated_at = incoming_at
    v.synced_at = now
    if existing is None:
        db.add(v)
    db.flush()
    return Outcome.APPLIED


def _upsert_referral(db: Session, agent: User, data: GbvReferralIn, now: datetime) -> Outcome:
    incoming_at = data.updated_at or now
    existing = db.get(GbvReferral, data.id)
    if existing is not None and existing.agent_id != agent.id:
        return Outcome.FOREIGN
    if existing is not None and incoming_at <= existing.updated_at:
        return Outcome.STALE
    r = existing or GbvReferral(id=data.id, agent_id=agent.id)
    r.referral_date = data.referral_date
    r.service_id = data.service_id
    r.category = data.category
    r.updated_at = incoming_at
    r.synced_at = now
    if existing is None:
        db.add(r)
    db.flush()
    return Outcome.APPLIED


# --- Synchronisation ----------------------------------------------------------


@router.post("/sync", response_model=SyncResponse)
def sync(payload: SyncRequest, agent: User = Depends(require_agent), db: Session = Depends(get_db)) -> SyncResponse:
    now = utc_now()
    skipped: dict[str, int] = {}

    def _count(outcome: Outcome) -> None:
        if outcome in (Outcome.FOREIGN, Outcome.ORPHAN):
            skipped[outcome.value] = skipped.get(outcome.value, 0) + 1

    # Ordre important : les bénéficiaires d'abord, pour qu'une visite créée
    # hors ligne avec son bénéficiaire trouve celui-ci déjà en place.
    for beneficiary in payload.beneficiaries:
        _count(_upsert_beneficiary(db, agent, beneficiary, now))
    for visit in payload.visits:
        _count(_upsert_visit(db, agent, visit, now))
    for referral in payload.gbv_referrals:
        _count(_upsert_referral(db, agent, referral, now))
    db.commit()
    if skipped:
        logger.warning("agent.sync_skipped", agent_id=agent.id, **skipped)

    def _changed[M: (Beneficiary, Visit, GbvReferral)](model: type[M]) -> list[M]:
        query = select(model).where(model.agent_id == agent.id)
        if payload.since is not None:
            # `>=` (et pas `>`) : une écriture concurrente horodatée à la même
            # microseconde que `since` n'est jamais perdue ; renvoyer une fiche
            # déjà connue de l'appareil est, lui, sans conséquence.
            query = query.where(model.synced_at >= payload.since)
        return list(db.scalars(query))

    return SyncResponse(
        server_time=now,
        beneficiaries=[_beneficiary_out(b) for b in _changed(Beneficiary)],
        visits=[_visit_out(v) for v in _changed(Visit)],
        gbv_referrals=[_referral_out(r) for r in _changed(GbvReferral)],
    )


# --- REST classique -----------------------------------------------------------


def _owned_beneficiary(db: Session, agent: User, beneficiary_id: str) -> Beneficiary:
    """404 aussi pour la fiche d'un AUTRE agent : un 403 confirmerait qu'elle
    existe."""
    b = db.get(Beneficiary, beneficiary_id)
    if b is None or b.agent_id != agent.id or b.deleted:
        raise HTTPException(status_code=404, detail="Bénéficiaire introuvable")
    return b


def _raise_for(outcome: Outcome) -> None:
    if outcome is Outcome.FOREIGN:
        raise HTTPException(status_code=409, detail="Identifiant déjà utilisé")
    if outcome is Outcome.ORPHAN:
        raise HTTPException(status_code=422, detail="Bénéficiaire inconnu")
    if outcome is Outcome.STALE:
        raise HTTPException(status_code=409, detail="Une version plus récente existe déjà sur le serveur")


@router.get("/beneficiaries", response_model=list[BeneficiaryOut])
def list_beneficiaries(agent: User = Depends(require_agent), db: Session = Depends(get_db)) -> list[BeneficiaryOut]:
    query = (
        select(Beneficiary)
        .where(Beneficiary.agent_id == agent.id, Beneficiary.deleted.is_(False))
        .order_by(Beneficiary.pseudonym)
    )
    return [_beneficiary_out(b) for b in db.scalars(query)]


@router.post("/beneficiaries", response_model=BeneficiaryOut, status_code=201)
def create_beneficiary(
    payload: BeneficiaryIn, agent: User = Depends(require_agent), db: Session = Depends(get_db)
) -> BeneficiaryOut:
    if db.get(Beneficiary, payload.id) is not None:
        raise HTTPException(status_code=409, detail="Identifiant déjà utilisé")
    _raise_for(_upsert_beneficiary(db, agent, payload, utc_now()))
    db.commit()
    return _beneficiary_out(_owned_beneficiary(db, agent, payload.id))


@router.get("/beneficiaries/{beneficiary_id}", response_model=BeneficiaryOut)
def get_beneficiary(
    beneficiary_id: str, agent: User = Depends(require_agent), db: Session = Depends(get_db)
) -> BeneficiaryOut:
    return _beneficiary_out(_owned_beneficiary(db, agent, beneficiary_id))


@router.put("/beneficiaries/{beneficiary_id}", response_model=BeneficiaryOut)
def update_beneficiary(
    beneficiary_id: str,
    payload: BeneficiaryIn,
    agent: User = Depends(require_agent),
    db: Session = Depends(get_db),
) -> BeneficiaryOut:
    if payload.id != beneficiary_id.lower():
        raise HTTPException(status_code=422, detail="L'identifiant du corps ne correspond pas à celui de l'URL")
    _owned_beneficiary(db, agent, beneficiary_id)
    _raise_for(_upsert_beneficiary(db, agent, payload, utc_now()))
    db.commit()
    b = db.get(Beneficiary, payload.id)
    assert b is not None
    return _beneficiary_out(b)


@router.delete("/beneficiaries/{beneficiary_id}", status_code=204)
def delete_beneficiary(
    beneficiary_id: str, agent: User = Depends(require_agent), db: Session = Depends(get_db)
) -> Response:
    """Suppression LOGIQUE (fiche et visites) : elle doit se propager aux
    autres appareils de l'agent à leur prochaine synchronisation."""
    b = _owned_beneficiary(db, agent, beneficiary_id)
    now = utc_now()
    b.deleted = True
    b.updated_at = now
    b.synced_at = now
    for visit in b.visits:
        if not visit.deleted:
            visit.deleted = True
            visit.updated_at = now
            visit.synced_at = now
    db.commit()
    return Response(status_code=204)


@router.get("/visits", response_model=list[VisitOut])
def list_visits(
    beneficiary_id: str | None = None, agent: User = Depends(require_agent), db: Session = Depends(get_db)
) -> list[VisitOut]:
    query = select(Visit).where(Visit.agent_id == agent.id, Visit.deleted.is_(False))
    if beneficiary_id:
        query = query.where(Visit.beneficiary_id == beneficiary_id.lower())
    return [_visit_out(v) for v in db.scalars(query.order_by(Visit.visit_date.desc()))]


@router.post("/visits", response_model=VisitOut, status_code=201)
def create_visit(payload: VisitIn, agent: User = Depends(require_agent), db: Session = Depends(get_db)) -> VisitOut:
    if db.get(Visit, payload.id) is not None:
        raise HTTPException(status_code=409, detail="Identifiant déjà utilisé")
    _raise_for(_upsert_visit(db, agent, payload, utc_now()))
    db.commit()
    visit = db.get(Visit, payload.id)
    assert visit is not None
    return _visit_out(visit)


@router.post("/gbv-referrals", response_model=GbvReferralOut, status_code=201)
def create_gbv_referral(
    payload: GbvReferralIn, agent: User = Depends(require_agent), db: Session = Depends(get_db)
) -> GbvReferralOut:
    if db.get(GbvReferral, payload.id) is not None:
        raise HTTPException(status_code=409, detail="Identifiant déjà utilisé")
    _raise_for(_upsert_referral(db, agent, payload, utc_now()))
    db.commit()
    referral = db.get(GbvReferral, payload.id)
    assert referral is not None
    return _referral_out(referral)


@router.get("/summary", response_model=AgentSummary)
def summary(agent: User = Depends(require_agent), db: Session = Depends(get_db)) -> AgentSummary:
    """Tableau de bord de l'agent sur les 30 derniers jours.

    - `referrals_last_30_days` : visites avec orientation (`referred`) +
      orientations VBG ;
    - `danger_signs_last_30_days` : visites où au moins un signe de danger a
      été constaté.
    """
    since = (utc_now() - timedelta(days=30)).date()
    active_beneficiaries = select(Beneficiary).where(Beneficiary.agent_id == agent.id, Beneficiary.deleted.is_(False))
    recent_visits = list(
        db.scalars(select(Visit).where(Visit.agent_id == agent.id, Visit.deleted.is_(False), Visit.visit_date >= since))
    )
    gbv_recent = db.scalar(
        select(func.count())
        .select_from(GbvReferral)
        .where(GbvReferral.agent_id == agent.id, GbvReferral.referral_date >= since)
    )
    beneficiaries = list(db.scalars(active_beneficiaries))
    return AgentSummary(
        beneficiaries=len(beneficiaries),
        pregnant=sum(1 for b in beneficiaries if b.pregnant),
        visits_last_30_days=len(recent_visits),
        referrals_last_30_days=sum(1 for v in recent_visits if v.referred) + (gbv_recent or 0),
        danger_signs_last_30_days=sum(1 for v in recent_visits if v.danger_sign_ids),
    )
