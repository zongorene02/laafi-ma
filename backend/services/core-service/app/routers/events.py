"""
Statistiques anonymes : collecte d'événements et statistiques publiques.

Collecte (`POST /events`) — envoyée par l'app SEULEMENT si la femme a accepté
les statistiques anonymes. Chaque événement n'incrémente qu'un COMPTEUR
journalier (jour, type, langue, district) : aucune ligne par événement,
aucun identifiant de compte ou d'appareil, aucune adresse IP, aucune heure,
aucun texte libre (règle de confidentialité n°2).

Publication (`GET /public/stats`) — toute cellule dont le compte est
inférieur à `PUBLIC_STATS_MIN_COUNT` est supprimée (règle n°3) : dans un
petit district, "2 appels au numéro VBG cette semaine" peut suffire à
désigner une personne. Les événements sensibles (`help_*`,
`danger_flagged`) ne sont JAMAIS ventilés par district ni par semaine,
seulement par mois et par région.

`agent_activity` (activité des agents de santé communautaires) ne vient pas
des événements des femmes mais des fiches des agents (visites, orientations
VBG), agrégées par mois et par RÉGION du district de l'agent — jamais par
agent ni par district —, avec la même suppression des petites cellules.
"""

from collections import Counter
from collections.abc import Callable
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.config import settings
from app.db import get_db
from app.db_models import District, EventCount, GbvReferral, User, Visit
from app.db_types import utc_now
from app.limiter import limiter
from app.schemas.misc import (
    SENSITIVE_EVENT_TYPES,
    AgentActivityCount,
    DistrictCount,
    EventsAccepted,
    EventsRequest,
    LangCount,
    MonthCount,
    PublicStatsResponse,
    RegionCount,
    StatsPeriod,
    TypeCount,
    WeekCount,
)

router = APIRouter(tags=["Statistiques anonymes"])

DEFAULT_PERIOD_DAYS = 90


@router.post("/events", response_model=EventsAccepted, status_code=202)
@limiter.limit("30/minute")
def collect_events(request: Request, payload: EventsRequest, db: Session = Depends(get_db)) -> EventsAccepted:
    today = utc_now().date()
    for event in payload.events:
        # Une date dans le futur (au-delà du décalage horaire) est forcément
        # fausse : on refuse plutôt que de fausser les statistiques.
        if event.occurred_on > today + timedelta(days=1):
            raise HTTPException(status_code=422, detail="occurred_on ne peut pas être dans le futur")

    known_districts = set(db.scalars(select(District.id)))
    cells: Counter[tuple[date, str, str, str]] = Counter()
    for event in payload.events:
        district_id = event.district_id if event.district_id in known_districts else ""
        cells[(event.occurred_on, event.type, event.lang, district_id or "")] += 1

    for (occurred_on, event_type, lang, district_id), count in cells.items():
        _increment(db, occurred_on, event_type, lang, district_id, count)
    return EventsAccepted(accepted=len(payload.events))


def _increment(db: Session, occurred_on: date, event_type: str, lang: str, district_id: str, count: int) -> None:
    """Ajoute `count` à une cellule (créée si besoin), validé immédiatement.

    Deux envois simultanés peuvent créer la même cellule en même temps : la
    contrainte d'unicité départage, et le perdant se rabat sur la mise à jour
    de la cellule créée par l'autre. Une validation par cellule (au plus 100
    par envoi) évite les points de sauvegarde (SAVEPOINT), mal gérés par le
    pilote SQLite de Python."""

    def _find() -> EventCount | None:
        return db.scalar(
            select(EventCount).where(
                EventCount.occurred_on == occurred_on,
                EventCount.type == event_type,
                EventCount.lang == lang,
                EventCount.district_id == district_id,
            )
        )

    cell = _find()
    if cell is None:
        db.add(EventCount(occurred_on=occurred_on, type=event_type, lang=lang, district_id=district_id, count=count))
        try:
            db.commit()
            return
        except IntegrityError:
            db.rollback()
            cell = _find()
            if cell is None:
                raise
    cell.count += count
    db.commit()


