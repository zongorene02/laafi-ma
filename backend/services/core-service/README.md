# core-service — API de Laafi Ma

API FastAPI de Laafi Ma : assistant santé vocal (fr/mooré/dioula), base de
connaissances validée, sauvegarde chiffrée du carnet de santé, annuaire
d'aide, espace des agents de santé communautaires, capsules d'apprentissage,
statistiques anonymes et administration.

- Contrat de l'API (référence commune avec l'app et la console) :
  [`docs/API.md`](../../../docs/API.md)
- Architecture et règles de confidentialité :
  [`docs/architecture.md`](../../../docs/architecture.md)
- Documentation interactive, service démarré : `http://127.0.0.1:8000/docs`

## Modules (`app/`)

| Fichier | Rôle |
|---|---|
| `main.py` | Assemble l'application : middlewares, limite de débit, métriques, routeurs |
| `routers/` | Un routeur par module (`auth`, `assistant`, `kb`, `records`, `help`, `agent`, `translation`, `learn`, `districts`, `events`, `admin`, `meta`) |
| `schemas/` | Schémas Pydantic des requêtes et réponses |
| `config.py` | Configuration (`.env`), avec garde-fous de production |
| `auth.py` / `security.py` | JWT, rôles, hachage bcrypt, codes de récupération |
| `db.py` / `db_models.py` / `db_types.py` | SQLAlchemy : connexion, tables, dates UTC |
| `content.py` | Contenus de santé : sérialisation, règle "modification = brouillon" |
| `matching.py` | Rapprochement des questions (TF-IDF n-grammes, pur Python) et mots-clés de danger |
| `audio_store.py` / `uploads.py` / `media_service.py` | Fichiers audio, envois limités en taille, décodage ffmpeg |
| `translation_service.py` | NLLB-200 + adaptateur LoRA mooré (pivot anglais) |
| `fast_translation_service.py` | Moteur rapide CTranslate2 int8 (option `mode: "fast"`) |
| `speech_service.py` | Whisper (fr), MMS-ASR (mos/dyu), MMS-TTS |
| `seed.py` | Données de départ SOURCÉES uniquement |
| `bootstrap_admin.py` | Création du premier admin |
| `logging_config.py` / `request_context.py` / `tracing.py` | Logs JSON, identifiant de requête, traçage OpenTelemetry |

Les poids des modèles (`models/`) ne sont pas versionnés.

## Installation (Windows, sans Docker)

Le chemin du projet contient des espaces et un `+` : toujours le citer.

```
cd "backend/services/core-service"
C:\Python313\python.exe -m venv venv
./venv/Scripts/python.exe -m pip install --extra-index-url https://download.pytorch.org/whl/cpu -r requirements.txt -r ../../requirements-dev.txt
copy .env.example .env    # puis ajuster
```

## Démarrage

```
./venv/Scripts/python.exe -m alembic upgrade head      # schéma
./venv/Scripts/python.exe -m app.seed                  # données sourcées (idempotent)
./venv/Scripts/python.exe -m app.bootstrap_admin       # premier admin (ADMIN_EMAILS dans .env)
./venv/Scripts/python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Ou plus simplement depuis la racine du dépôt : `.\scripts\dev.ps1` (ajouter
`-NoModels` pour démarrer sans charger les modèles).

Sur une machine à 8 Go de RAM, `LOAD_MODELS_ON_STARTUP=false` démarre l'API
sans NLLB/Whisper/MMS : l'assistant texte en français, la base de
connaissances, l'espace agent, l'annuaire et les statistiques fonctionnent ;
la voix et le mooré/dioula répondent 503.

`bootstrap_admin` lit le mot de passe dans `ADMIN_BOOTSTRAP_PASSWORD` ou le
demande au clavier (saisie masquée). Les comptes suivants (agents,
validateurs, admins) se créent depuis la console d'administration.

## Migrations

Migration initiale (autogenerate), puis une révision par évolution du
schéma (ex: `b7c2e4a91d30`, prochain rendez-vous des bénéficiaires). Les
champs ajoutés DANS une colonne JSON (ex: fiche d'aide des signes de danger)
n'en demandent pas : leurs valeurs par défaut sont appliquées à la lecture.
Après une modification de `db_models.py` :

```
./venv/Scripts/python.exe -m alembic revision --autogenerate -m "description"
./venv/Scripts/python.exe -m alembic upgrade head
```

## Tests et qualité

```
./venv/Scripts/python.exe -m pytest tests/
./venv/Scripts/python.exe -m ruff check --config ../../pyproject.toml .
./venv/Scripts/python.exe -m ruff format --config ../../pyproject.toml --check .
./venv/Scripts/python.exe -m mypy --config-file ../../pyproject.toml app
```

Les tests ne chargent AUCUN modèle d'IA (doublures dans `tests/conftest.py`)
et utilisent une base SQLite en mémoire : ils valident la logique de l'API
(rôles, confidentialité, circuit de validation, synchronisation), pas la
qualité des modèles.
