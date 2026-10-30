"""Vérifie le garde-fou de démarrage de config.py : le service doit REFUSER
de démarrer si on le lance hors développement avec les secrets d'exemple (ou
un CORS ouvert à tous). Ces valeurs sont publiques — elles sont dans ce dépôt
et dans .env.example — donc quiconque les connaît peut forger un jeton pour
n'importe quel compte, admin compris.

Un test à part entière parce que c'est exactement le genre de protection qui
se casse sans qu'on s'en rende compte : il suffit de renommer un champ ou de
recopier la valeur par défaut ailleurs pour que le garde-fou ne détecte plus
rien, et personne ne le remarque avant le déploiement."""

import pytest
from pydantic import ValidationError

from app.config import DEV_ONLY_PLACEHOLDER_SECRET, Settings

# Une configuration "de production" complète et VALIDE, dont chaque test ne
# dégrade qu'un seul champ à la fois — pour prouver que c'est bien ce champ-là
# qui déclenche le refus, et pas un autre problème de la config.
VALID_PRODUCTION_CONFIG = {
    # `_env_file=None` : on ignore le .env local du développeur, sinon ce test
    # passerait ou échouerait selon la machine sur laquelle il tourne.
    "_env_file": None,
    "environment": "production",
    "jwt_secret_key": "une-vraie-cle-longue-et-aleatoire-0123456789abcdef",
    "cors_allowed_origins": ["https://laafi-ma.example.org"],
}


def test_production_config_with_real_secrets_is_accepted():
    settings = Settings(**VALID_PRODUCTION_CONFIG)
    assert settings.environment == "production"


def test_production_refuses_the_example_secret():
    config = {**VALID_PRODUCTION_CONFIG, "jwt_secret_key": DEV_ONLY_PLACEHOLDER_SECRET}

    with pytest.raises(ValidationError) as error:
        Settings(**config)

    assert "Secrets par défaut" in str(error.value)


def test_production_refuses_a_wide_open_cors():
    config = {**VALID_PRODUCTION_CONFIG, "cors_allowed_origins": ["*"]}

    with pytest.raises(ValidationError) as error:
        Settings(**config)

    assert "CORS_ALLOWED_ORIGINS" in str(error.value)


def test_development_stays_frictionless():
    """Le développement local doit rester sans aucune configuration à faire :
    c'est la contrepartie assumée du garde-fou ci-dessus."""
    settings = Settings(_env_file=None, environment="development")
    assert settings.jwt_secret_key == DEV_ONLY_PLACEHOLDER_SECRET
