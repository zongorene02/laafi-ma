"""Schémas des districts, des événements anonymes et des statistiques publiques."""

from datetime import date
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.languages import UserLang
from app.schemas.common import Timestamp, UuidStr

# --- Districts ----------------------------------------------------------------


class DistrictIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    region: str = Field(min_length=1, max_length=200)


class DistrictOut(BaseModel):
    id: str
    name: str
    region: str

    model_config = ConfigDict(from_attributes=True)


# --- Événements anonymes ------------------------------------------------------

EventType = Literal[
    "app_opened",
    "question_asked",
    "question_unanswered",
    "danger_flagged",
    "help_opened",
    "help_call",
    "help_alert_sent",
    "directory_viewed",
    "capsule_played",
    "reminder_done",
    "record_backup",
    # Indicateurs du dossier de financement (voir docs/API.md) — aucun n'est
    # sensible : ventilés comme les autres.
    "monthly_active",  # au plus une fois par mois et par appareil (aucun id envoyé)
    "question_voice",  # question posée au micro (en plus de question_asked)
    "answer_understood",  # « Avez-vous compris ? » -> oui
    "answer_not_understood",  # « Avez-vous compris ? » -> non
    "anc_visit_recorded",  # consultation prénatale notée dans son carnet
    "vaccine_recorded",  # vaccin d'un enfant noté dans son carnet
]

# Types jamais ventilés par district ni par semaine (seulement par mois et
# par région) : trop sensibles — un appel au numéro VBG dans un petit district
# une semaine donnée pourrait désigner une personne.
SENSITIVE_EVENT_TYPES = frozenset({"help_opened", "help_call", "help_alert_sent", "danger_flagged"})

MAX_EVENTS_PER_BATCH = 100


class EventIn(BaseModel):
    """Un événement : un type, une langue, éventuellement un district, une
    DATE (jamais d'heure). Tout autre champ envoyé est ignoré."""

    type: EventType
    lang: UserLang
    district_id: UuidStr | None = None
    occurred_on: date


class EventsRequest(BaseModel):
    events: list[EventIn] = Field(max_length=MAX_EVENTS_PER_BATCH)


class EventsAccepted(BaseModel):
    accepted: int


# --- Statistiques publiques ---------------------------------------------------


class StatsPeriod(BaseModel):
    # "from" est un mot réservé Python : attribut `from_`, sérialisé "from".
    from_: date = Field(serialization_alias="from")
    to: date


class TypeCount(BaseModel):
    type: str
    count: int


class WeekCount(TypeCount):
    week: str


class MonthCount(TypeCount):
    month: str


class LangCount(TypeCount):
    lang: str


class DistrictCount(TypeCount):
    district: str


class RegionCount(TypeCount):
    region: str


# Activité des agents, calculée depuis leurs fiches (aucun événement des
# femmes) : agents actifs, visites, visites orientées, orientations VBG.
AgentActivityType = Literal["agents_active", "agent_visits", "danger_referrals", "gbv_referrals"]


class AgentActivityCount(BaseModel):
    month: str
    region: str
    type: AgentActivityType
    count: int


class PublicStatsResponse(BaseModel):
    generated_at: Timestamp
    min_count: int
    period: StatsPeriod
    totals: list[TypeCount]
    by_week: list[WeekCount]
    by_month: list[MonthCount]
    by_lang: list[LangCount]
    by_district: list[DistrictCount]
    by_region: list[RegionCount]
    agent_activity: list[AgentActivityCount]
    suppressed_cells: int
