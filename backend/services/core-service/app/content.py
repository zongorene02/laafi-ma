"""
Contenus de santé : conversion ORM -> réponses de l'API et règles du circuit
de validation, partagées par les routeurs kb, assistant et learn.

Circuit de validation (docs/API.md) : `draft` -> `sourced` (seed seulement) ->
`validated` -> `archived`. TOUTE modification d'un contenu le renvoie en
`draft` (et efface qui l'a validé) : une réponse de santé modifiée n'est plus
celle qu'une sage-femme a relue, ni celle de la source citée, elle doit donc
être relue à nouveau avant d'être servie.
"""

from datetime import datetime
from typing import Any

from app.audio_store import audio_for, media_url
from app.config import settings
from app.db_models import STATUS_DRAFT, STATUS_SOURCED, STATUS_VALIDATED, Capsule, DangerSign, KbEntry, User
from app.db_types import utc_now
from app.languages import USER_LANGUAGES
from app.schemas.common import UserRef
from app.schemas.kb import (
    DangerSignOut,
    DangerSignTranslationOut,
    KbEntryOut,
    KbTranslationOut,
)
from app.schemas.learn import CapsuleOut, CapsuleTranslationOut, QuizQuestion

LANGS: tuple[str, ...] = tuple(USER_LANGUAGES)


def user_ref(user: User | None) -> UserRef | None:
    return UserRef(id=user.id, full_name=user.full_name) if user is not None else None


def served_statuses() -> tuple[str, ...]:
    """Statuts servis au public : la SEULE définition de cette règle, utilisée
    par l'assistant, la FAQ, les signes de danger, les capsules et la synthèse
    vocale. `sourced` n'en fait partie que si SERVE_SOURCED_CONTENT=true."""
    if settings.serve_sourced_content:
        return (STATUS_VALIDATED, STATUS_SOURCED)
    return (STATUS_VALIDATED,)


def is_served(item: KbEntry | DangerSign | Capsule) -> bool:
    return item.status in served_statuses()


def is_provisional(item: KbEntry | DangerSign | Capsule) -> bool:
    """Contenu servi sans relecture par une sage-femme : l'app doit le dire."""
    return item.status == STATUS_SOURCED


def mark_edited(item: KbEntry | DangerSign | Capsule, now: datetime | None = None) -> None:
    """Applique la règle "toute modification renvoie en brouillon"."""
    item.status = STATUS_DRAFT
    item.validated_by_id = None
    item.validated_by = None
    item.validated_at = None
    item.updated_at = now or utc_now()


def translation_of(item: KbEntry | DangerSign | Capsule, lang: str) -> dict[str, Any]:
    value = (item.translations or {}).get(lang)
    return dict(value) if isinstance(value, dict) else {}


# --- Base de connaissances ----------------------------------------------------


def kb_has_text(entry: KbEntry, lang: str) -> bool:
    t = translation_of(entry, lang)
    return bool(str(t.get("question", "")).strip()) and bool(str(t.get("answer", "")).strip())


def kb_serving_lang(entry: KbEntry, lang: str) -> str:
    """Langue réellement servie : celle demandée si l'entrée servie a un
    texte dans cette langue, sinon le français (toujours présent sur une
    entrée servie). On ne sert JAMAIS une traduction automatique à la volée,
    qui n'aurait été relue par personne."""
    return lang if kb_has_text(entry, lang) else "fr"


def kb_entry_out(entry: KbEntry) -> KbEntryOut:
    """Vue complète pour la console (validateurs/admins). L'audio indiqué est
    l'enregistrement HUMAIN s'il existe ; la synthèse n'est produite que pour
    les contenus servis (voir audio_store et routers/meta.py)."""
    translations: dict[str, KbTranslationOut] = {}
    for lang in LANGS:
        t = translation_of(entry, lang)
        audio_file = t.get("audio_file")
        translations[lang] = KbTranslationOut(
            question=str(t.get("question", "")),
            variants=[str(v) for v in t.get("variants", [])],
            answer=str(t.get("answer", "")),
            audio_url=media_url(audio_file) if audio_file else None,
            audio_kind="human" if audio_file else None,
            machine_translated=bool(t.get("machine_translated", False)),
        )
    return KbEntryOut(
        id=entry.id,
        topic=entry.topic,
        status=entry.status,  # type: ignore[arg-type]
        is_danger_topic=entry.is_danger_topic,
        translations=translations,
        source=entry.source,
        validated_by=user_ref(entry.validated_by),
        validated_at=entry.validated_at,
        created_at=entry.created_at,
        updated_at=entry.updated_at,
    )


def kb_served_audio(entry: KbEntry, lang: str) -> tuple[str | None, str | None]:
    t = translation_of(entry, lang)
    return audio_for("kb", entry.id, lang, t, str(t.get("answer", "")))


