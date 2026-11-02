"""
Tables de la base de données (SQLAlchemy ORM). Nommé "db_models.py" (pas
"models.py") pour ne pas entrer en collision avec le dossier `models/` qui
contient les poids des modèles d'IA — deux sens différents du mot "modèle".

Style SQLAlchemy 2.0 (`Mapped[T]` + `mapped_column()`) : chaque colonne porte
son vrai type Python, visible par mypy.

Règles de confidentialité portées par le schéma lui-même (voir docs/API.md) :

- une femme n'a ni nom, ni téléphone, ni email : seul un code de récupération
  HACHÉ relie son appareil à son compte ;
- son carnet de santé n'existe ici que sous forme de blob chiffré opaque
  (`RecordBackup`), jamais en clair ;
- les orientations VBG (`GbvReferral`) n'ont AUCUNE colonne pour un nom ou un
  identifiant de bénéficiaire — impossible de les stocker par erreur ;
- les statistiques (`EventCount`) sont des COMPTEURS agrégés par jour : ni
  identifiant, ni heure, ni texte libre, pas même une ligne par événement.

Les textes multilingues (fr/mos/dyu) sont stockés en JSON : une langue de
plus ne demande aucune migration, et une entrée se lit d'un bloc.
"""

import uuid
from datetime import date, datetime
from typing import Any

from sqlalchemy import JSON, Boolean, Date, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base
from app.db_types import UtcDateTime, utc_now

ROLE_WOMAN = "woman"
ROLE_AGENT = "agent"
ROLE_VALIDATOR = "validator"
ROLE_ADMIN = "admin"
STAFF_ROLES = (ROLE_AGENT, ROLE_VALIDATOR, ROLE_ADMIN)

STATUS_DRAFT = "draft"
# Tiré d'une source publique citée (OMS, UNFPA), relu par AUCUNE sage-femme :
# créé seulement par `python -m app.seed`, servi seulement si
# SERVE_SOURCED_CONTENT=true (voir docs/API.md et app/content.py).
STATUS_SOURCED = "sourced"
STATUS_VALIDATED = "validated"
STATUS_ARCHIVED = "archived"


def _new_uuid() -> str:
    return str(uuid.uuid4())


class District(Base):
    __tablename__ = "districts"
    __table_args__ = (UniqueConstraint("name", "region", name="uq_districts_name_region"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_uuid)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    region: Mapped[str] = mapped_column(String(200), nullable=False)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False)


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_uuid)
    # "woman" | "agent" | "validator" | "admin"
    role: Mapped[str] = mapped_column(String(20), nullable=False, index=True)

    # Personnel uniquement : un compte "woman" n'a JAMAIS d'email ni de nom.
    email: Mapped[str | None] = mapped_column(String(320), unique=True, index=True, nullable=True)
    hashed_password: Mapped[str | None] = mapped_column(String(100), nullable=True)
    full_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    district_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("districts.id", ondelete="SET NULL"), nullable=True
    )

    # Compte "woman" uniquement : empreinte bcrypt du code de récupération
    # montré une seule fois à la création (voir /auth/device).
    recovery_code_hash: Mapped[str | None] = mapped_column(String(100), nullable=True)

    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False)

    # Suppression du compte = suppression de tout ce qui lui est rattaché
    # (voir DELETE /auth/me). `passive_deletes` : on laisse aussi la base
    # appliquer ses `ON DELETE CASCADE`.
    backup: Mapped["RecordBackup | None"] = relationship(
        back_populates="user", cascade="all, delete-orphan", passive_deletes=True, uselist=False
    )
    beneficiaries: Mapped[list["Beneficiary"]] = relationship(
        back_populates="agent", cascade="all, delete-orphan", passive_deletes=True
    )
    visits: Mapped[list["Visit"]] = relationship(cascade="all, delete-orphan", passive_deletes=True)
    gbv_referrals: Mapped[list["GbvReferral"]] = relationship(cascade="all, delete-orphan", passive_deletes=True)


class KbEntry(Base):
    """Une question/réponse de la base de connaissances de l'assistant."""

    __tablename__ = "kb_entries"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_uuid)
    topic: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    status: Mapped[str] = mapped_column(String(20), default=STATUS_DRAFT, nullable=False, index=True)
    is_danger_topic: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    # {"fr": {"question", "variants", "answer", "audio_file", "machine_translated"}, "mos": {...}, "dyu": {...}}
    translations: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict, nullable=False)
    source: Mapped[str | None] = mapped_column(Text, nullable=True)
    validated_by_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    validated_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    # Identifiant stable des lignes créées par `python -m app.seed` (voir DangerSign).
    seed_key: Mapped[str | None] = mapped_column(String(80), unique=True, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False)

    validated_by: Mapped[User | None] = relationship()


