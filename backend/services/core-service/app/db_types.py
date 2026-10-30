"""
Types de colonnes personnalisés.

`UtcDateTime` : toutes les dates-heures du service sont en UTC, et doivent
le rester une fois relues. Or SQLite ne mémorise pas le fuseau horaire : une
valeur écrite "aware" (avec fuseau) revient "naïve" (sans fuseau). Comparer
ensuite une date relue à une date reçue d'un client (ex: le `updated_at` de
la synchronisation hors ligne, dernier-écrit-gagne) lèverait un TypeError —
ou pire, serait faux de plusieurs heures si on retirait le fuseau du mauvais
côté. Ce type garantit que Python voit TOUJOURS une date UTC "aware", quelle
que soit la base (SQLite en dev, PostgreSQL en production).
"""

from datetime import UTC, datetime
from typing import Any

from sqlalchemy import DateTime
from sqlalchemy.engine import Dialect
from sqlalchemy.types import TypeDecorator


class UtcDateTime(TypeDecorator[datetime]):
    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value: datetime | None, dialect: Dialect) -> Any:
        if value is None:
            return None
        aware = value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)
        # SQLite : on stocke l'heure UTC "nue" (il ignorerait le fuseau de
        # toute façon) ; PostgreSQL (timestamptz) : on garde le fuseau.
        return aware.replace(tzinfo=None) if dialect.name == "sqlite" else aware

    def process_result_value(self, value: datetime | None, dialect: Dialect) -> datetime | None:
        if value is None:
            return None
        return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def utc_now() -> datetime:
    return datetime.now(UTC)
