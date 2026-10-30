"""
Logs structurés (JSON) plutôt que du texte libre.

Pourquoi : un `print("Erreur:", e)` est lisible par un humain qui regarde le
terminal en direct, mais devient inexploitable à grande échelle — dès qu'on a
plusieurs services et qu'on veut chercher "toutes les requêtes en échec pour
la langue mooré sur les dernières 24h", il faut pouvoir FILTRER et
REQUÊTER les logs comme des données structurées, pas du texte à parcourir
à l'œil. En production, ces logs JSON sont envoyés vers un outil
d'agrégation (ex. Grafana Loki, ou la stack ELK) qui permet ce genre de
recherche. Ici, on les configure pour sortir en JSON sur la sortie standard
— n'importe quel outil peut les collecter depuis là (c'est la pratique
"12-factor app" : une application ne doit pas savoir où finissent ses logs,
juste les écrire proprement).
"""

import logging
import sys

import structlog

from app.config import settings


def configure_logging():
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=settings.log_level,
    )
    # Ces librairies (appelées par transformers/huggingface_hub pour
    # télécharger les modèles) journalisent chaque requête HTTP en détail à
    # ce niveau — utile pour déboguer un souci réseau précis, mais ça noie
    # nos propres logs applicatifs dans le bruit en temps normal.
    for noisy_logger in ("httpx", "httpcore", "urllib3"):
        logging.getLogger(noisy_logger).setLevel(logging.WARNING)

    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.getLevelName(settings.log_level)),
        logger_factory=structlog.PrintLoggerFactory(),
        cache_logger_on_first_use=True,
    )


def get_logger(name: str):
    return structlog.get_logger(name)
