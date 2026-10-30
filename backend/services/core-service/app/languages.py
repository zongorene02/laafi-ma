"""
Langues de Laafi Ma.

Deux niveaux distincts :

- `USER_LANGUAGES` : les seules langues proposées aux utilisatrices et aux
  agents — français, mooré, dioula.
- `NLLB_CODES` : les codes exacts attendus par NLLB-200 (format
  "code_Script", ex. "fra_Latn"). L'anglais y figure UNIQUEMENT comme langue
  pivot interne (voir translation_service.py : l'adaptateur Mooré n'a été
  entraîné que sur des paires anglais-mooré) ; il n'est jamais proposé ni
  accepté en entrée d'un endpoint.
"""

from typing import Literal

# Code -> nom affiché (ordre conservé dans GET /languages)
USER_LANGUAGES: dict[str, str] = {
    "fr": "Français",
    "mos": "Mooré",
    "dyu": "Dioula",
}

# Type réutilisé par les schémas Pydantic : une langue hors liste est
# refusée par la validation (422) avant même d'atteindre notre code.
UserLang = Literal["fr", "mos", "dyu"]

PIVOT_LANG = "en"

NLLB_CODES: dict[str, str] = {
    "fr": "fra_Latn",
    "mos": "mos_Latn",  # Mooré
    "dyu": "dyu_Latn",  # Dioula
    PIVOT_LANG: "eng_Latn",  # pivot interne uniquement
}

# Alias conservé pour le code de traduction hérité de Trad IA.
SUPPORTED_LANGUAGES = NLLB_CODES


def is_user_language(code: str) -> bool:
    return code in USER_LANGUAGES


def to_nllb_code(simple_code: str) -> str:
    """Convertit un code simple ('fr') en code NLLB ('fra_Latn').

    Lève une ValueError explicite si la langue n'est pas supportée, plutôt
    que de laisser une KeyError peu claire remonter jusqu'à l'utilisateur.
    """
    try:
        return NLLB_CODES[simple_code]
    except KeyError as e:
        raise ValueError(
            f"Langue non supportée : '{simple_code}'. Langues disponibles : {sorted(USER_LANGUAGES)}"
        ) from e
