"""
Laafi Ma — API principale (core-service).

Application vocale de santé et de protection pour les femmes du Burkina Faso,
en français, mooré et dioula. Ce fichier ne fait qu'ASSEMBLER l'application :
middlewares, limite de débit, métriques, et les routeurs de chaque module
(`app/routers/`). Le contrat de l'API est dans `docs/API.md`.

Les endpoints sont déclarés en `def` classique (pas `async def`) : les
modèles d'IA et la base de données sont bloquants, et FastAPI exécute les
fonctions `def` dans un pool de threads, ce qui évite de geler le serveur
entier pendant une transcription ou une traduction.
"""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from prometheus_fastapi_instrumentator import Instrumentator
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.config import settings
from app.limiter import limiter
from app.logging_config import configure_logging, get_logger
from app.request_context import REQUEST_ID_HEADER, RequestContextMiddleware
from app.routers import (
    admin,
    agent,
    assistant,
    auth,
    districts,
    events,
    help,
    kb,
    learn,
    meta,
    records,
    translation,
)
from app.speech_service import speech_service
from app.tracing import setup_tracing
from app.translation_service import translation_service

configure_logging()
logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    # Code exécuté une fois au démarrage (avant le yield) et à l'arrêt (après).
    # PAS de `Base.metadata.create_all` ici : Alembic (migrations/) est le
    # SEUL responsable du schéma (voir entrypoint.sh).
    logger.info("startup.begin", environment=settings.environment)
    if settings.load_models_on_startup:
        logger.info("loading_translation_model")
        translation_service.load()
        logger.info("loading_speech_models")
        speech_service.load()
    else:
        # Mode "léger" : l'assistant texte en français, la base de
        # connaissances, l'espace agent, l'annuaire et les statistiques
        # fonctionnent ; la voix et le mooré/dioula répondent 503.
        logger.info("startup.models_skipped")
    logger.info("startup.complete")
    yield


API_DESCRIPTION = """
Laafi Ma (« santé de ma mère / ma santé ») : assistant santé vocal, carnet de
santé chiffré, annuaire d'aide et de protection, espace des agents de santé
communautaires et capsules d'apprentissage — en français, mooré et dioula.

Seuls des contenus **validés** par des professionnels de santé sont servis.
Toutes les IA utilisées sont **open source** (Whisper, NLLB-200, MMS) et
tournent sur nos serveurs : aucune donnée n'est envoyée à un service tiers.
""".strip()

OPENAPI_TAGS = [
    {"name": "Santé du service", "description": "État du service et langues disponibles."},
    {"name": "Authentification", "description": "Comptes anonymes (appareil) et connexion du personnel."},
    {"name": "Assistant", "description": "Questions écrites/vocales, FAQ hors ligne, signes de danger."},
    {"name": "Base de connaissances", "description": "Contenus de santé et circuit de validation (validateurs)."},
    {"name": "Carnet de santé", "description": "Sauvegarde chiffrée de bout en bout (blob opaque)."},
    {"name": "Aide et protection", "description": "Annuaire des numéros et services d'aide."},
    {"name": "Espace agent", "description": "Suivi des bénéficiaires par les ASBC, synchronisation hors ligne."},
    {"name": "Traduction (agents)", "description": "Traduction texte/voix (NLLB-200, Whisper, MMS)."},
    {"name": "Capsules", "description": "Capsules d'apprentissage audio + quiz."},
    {"name": "Districts", "description": "Districts sanitaires (saisis par un admin)."},
    {"name": "Statistiques anonymes", "description": "Compteurs anonymes et statistiques publiques."},
    {"name": "Médias", "description": "Fichiers audio (enregistrements humains et synthèses)."},
    {"name": "Administration", "description": "Comptes du personnel, statistiques, état du service."},
]

app = FastAPI(
    title="Laafi Ma — API (core-service)",
    description=API_DESCRIPTION,
    version="1.0.0",
    openapi_tags=OPENAPI_TAGS,
    lifespan=lifespan,
)

# CORS : l'app Flutter web et la console d'administration tournent sur un
# autre domaine que l'API. Les en-têtes exposés doivent être LISIBLES par le
# navigateur (identifiant de requête, textes et moteur de /translate-voice).
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=[REQUEST_ID_HEADER, "X-Source-Text", "X-Translated-Text", "X-Translation-Mode"],
)

# Identifiant de requête + durée sur chaque ligne de log. Ajouté APRÈS le
# CORS : Starlette exécute les middlewares dans l'ordre inverse de leur ajout.
app.add_middleware(RequestContextMiddleware)

app.state.limiter = limiter
# "type: ignore" : incompatibilité de stubs entre slowapi et Starlette (le
# handler est fourni tel quel par slowapi).
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)  # type: ignore[arg-type]

# Métriques Prometheus sur /metrics (requêtes, latences, codes d'erreur).
Instrumentator().instrument(app).expose(app)

# Traçage distribué (désactivé tant que TRACING_ENABLED n'est pas vrai).
setup_tracing(app)

for module in (meta, auth, assistant, kb, records, help, agent, translation, learn, districts, events, admin):
    app.include_router(module.router)