class DangerSign(Base):
    """Signe de danger (grossesse...) détecté dans les questions posées."""

    __tablename__ = "danger_signs"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_uuid)
    status: Mapped[str] = mapped_column(String(20), default=STATUS_DRAFT, nullable=False, index=True)
    # {"fr": {"label", "advice", "agent_questions", "refer_when"}, "mos": {...}, "dyu": {...}}
    # (les deux dernières clés peuvent manquer sur les lignes anciennes :
    # valeurs par défaut appliquées à la lecture, voir content.py)
    translations: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict, nullable=False)
    keywords_fr: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    source: Mapped[str | None] = mapped_column(Text, nullable=True)
    validated_by_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    validated_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    # Identifiant stable des lignes créées par `python -m app.seed` (rend le
    # seed idempotent même si un validateur a modifié le libellé depuis).
    seed_key: Mapped[str | None] = mapped_column(String(80), unique=True, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False)

    validated_by: Mapped[User | None] = relationship()


class UnansweredQuestion(Base):
    """Question sans réponse validée, gardée pour les validateurs. Anonyme :
    ni compte, ni appareil, ni IP — le texte (en français), la langue et la
    date suffisent à enrichir la base de connaissances."""

    __tablename__ = "unanswered_questions"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_uuid)
    text_fr: Mapped[str] = mapped_column(Text, nullable=False)
    lang: Mapped[str] = mapped_column(String(5), nullable=False)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False)
    resolved: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False, index=True)
    resolved_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)


class RecordBackup(Base):
    """Sauvegarde chiffrée du carnet de santé. Le serveur stocke le blob TEL
    QUEL : la clé est dérivée sur l'appareil d'une phrase secrète que le
    serveur ne voit jamais. Un seul blob par compte."""

    __tablename__ = "record_backups"

    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    ciphertext: Mapped[str] = mapped_column(Text, nullable=False)
    nonce: Mapped[str] = mapped_column(String(200), nullable=False)
    salt: Mapped[str] = mapped_column(String(200), nullable=False)
    kdf: Mapped[str] = mapped_column(String(40), nullable=False)
    kdf_iterations: Mapped[int] = mapped_column(Integer, nullable=False)
    cipher: Mapped[str] = mapped_column(String(40), nullable=False)
    schema_version: Mapped[int] = mapped_column(Integer, nullable=False)
    client_updated_at: Mapped[datetime] = mapped_column(UtcDateTime(), nullable=False)
    size_bytes: Mapped[int] = mapped_column(Integer, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False)

    user: Mapped[User] = relationship(back_populates="backup")


class HelpService(Base):
    """Annuaire d'aide (numéros verts, centres VBG, police...)."""

    __tablename__ = "help_services"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_uuid)
    name: Mapped[str] = mapped_column(String(300), nullable=False)
    category: Mapped[str] = mapped_column(String(30), nullable=False, index=True)
    phone: Mapped[str] = mapped_column(String(50), nullable=False)
    city: Mapped[str | None] = mapped_column(String(120), nullable=True)
    region: Mapped[str | None] = mapped_column(String(120), nullable=True)
    address: Mapped[str | None] = mapped_column(Text, nullable=True)
    hours: Mapped[str | None] = mapped_column(String(200), nullable=True)
    free_call: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    languages: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    source_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    # null = "pas encore confirmé" : l'app doit l'afficher comme tel.
    verified_at: Mapped[date | None] = mapped_column(Date, nullable=True)
    active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    seed_key: Mapped[str | None] = mapped_column(String(80), unique=True, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False)


class Beneficiary(Base):
    """Personne suivie par un agent de santé communautaire. Identifiant créé
    sur l'appareil (UUID v4) pour permettre la saisie hors ligne ; pseudonyme
    seulement, jamais de nom complet exigé."""

    __tablename__ = "beneficiaries"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    agent_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    pseudonym: Mapped[str] = mapped_column(String(120), nullable=False)
    village: Mapped[str | None] = mapped_column(String(120), nullable=True)
    age_range: Mapped[str] = mapped_column(String(10), nullable=False)
    pregnant: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    expected_due_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    children_under_5: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    # Prochain rendez-vous (« Rappels à faire » de l'agent). Pas de numéro de
    # téléphone : il reste sur l'appareil de l'agent.
    next_appointment_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    # "prenatal" | "postnatal" | "vaccine" | "family_planning" | "follow_up" | "other"
    next_appointment_reason: Mapped[str | None] = mapped_column(String(30), nullable=True)
    consent_given_at: Mapped[datetime] = mapped_column(UtcDateTime(), nullable=False)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    # `updated_at` : horodatage de l'APPAREIL, arbitre du dernier-écrit-gagne.
    updated_at: Mapped[datetime] = mapped_column(UtcDateTime(), nullable=False)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    # `synced_at` : horodatage SERVEUR de la dernière écriture acceptée. C'est
    # lui que compare `since` : un appareil resté hors ligne une semaine peut
    # pousser des fiches à `updated_at` ancien, que les autres appareils
    # rateraient si l'on filtrait sur `updated_at`.
    synced_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False, index=True)

    agent: Mapped[User] = relationship(back_populates="beneficiaries")
    visits: Mapped[list["Visit"]] = relationship(
        back_populates="beneficiary", cascade="all, delete-orphan", passive_deletes=True
    )


