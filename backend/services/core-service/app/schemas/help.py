"""Schémas de l'annuaire d'aide et de protection (module 3)."""

from datetime import date
from typing import Literal

from pydantic import BaseModel, Field

from app.languages import UserLang

# `emergency` : sapeurs-pompiers / urgences médicales (ex: le 18), appelé par
# le bouton « Appeler les urgences » du bandeau de danger de l'app.
HelpCategory = Literal[
    "hotline", "vbg_center", "police", "gendarmerie", "emergency", "health", "social", "legal", "psychosocial"
]


class HelpServiceIn(BaseModel):
    name: str = Field(min_length=1, max_length=300)
    category: HelpCategory
    phone: str = Field(min_length=1, max_length=50)
    city: str | None = Field(default=None, max_length=120)
    region: str | None = Field(default=None, max_length=120)
    address: str | None = Field(default=None, max_length=1000)
    hours: str | None = Field(default=None, max_length=200)
    free_call: bool = False
    languages: list[UserLang] = Field(default_factory=list)
    source_url: str | None = Field(default=None, max_length=1000)
    active: bool = True


class HelpServiceOut(BaseModel):
    id: str
    name: str
    category: str
    phone: str
    city: str | None
    region: str | None
    address: str | None
    hours: str | None
    free_call: bool
    languages: list[str]
    source_url: str | None
    # null = "pas encore confirmé" : l'app doit l'afficher comme tel.
    verified_at: date | None
    active: bool