def _agent_activity(db: Session, start: date, end: date) -> Counter[tuple[str, ...]]:
    """Compteurs (mois, région, type) de l'activité des agents sur la période.

    - `agent_visits` : visites non supprimées (`visit_date`) ;
    - `danger_referrals` : parmi elles, celles orientées POUR UN SIGNE DE
      DANGER (`referred` ET au moins un `danger_sign_ids`) — une orientation
      sans signe de danger constaté n'y est pas comptée ;
    - `gbv_referrals` : orientations VBG (`referral_date`) ;
    - `agents_active` : agents DISTINCTS ayant au moins une visite ou une
      orientation VBG dans le mois.

    Un agent sans district (donc sans région) est ignoré : il n'a pas de
    case où être compté."""
    region_of_agent: dict[str, str] = {
        agent_id: region
        for agent_id, region in db.execute(
            select(User.id, District.region).join(District, User.district_id == District.id)
        )
    }
    cells: Counter[tuple[str, ...]] = Counter()
    active: set[tuple[str, str, str]] = set()  # (mois, région, agent)

    def _count(agent_id: str, day: date, activity_type: str) -> str | None:
        region = region_of_agent.get(agent_id)
        if region is None:
            return None
        month = day.strftime("%Y-%m")
        cells[(month, region, activity_type)] += 1
        active.add((month, region, agent_id))
        return month

    visits = db.execute(
        select(Visit.agent_id, Visit.visit_date, Visit.referred, Visit.danger_sign_ids).where(
            Visit.deleted.is_(False), Visit.visit_date >= start, Visit.visit_date <= end
        )
    )
    for agent_id, visit_date, referred, danger_sign_ids in visits:
        month = _count(agent_id, visit_date, "agent_visits")
        if month is not None and referred and danger_sign_ids:
            cells[(month, region_of_agent[agent_id], "danger_referrals")] += 1

    referrals = db.execute(
        select(GbvReferral.agent_id, GbvReferral.referral_date).where(
            GbvReferral.referral_date >= start, GbvReferral.referral_date <= end
        )
    )
    for agent_id, referral_date in referrals:
        _count(agent_id, referral_date, "gbv_referrals")

    for month, region, _agent_id in active:
        cells[(month, region, "agents_active")] += 1
    return cells


def _iso_week(day: date) -> str:
    year, week, _ = day.isocalendar()
    return f"{year}-W{week:02d}"


@router.get("/public/stats", response_model=PublicStatsResponse)
def public_stats(
    from_: date | None = Query(default=None, alias="from"),
    to: date | None = None,
    db: Session = Depends(get_db),
) -> PublicStatsResponse:
    end = to or utc_now().date()
    start = from_ or end - timedelta(days=DEFAULT_PERIOD_DAYS - 1)
    if start > end:
        raise HTTPException(status_code=422, detail="'from' doit précéder 'to'")

    rows = list(db.scalars(select(EventCount).where(EventCount.occurred_on >= start, EventCount.occurred_on <= end)))
    districts = {d.id: d for d in db.scalars(select(District))}
    min_count = settings.public_stats_min_count
    suppressed = 0

    def _aggregate(key: Callable[[EventCount], tuple[str, ...] | None]) -> list[tuple[tuple[str, ...], int]]:
        """Agrège les compteurs selon `key` (None = ligne exclue de cette
        ventilation), puis supprime les cellules sous le seuil."""
        totals: Counter[tuple[str, ...]] = Counter()
        for row in rows:
            cell = key(row)
            if cell is not None:
                totals[cell] += row.count
        return _suppress(totals)

    def _suppress(totals: Counter[tuple[str, ...]]) -> list[tuple[tuple[str, ...], int]]:
        """Retire (et compte dans `suppressed_cells`) toute cellule sous le
        seuil ; renvoie les autres, triées."""
        nonlocal suppressed
        kept = []
        for cell, count in sorted(totals.items()):
            if count < min_count:
                suppressed += 1
            else:
                kept.append((cell, count))
        return kept

    def _region(row: EventCount) -> str | None:
        district = districts.get(row.district_id)
        return district.region if district is not None else None

    def _district(row: EventCount) -> str | None:
        district = districts.get(row.district_id)
        return district.name if district is not None else None

    totals = _aggregate(lambda r: (r.type,))
    by_week = _aggregate(lambda r: None if r.type in SENSITIVE_EVENT_TYPES else (_iso_week(r.occurred_on), r.type))
    by_month = _aggregate(lambda r: (r.occurred_on.strftime("%Y-%m"), r.type))
    by_lang = _aggregate(lambda r: None if r.type in SENSITIVE_EVENT_TYPES else (r.lang, r.type))
    by_district = _aggregate(
        lambda r: None if r.type in SENSITIVE_EVENT_TYPES or _district(r) is None else (str(_district(r)), r.type)
    )
    by_region = _aggregate(lambda r: None if _region(r) is None else (str(_region(r)), r.type))
    agent_activity = _suppress(_agent_activity(db, start, end))

    return PublicStatsResponse(
        generated_at=utc_now(),
        min_count=min_count,
        period=StatsPeriod(from_=start, to=end),
        totals=[TypeCount(type=c[0], count=n) for c, n in totals],
        by_week=[WeekCount(week=c[0], type=c[1], count=n) for c, n in by_week],
        by_month=[MonthCount(month=c[0], type=c[1], count=n) for c, n in by_month],
        by_lang=[LangCount(lang=c[0], type=c[1], count=n) for c, n in by_lang],
        by_district=[DistrictCount(district=c[0], type=c[1], count=n) for c, n in by_district],
        by_region=[RegionCount(region=c[0], type=c[1], count=n) for c, n in by_region],
        agent_activity=[
            AgentActivityCount(month=c[0], region=c[1], type=c[2], count=n)  # type: ignore[arg-type]
            for c, n in agent_activity
        ],
        suppressed_cells=suppressed,
    )
