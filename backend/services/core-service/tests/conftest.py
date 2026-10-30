"""
Configuration partagée des tests (pytest charge automatiquement ce fichier).

Point clé : AUCUN modèle d'IA n'est chargé. Les méthodes `load()`,
`translate()`, `transcribe()`, `synthesize()` des services sont remplacées
par de fausses versions légères AVANT de démarrer l'app de test — sinon
chaque exécution chargerait plusieurs Go (NLLB, Whisper, MMS) sur une
machine qui n'en a pas les moyens. Cette suite teste la LOGIQUE DE L'API
(routage, rôles, confidentialité, circuit de validation, synchronisation),
pas la qualité des modèles (validée à la main, voir scripts/).

Base de test : SQLite EN MÉMOIRE, recréée de zéro avant chaque test.
"""

import uuid
from collections.abc import Callable, Iterator
from typing import Any

import bcrypt
import numpy as np
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app import db_models, main, media_service
from app.config import settings
from app.db import Base, enable_sqlite_foreign_keys, get_db
from app.db_models import User
from app.fast_translation_service import fast_translation_service
from app.languages import to_nllb_code
from app.main import app
from app.routers import meta
from app.security import hash_password
from app.speech_service import speech_service
from app.translation_service import translation_service

# `StaticPool` : toutes les requêtes réutilisent LA MÊME connexion SQLite en
# mémoire, pour que les données écrites par une requête soient visibles par
# la suivante. Clés étrangères activées comme sur la vraie base.
_test_engine = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False}, poolclass=StaticPool)
enable_sqlite_foreign_keys(_test_engine)
TestSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=_test_engine)

STAFF_PASSWORD = "mot-de-passe-solide"
_original_gensalt = bcrypt.gensalt


def _override_get_db() -> Iterator[Session]:
    db = TestSessionLocal()
    try:
        yield db
    finally:
        db.close()


app.dependency_overrides[get_db] = _override_get_db


@pytest.fixture(autouse=True)
def _reset_test_database(tmp_path, monkeypatch) -> Iterator[None]:
    """Avant chaque test : tables vides, limite de débit remise à zéro (état
    global du processus), dossier média temporaire propre au test."""
    assert db_models.User is not None  # enregistre les tables sur Base.metadata
    # bcrypt au coût minimal (4 au lieu de 12) : chaque test crée des comptes,
    # et le coût réel de production rendait la suite plusieurs fois plus lente
    # sans rien tester de plus.
    monkeypatch.setattr(bcrypt, "gensalt", lambda rounds=4, prefix=b"2b": _original_gensalt(4, prefix))
    Base.metadata.create_all(bind=_test_engine)
    main.limiter.reset()
    # /health sonde la base : jamais la vraie base de développement (dev.db).
    monkeypatch.setattr(meta, "engine", _test_engine)
    monkeypatch.setattr(settings, "media_dir", str(tmp_path / "media"))
    yield
    Base.metadata.drop_all(bind=_test_engine)


@pytest.fixture
def db() -> Iterator[Session]:
    session = TestSessionLocal()
    try:
        yield session
    finally:
        session.close()


def fake_translate(text: str, source_lang: str, target_lang: str) -> str:
    """Valide les codes de langue comme le vrai moteur (ValueError -> 400),
    sans charger le moindre modèle."""
    to_nllb_code(source_lang)
    to_nllb_code(target_lang)
    return f"[{target_lang}] {text}"


@pytest.fixture
def models_loaded(client, monkeypatch) -> dict[str, Any]:
    """Fait croire que NLLB et les modèles vocaux sont chargés, avec des
    doublures déterministes. Le dictionnaire renvoyé permet à un test de
    choisir ce que "dit" la transcription ou la traduction vers le français.
    Dépend de `client` pour s'appliquer APRÈS sa remise à zéro des modèles."""
    state: dict[str, Any] = {"transcript": "Bonjour", "to_french": {}}

    def _translate(text: str, source_lang: str, target_lang: str) -> str:
        if target_lang == "fr" and text in state["to_french"]:
            return str(state["to_french"][text])
        return fake_translate(text, source_lang, target_lang)

    monkeypatch.setattr(translation_service, "_model", object())
    monkeypatch.setattr(translation_service, "translate", _translate)
    monkeypatch.setattr(speech_service, "_whisper", object())
    monkeypatch.setattr(speech_service, "transcribe", lambda audio, rate, lang: state["transcript"])
    monkeypatch.setattr(speech_service, "synthesize", lambda text, lang: (np.zeros(1600, dtype=np.float32), 16000))
    monkeypatch.setattr(
        media_service, "any_audio_or_video_to_wav_array", lambda raw, hint="input": (np.zeros(16000), 16000)
    )
    return state


@pytest.fixture
def client(monkeypatch) -> Iterator[TestClient]:
    """App de test SANS modèle chargé (cas par défaut : le serveur doit
    rester utile sans eux). Les tests qui ont besoin de la voix ou de la
    traduction ajoutent la fixture `models_loaded`."""
    monkeypatch.setattr(settings, "load_models_on_startup", False)
    monkeypatch.setattr(translation_service, "load", lambda: None)
    monkeypatch.setattr(speech_service, "load", lambda: None)
    monkeypatch.setattr(translation_service, "_model", None)
    monkeypatch.setattr(speech_service, "_whisper", None)
    monkeypatch.setattr(fast_translation_service, "is_available", lambda: False)
    with TestClient(app) as test_client:
        yield test_client


def create_staff(db: Session, role: str, email: str | None = None, **extra: Any) -> User:
    user = User(
        role=role,
        email=email or f"{role}-{uuid.uuid4().hex[:6]}@laafi-ma.bf",
        full_name=f"{role.title()} Test",
        hashed_password=hash_password(STAFF_PASSWORD),
        **extra,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def login_headers(client: TestClient, email: str, password: str = STAFF_PASSWORD) -> dict[str, str]:
    response = client.post("/auth/login", json={"email": email, "password": password})
    assert response.status_code == 200, response.text
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


@pytest.fixture
def staff_headers(client, db) -> Callable[[str], dict[str, str]]:
    """`staff_headers("validator")` -> en-têtes d'un nouveau compte de ce rôle."""

    def _make(role: str) -> dict[str, str]:
        user = create_staff(db, role)
        assert user.email is not None
        return login_headers(client, user.email)

    return _make


@pytest.fixture
def admin_headers(staff_headers) -> dict[str, str]:
    return staff_headers("admin")


@pytest.fixture
def validator_headers(staff_headers) -> dict[str, str]:
    return staff_headers("validator")


@pytest.fixture
def agent_headers(staff_headers) -> dict[str, str]:
    return staff_headers("agent")


@pytest.fixture
def woman(client) -> dict[str, Any]:
    """Un compte anonyme créé comme le fait l'app : jeton, id, code."""
    body = client.post("/auth/device").json()
    return {
        "headers": {"Authorization": f"Bearer {body['access_token']}"},
        "account_id": body["account_id"],
        "recovery_code": body["recovery_code"],
    }
