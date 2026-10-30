"""Types partagés par tous les schémas de l'API (voir docs/API.md)."""

import uuid
from datetime import UTC, datetime
from typing import Annotated, Literal

from pydantic import AfterValidator, BaseModel, ConfigDict, PlainSerializer


def to_utc(value: datetime) -> datetime:
    """Une date-heure reçue sans fuseau est considérée comme UTC (le contrat
    impose l'UTC partout) ; une date avec fuseau est convertie en UTC."""
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def iso_utc(value: datetime) -> str:
    """ISO 8601 UTC avec le suffixe "Z" (`2026-10-29T10:15:00Z`)."""
    return to_utc(value).isoformat().replace("+00:00", "Z")


# Horodatage ISO 8601 UTC, en entrée comme en sortie.
Timestamp = Annotated[datetime, AfterValidator(to_utc), PlainSerializer(iso_utc, return_type=str)]


def _canonical_uuid(value: str) -> str:
    try:
        return str(uuid.UUID(value))
    except (ValueError, AttributeError, TypeError) as e:
        raise ValueError("Identifiant UUID invalide") from e


# Identifiant UUID transmis comme chaîne, normalisé en minuscules.
UuidStr = Annotated[str, AfterValidator(_canonical_uuid)]

ContentStatus = Literal["draft", "validated", "archived"]
AudioKind = Literal["human", "synthetic"]


class UserRef(BaseModel):
    """Référence courte à un compte du personnel (ex: qui a validé)."""

    id: str
    full_name: str | None

    model_config = ConfigDict(from_attributes=True)