# --- Signes de danger ---------------------------------------------------------


def danger_sign_translation(sign: DangerSign, lang: str) -> dict[str, Any]:
    """Traduction d'un signe de danger sous sa forme COMPLÈTE (libellé,
    conseil, fiche d'aide de l'agent), ou {} si la langue est absente.

    Les lignes écrites avant l'ajout de la fiche d'aide n'ont pas les clés
    `agent_questions` / `refer_when` dans leur JSON : elles reçoivent leurs
    valeurs par défaut ici, ce qui évite toute migration de données — et
    évite qu'un simple réenregistrement sans changement ne les renvoie en
    brouillon."""
    t = translation_of(sign, lang)
    if not t:
        return {}
    refer_when = t.get("refer_when")
    return {
        "label": str(t.get("label", "")),
        "advice": str(t.get("advice", "")),
        "agent_questions": [str(q) for q in t.get("agent_questions") or []],
        "refer_when": str(refer_when) if refer_when else None,
    }


def danger_sign_out(sign: DangerSign) -> DangerSignOut:
    translations: dict[str, DangerSignTranslationOut] = {}
    for lang in LANGS:
        t = danger_sign_translation(sign, lang)
        translations[lang] = DangerSignTranslationOut(
            label=t.get("label", ""),
            advice=t.get("advice", ""),
            agent_questions=t.get("agent_questions", []),
            refer_when=t.get("refer_when"),
        )
    return DangerSignOut(
        id=sign.id,
        status=sign.status,  # type: ignore[arg-type]
        translations=translations,
        keywords_fr=list(sign.keywords_fr or []),
        source=sign.source,
        validated_by=user_ref(sign.validated_by),
        validated_at=sign.validated_at,
        created_at=sign.created_at,
        updated_at=sign.updated_at,
    )


def danger_sign_text(sign: DangerSign, lang: str) -> tuple[str, str]:
    """(libellé, conseil) dans la langue demandée, sinon en français —
    champ par champ, comme `danger_sign_aid` : un libellé mooré sans conseil
    garde le conseil français plutôt que rien."""
    asked = translation_of(sign, lang)
    fr = translation_of(sign, "fr")
    label = str(asked.get("label", "")).strip() or str(fr.get("label", ""))
    advice = str(asked.get("advice", "")).strip() or str(fr.get("advice", ""))
    return label, advice


def danger_sign_aid(sign: DangerSign, lang: str) -> tuple[list[str], str | None]:
    """(questions à poser, quand orienter) de la fiche d'aide de l'agent,
    dans la langue demandée, sinon en français — champ par champ : une
    fiche mooré qui n'a encore que ses questions garde le « quand orienter »
    français plutôt que rien."""
    asked = danger_sign_translation(sign, lang)
    fr = danger_sign_translation(sign, "fr")
    questions = asked.get("agent_questions") or fr.get("agent_questions") or []
    refer_when = asked.get("refer_when") or fr.get("refer_when")
    return list(questions), refer_when


# --- Capsules -----------------------------------------------------------------


def capsule_has_text(capsule: Capsule, lang: str) -> bool:
    t = translation_of(capsule, lang)
    return bool(str(t.get("title", "")).strip()) and bool(str(t.get("text", "")).strip())


def capsule_out(capsule: Capsule, *, served: bool) -> CapsuleOut:
    """`served=True` : vue publique d'une capsule servie — l'audio d'une
    langue sans enregistrement humain pointe vers la synthèse (générée à la
    première lecture). `served=False` : vue console, enregistrement humain
    uniquement."""
    translations: dict[str, CapsuleTranslationOut] = {}
    for lang in LANGS:
        t = translation_of(capsule, lang)
        text = str(t.get("text", ""))
        if served:
            audio_url, audio_kind = audio_for("capsules", capsule.id, lang, t, text)
        else:
            audio_file = t.get("audio_file")
            audio_url, audio_kind = (media_url(audio_file), "human") if audio_file else (None, None)
        translations[lang] = CapsuleTranslationOut(
            title=str(t.get("title", "")),
            text=text,
            audio_url=audio_url,
            audio_kind=audio_kind,  # type: ignore[arg-type]
        )
    return CapsuleOut(
        id=capsule.id,
        track=capsule.track,
        status=capsule.status,  # type: ignore[arg-type]
        order=capsule.order,
        translations=translations,
        quiz=[QuizQuestion.model_validate(q) for q in capsule.quiz or []],
        license=capsule.license,
        provisional=is_provisional(capsule),
        validated_by=user_ref(capsule.validated_by),
        validated_at=capsule.validated_at,
        created_at=capsule.created_at,
        updated_at=capsule.updated_at,
    )
