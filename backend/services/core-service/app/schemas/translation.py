"""Schémas de la traduction pour les agents (repris de Trad IA)."""

from typing import Literal, get_args

from pydantic import BaseModel, Field

# "verified" : moteur de référence (NLLB + adaptateur Mooré), dont les
# traductions Mooré ont été relues par un locuteur natif. Lent.
# "fast" : moteur quantifié CTranslate2, 7 à 20 fois plus rapide, pas encore
# relu. Choix explicite de l'appelant, jamais imposé.
TranslationMode = Literal["verified", "fast"]
TRANSLATION_MODES: tuple[str, ...] = get_args(TranslationMode)


class TranslateRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    source_lang: str  # "fr", "mos", "dyu"
    target_lang: str
    mode: TranslationMode = "verified"


class TranslateResponse(BaseModel):
    translation: str
    source_lang: str
    target_lang: str
    # Rendu dans la réponse pour qu'un client ne puisse jamais confondre une
    # traduction rapide avec une traduction vérifiée.
    mode: str = "verified"


class TranscribeResponse(BaseModel):
    text: str


class SpeakRequest(BaseModel):
    text: str = Field(min_length=1, max_length=2000)
    language: str
