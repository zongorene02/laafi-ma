"""
Connexion à la base de données (SQLAlchemy), voir db_models.py pour les
tables et migrations/ (Alembic) pour l'historique des changements de schéma.
"""

from collections.abc import Iterator
from typing import Any

from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, declarative_base, sessionmaker

from app.config import settings

# `connect_args` : uniquement nécessaire pour SQLite (par défaut, il refuse
# qu'une connexion soit utilisée depuis un thread différent de celui qui l'a
# créée — mais FastAPI exécute nos endpoints `def` classiques dans un pool
# de threads). PostgreSQL n'a pas cette restriction.
_is_sqlite = settings.database_url.startswith("sqlite")
connect_args = {"check_same_thread": False} if _is_sqlite else {}

# `pool_pre_ping` / `pool_recycle` : remplace en silence les connexions
# PostgreSQL fermées par l'infrastructure après une période d'inactivité.
# Sans objet pour SQLite (un fichier local).
pool_options: dict[str, Any] = {} if _is_sqlite else {"pool_pre_ping": True, "pool_recycle": 1800}

engine = create_engine(settings.database_url, connect_args=connect_args, **pool_options)


def enable_sqlite_foreign_keys(target_engine: Any) -> None:
    """SQLite n'applique PAS les clés étrangères par défaut (ni les
    `ON DELETE CASCADE` déclarés dans le schéma) : il faut l'activer sur
    chaque connexion. PostgreSQL les applique toujours."""

    @event.listens_for(target_engine, "connect")
    def _set_sqlite_pragma(dbapi_connection: Any, _record: Any) -> None:
        cursor = dbapi_connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()


if _is_sqlite:
    enable_sqlite_foreign_keys(engine)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db() -> Iterator[Session]:
    """Dépendance FastAPI : ouvre une session de base de données pour la
    durée d'UNE requête, la ferme systématiquement après (même en cas
    d'erreur, grâce au `finally`)."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
