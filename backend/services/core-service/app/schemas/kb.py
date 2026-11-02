"""Schémas de la base de connaissances, des signes de danger et de l'assistant."""

from typing import Annotated, Literal

from pydantic import BaseModel, Field

from app.languages import UserLang
from app.schemas.common import AudioKind, ContentStatus, Timestamp, UserRef

Topic = Literal[
    "grossesse",
    "post_partum",
    "contraception",
    "menstruation",
    "nutrition",
    "maladies",
    "sante_mentale",
    "violences",
    "enfant",
    "hygiene",
    "autre",
]


# --- Base de connaissances ----------------------------------------------------


class KbTranslationIn(BaseModel):
    question: str = Field(default="", max_length=500)
    # Autres formulations de la même question : elles servent au
    # rapprochement (en français), jamais affichées à l'utilisatrice.
    variants: list[str] = Field(default_factory=list, max_length=50)
    answer: str = Field(default="", max_length=5000)


class KbEntryIn(BaseModel):
    topic: Topic
    is_danger_topic: bool = False
    translations: dict[UserLang, KbTranslationIn] = Field(default_factory=dict)
    source: str | None = Field(default=None, max_length=1000)


class KbTranslationOut(BaseModel):
    question: str
    variants: list[str]
    answer: str
    audio_url: str | None
    audio_kind: AudioKind | None
    machine_translated: bool


class KbEntryOut(BaseModel):
    id: str
    topic: str
    status: ContentStatus
    is_danger_topic: bool
    translations: dict[str, KbTranslationOut]
    source: str | None
    validated_by: UserRef | None
    validated_at: Timestamp | None
    created_at: Timestamp
    updated_at: Timestamp


# --- Signes de danger ---------------------------------------------------------


# Fiche d'aide à la décision de l'agent (module 4) : questions à poser,
# puis quand orienter vers le centre de santé.
AgentQuestion = Annotated[str, Field(min_length=1, max_length=300)]
MAX_AGENT_QUESTIONS = 10


class DangerSignTranslationIn(BaseModel):
    label: str = Field(default="", max_length=300)
    advice: str = Field(default="", max_length=1000)
    agent_questions: list[AgentQuestion] = Field(default_factory=list, max_length=MAX_AGENT_QUESTIONS)
    refer_when: str | None = Field(default=None, max_length=1000)


class DangerSignIn(BaseModel):
    translations: dict[UserLang, DangerSignTranslationIn] = Field(default_factory=dict)
    keywords_fr: list[str] = Field(default_factory=list, max_length=100)
    source: str | None = Field(default=None, max_length=1000)


class DangerSignTranslationOut(BaseModel):
    label: str
    advice: str
    agent_questions: list[str]
    refer_when: str | None


class DangerSignOut(BaseModel):
    id: str
    status: ContentStatus
    translations: dict[str, DangerSignTranslationOut]
    keywords_fr: list[str]
    source: str | None
    validated_by: UserRef | None
    validated_at: Timestamp | None
    created_at: Timestamp
    updated_at: Timestamp


# --- Questions sans réponse ---------------------------------------------------


class UnansweredOut(BaseModel):
    id: str
    text_fr: str
    lang: str
    created_at: Timestamp
    resolved: bool


# --- Assistant (côté app) -----------------------------------------------------


class AskTextRequest(BaseModel):
    text: str = Field(min_length=1, max_length=1000)
    lang: UserLang


class AssistantEntry(BaseModel):
    id: str
    topic: str
    question: str
    answer: str
    audio_url: str | None
    audio_kind: AudioKind | None
    # True seulement pour le contenu `sourced` : l'app dit alors qu'aucune
    # sage-femme ne l'a relu (voir docs/API.md).
    provisional: bool
    source: str | None


class DangerSignBrief(BaseModel):
    id: str
    label: str
    advice: str
    provisional: bool
    source: str | None


class AskResponse(BaseModel):
    transcript: str | None
    question_fr: str | None
    matched: bool
    confidence: float
    entry: AssistantEntry | None
    danger: bool
    danger_signs: list[DangerSignBrief]
    fallback_message: str | None


class TranscribeResponse(BaseModel):
    """Transcription seule (`POST /assistant/transcribe`) : l'app la montre
    pour confirmation, ou la compare SUR L'APPAREIL à la phrase d'aide
    secrète. `question_fr` vaut null quand la langue est le français."""

    transcript: str
    question_fr: str | None


class FaqEntry(AssistantEntry):
    is_danger_topic: bool


class FaqResponse(BaseModel):
    version: str
    entries: list[FaqEntry]


class DangerSignPublic(DangerSignBrief):
    keywords: list[str]
    agent_questions: list[str]
    refer_when: str | None
