"""Schémas de l'espace agent (module 4) : bénéficiaires, visites,
orientations VBG et synchronisation hors ligne."""

from datetime import date
from typing import Literal

from pydantic import BaseModel, Field

from app.schemas.common import Timestamp, UuidStr

AgeRange = Literal["<15", "15-19", "20-24", "25-34", "35-49", "50+"]
VisitType = Literal["prenatal", "postnatal", "child", "family_planning", "follow_up", "other"]
# Motif du prochain rendez-vous : alimente la liste « Rappels à faire » de
# l'agent (femmes sans smartphone).
AppointmentReason = Literal["prenatal", "postnatal", "vaccine", "family_planning", "follow_up", "other"]
GbvCategory = Literal["physical", "sexual", "psychological", "economic", "early_marriage", "fgm", "other"]

# Garde-fou contre une synchronisation démesurée (un appareil resté hors
# ligne longtemps reste largement en dessous).
MAX_SYNC_ITEMS = 2000


class BeneficiaryIn(BaseModel):
    id: UuidStr
    pseudonym: str = Field(min_length=1, max_length=120)
    village: str | None = Field(default=None, max_length=120)
    age_range: AgeRange
    pregnant: bool = False
    expected_due_date: date | None = None
    children_under_5: int = Field(default=0, ge=0, le=30)
    # Prochain rendez-vous. Le numéro de téléphone de la femme, si l'agent en
    # note un, reste sur son appareil : il n'a AUCUN champ ici.
    next_appointment_date: date | None = None
    next_appointment_reason: AppointmentReason | None = None
    # OBLIGATOIRE : une fiche sans consentement est refusée (422).
    consent_given_at: Timestamp
    notes: str | None = Field(default=None, max_length=5000)
    # Horodatage de l'appareil. Facultatif en REST (le serveur met "maintenant"),
    # arbitre du dernier-écrit-gagne en synchronisation.
    updated_at: Timestamp | None = None
    deleted: bool = False


class BeneficiaryOut(BaseModel):
    id: str
    pseudonym: str
    village: str | None
    age_range: str
    pregnant: bool
    expected_due_date: date | None
    children_under_5: int
    next_appointment_date: date | None
    next_appointment_reason: str | None
    consent_given_at: Timestamp
    notes: str | None
    updated_at: Timestamp
    deleted: bool


class VisitIn(BaseModel):
    id: UuidStr
    beneficiary_id: UuidStr
    visit_date: date
    type: VisitType
    danger_sign_ids: list[UuidStr] = Field(default_factory=list, max_length=50)
    referred: bool = False
    referred_to: str | None = Field(default=None, max_length=300)
    notes: str | None = Field(default=None, max_length=5000)
    updated_at: Timestamp | None = None
    deleted: bool = False


class VisitOut(BaseModel):
    id: str
    beneficiary_id: str
    visit_date: date
    type: str
    danger_sign_ids: list[str]
    referred: bool
    referred_to: str | None
    notes: str | None
    updated_at: Timestamp
    deleted: bool


class GbvReferralIn(BaseModel):
    """Volontairement SANS nom ni identifiant de bénéficiaire : un champ de ce
    genre envoyé par erreur est ignoré (et la table n'a de toute façon aucune
    colonne pour le recevoir)."""

    id: UuidStr
    referral_date: date
    service_id: UuidStr | None = None
    category: GbvCategory
    updated_at: Timestamp | None = None


class GbvReferralOut(BaseModel):
    id: str
    referral_date: date
    service_id: str | None
    category: str
    updated_at: Timestamp


class SyncRequest(BaseModel):
    since: Timestamp | None = None
    beneficiaries: list[BeneficiaryIn] = Field(default_factory=list, max_length=MAX_SYNC_ITEMS)
    visits: list[VisitIn] = Field(default_factory=list, max_length=MAX_SYNC_ITEMS)
    gbv_referrals: list[GbvReferralIn] = Field(default_factory=list, max_length=MAX_SYNC_ITEMS)


class SyncResponse(BaseModel):
    server_time: Timestamp
    beneficiaries: list[BeneficiaryOut]
    visits: list[VisitOut]
    gbv_referrals: list[GbvReferralOut]


class AgentSummary(BaseModel):
    beneficiaries: int
    pregnant: int
    visits_last_30_days: int
    referrals_last_30_days: int
    danger_signs_last_30_days: int
