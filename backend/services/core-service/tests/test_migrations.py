"""Les migrations Alembic (jusqu'à la tête) produisent EXACTEMENT le schéma des modèles.

Les tests de l'API créent leurs tables avec `create_all` : sans ce test, un
champ ajouté à `db_models.py` sans migration passerait tous les tests puis
casserait au premier démarrage réel ("no such column")."""

from pathlib import Path

from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from sqlalchemy import create_engine, inspect

from app.config import settings
from app.db import Base

SERVICE_DIR = Path(__file__).resolve().parent.parent


def test_upgrade_matches_models_and_downgrade_is_clean(tmp_path, monkeypatch):
    url = f"sqlite:///{(tmp_path / 'migration.db').as_posix()}"
    monkeypatch.setattr(settings, "database_url", url)  # lu par migrations/env.py
    config = Config(str(SERVICE_DIR / "alembic.ini"))

    command.upgrade(config, "head")
    engine = create_engine(url)
    with engine.connect() as connection:
        diff = compare_metadata(MigrationContext.configure(connection), Base.metadata)
    assert diff == []

    command.downgrade(config, "base")
    assert set(inspect(engine).get_table_names()) == {"alembic_version"}
    engine.dispose()
