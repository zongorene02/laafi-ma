"""
Identifiant unique par requête, attaché automatiquement à tous les logs.

Le problème qu'il résout : nos logs sont structurés (voir logging_config.py)
mais rien n'y relie deux lignes entre elles. Une traduction vocale écrit
plusieurs messages successifs (réception, transcription, traduction,
synthèse) ; dès que deux personnes utilisent l'application en même temps —
et le serveur exécute bien plusieurs requêtes en parallèle — ces lignes
s'entremêlent dans le flux, et il devient impossible de savoir laquelle
appartient à quelle requête. C'est exactement au moment où quelque chose
échoue en production, sous charge, qu'on en a le plus besoin.

`structlog.contextvars` résout ça sans traîner un identifiant en paramètre
dans toutes les fonctions : la valeur est stockée dans un `ContextVar`,
propre à chaque requête (et à chaque tâche asynchrone), et le processeur
`merge_contextvars` l'ajoute tout seul à chaque ligne de log émise pendant
cette requête.

L'identifiant est aussi renvoyé au client dans l'en-tête `X-Request-ID` :
quand quelqu'un signale un problème, ce code court suffit à retrouver
l'ensemble des lignes correspondantes, sans avoir à deviner à partir d'une
heure approximative.
"""

import time
import uuid

import structlog
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request

from app.logging_config import get_logger

logger = get_logger(__name__)

REQUEST_ID_HEADER = "X-Request-ID"


class RequestContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        # On réutilise l'identifiant fourni par un reverse proxy s'il en a
        # posé un (Render, un load balancer) : la même requête garde alors le
        # même identifiant d'un bout à l'autre de la chaîne, y compris dans
        # les logs du proxy.
        request_id = request.headers.get(REQUEST_ID_HEADER) or uuid.uuid4().hex[:12]

        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(request_id=request_id)

        started_at = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            # On journalise AVANT de laisser l'exception repartir : sinon la
            # seule trace serait celle produite par le serveur lui-même, sans
            # l'identifiant de requête ni la durée.
            logger.exception(
                "request.failed",
                method=request.method,
                path=request.url.path,
                duration_ms=round((time.perf_counter() - started_at) * 1000),
            )
            raise

        duration_ms = round((time.perf_counter() - started_at) * 1000)
        # La durée est journalisée systématiquement : c'est elle qui permet de
        # repérer une lenteur qui s'installe (un modèle qui met deux fois plus
        # de temps qu'avant) sans attendre que quelqu'un s'en plaigne.
        logger.info(
            "request.completed",
            method=request.method,
            path=request.url.path,
            status_code=response.status_code,
            duration_ms=duration_ms,
        )
        response.headers[REQUEST_ID_HEADER] = request_id
        return response
