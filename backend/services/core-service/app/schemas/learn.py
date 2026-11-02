"""Schémas des capsules d'apprentissage (module 5)."""

from typing import Literal, Self

from pydantic import BaseModel, Field, model_validator

from app.languages import UserLang
from app.schemas.common import AudioKind, ContentStatus, Timestamp, UserRef

Track = Literal["adolescente", "future_mere", "jeune_mere", "hommes_familles", "droits", "bien_etre", "general"]


class CapsuleTranslationIn(BaseModel):
    title: str = Field(default="", max_length=300)
    text: str = Field(default="", max_length=20000)


class QuizQuestion(BaseModel):
    question: dict[UserLang, str]
    choices: list[dict[UserLang, str]] = Field(min_length=2, max_length=10)
    correct_index: int = Field(ge=0)

    @model_validator(mode="after")
    def _correct_index_in_range(self) -> Self:
        if self.correct_index >= len(self.choices):
            raise ValueError("correct_index doit désigner l'un des choix proposés")
        return self


class CapsuleIn(BaseModel):
    track: Track
    order: int = 0
    translations: dict[UserLang, CapsuleTranslationIn] = Field(default_factory=dict)
    quiz: list[QuizQuestion] = Field(default_factory=list, max_length=50)
    license: str = Field(default="CC-BY-4.0", max_length=40)


class CapsuleTranslationOut(BaseModel):
    title: str
    text: str
    audio_url: str | None
    audio_kind: AudioKind | None


class CapsuleOut(BaseModel):
    id: str
    track: str
    status: ContentStatus
    order: int
    translations: dict[str, CapsuleTranslationOut]
    quiz: list[QuizQuestion]
    license: str
    # True seulement pour le contenu `sourced`. Pas de `source` ici : la table
    # des capsules n'a pas cette colonne, la source est citée dans le texte.
    provisional: bool
    validated_by: UserRef | None
    validated_at: Timestamp | None
    created_at: Timestamp
    updated_at: Timestamp