class Visit(Base):
    __tablename__ = "visits"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    agent_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    beneficiary_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("beneficiaries.id", ondelete="CASCADE"), index=True
    )
    visit_date: Mapped[date] = mapped_column(Date, nullable=False)
    type: Mapped[str] = mapped_column(String(30), nullable=False)
    danger_sign_ids: Mapped[list[str]] = mapped_column(JSON, default=list, nullable=False)
    referred: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    referred_to: Mapped[str | None] = mapped_column(String(300), nullable=True)
    notes: Mapped[str | None] = mapped_column(Text, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(UtcDateTime(), nullable=False)
    deleted: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    synced_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False, index=True)

    beneficiary: Mapped[Beneficiary] = relationship(back_populates="visits")


class GbvReferral(Base):
    """Orientation d'une victime de violence vers un service d'aide. AUCUNE
    colonne de nom ni d'identifiant de bénéficiaire, par construction."""

    __tablename__ = "gbv_referrals"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    agent_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True)
    referral_date: Mapped[date] = mapped_column(Date, nullable=False)
    # Pas de clé étrangère : un service retiré de l'annuaire ne doit pas
    # bloquer la synchronisation d'une orientation faite quand il existait.
    service_id: Mapped[str | None] = mapped_column(String(36), nullable=True)
    category: Mapped[str] = mapped_column(String(30), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(UtcDateTime(), nullable=False)
    synced_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False, index=True)


class Capsule(Base):
    """Capsule d'apprentissage (texte + audio + quiz)."""

    __tablename__ = "capsules"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=_new_uuid)
    track: Mapped[str] = mapped_column(String(30), nullable=False, index=True)
    status: Mapped[str] = mapped_column(String(20), default=STATUS_DRAFT, nullable=False, index=True)
    # "order" est un mot réservé SQL : colonne nommée "sort_order".
    order: Mapped[int] = mapped_column("sort_order", Integer, default=0, nullable=False)
    # {"fr": {"title", "text", "audio_file"}, "mos": {...}, "dyu": {...}}
    translations: Mapped[dict[str, Any]] = mapped_column(JSON, default=dict, nullable=False)
    quiz: Mapped[list[dict[str, Any]]] = mapped_column(JSON, default=list, nullable=False)
    license: Mapped[str] = mapped_column(String(40), default="CC-BY-4.0", nullable=False)
    validated_by_id: Mapped[str | None] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    validated_at: Mapped[datetime | None] = mapped_column(UtcDateTime(), nullable=True)
    # Identifiant stable des lignes créées par `python -m app.seed` (voir DangerSign).
    seed_key: Mapped[str | None] = mapped_column(String(80), unique=True, nullable=True)
    created_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(UtcDateTime(), default=utc_now, nullable=False)

    validated_by: Mapped[User | None] = relationship()


class EventCount(Base):
    """Compteur journalier d'événements anonymes. Une ligne par (jour, type,
    langue, district) — jamais une ligne par événement, si bien qu'il n'existe
    même pas d'ordre d'arrivée qui permettrait de recouper deux événements.

    `district_id` vaut "" (et pas NULL) quand il est inconnu : NULL n'est
    jamais égal à NULL dans une contrainte d'unicité, ce qui créerait des
    doublons de compteurs."""

    __tablename__ = "event_counts"
    __table_args__ = (UniqueConstraint("occurred_on", "type", "lang", "district_id", name="uq_event_counts_cell"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    occurred_on: Mapped[date] = mapped_column(Date, nullable=False, index=True)
    type: Mapped[str] = mapped_column(String(40), nullable=False)
    lang: Mapped[str] = mapped_column(String(5), nullable=False)
    district_id: Mapped[str] = mapped_column(String(36), default="", nullable=False)
    count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
