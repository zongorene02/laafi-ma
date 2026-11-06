# Laafi Ma — santé et protection des femmes, à la voix

Application vocale pour les femmes du Burkina Faso, en **français, mooré et
dioula**. Elle sert toutes les femmes, enceintes ou non, et fonctionne en
grande partie sans connexion. 100 % open source et auto-hébergée : aucune API
d'IA payante.

| Module | Pour qui | Ce qu'il fait |
|---|---|---|
| 1. Assistant santé vocal | femmes | Question à la voix ou au texte, confirmée (« Vous avez demandé… ? ») avant la réponse ; réponse **uniquement** tirée d'une base fixe, jamais générée, avec une mention si aucune sage-femme ne l'a relue ; « Avez-vous compris ? » ; signes de danger signalés avec appel du centre de santé, du numéro vert ou des urgences ; question sans réponse transmise à l'équipe |
| 2. Carnet de santé virtuel | femmes | Consultations, documents, recommandations, cycle, grossesse, post-partum, agenda, rappels, bien-être, conseil de la semaine, soutien proposé après plusieurs jours d'humeur basse, partage par QR code avec journal des partages, sauvegarde chiffrée |
| 3. Aide et protection (VBG) | femmes | Code d'accès d'aide, **code vocal** (phrase banale dite ou écrite à l'assistant qui ouvre l'aide sans rien envoyer), SOS (appui long + compte à rebours, sans position pour les mineures), annuaire des services, journal privé, exercice de respiration, contacts de confiance, sortie rapide |
| 4. Espace agent (ASBC) | agents de santé communautaires | Bénéficiaires (consentement obligatoire), visites et signes de danger, fiche d'aide à la décision par signe de danger, rappels de rendez-vous (SMS ou appel depuis le téléphone de l'agent ; numéro gardé sur l'appareil), orientations VBG anonymes, synchronisation hors connexion, traduction voix fr/mooré/dioula |
| 5. Capsules audio | femmes, familles | Parcours (adolescente, future mère, jeune mère, hommes et familles, droits, bien-être), audio, quiz sans note, téléchargement hors connexion |

Protection intégrée : PIN, **profil leurre** (second PIN qui ouvre un carnet
vide), **mode déguisé** (l'application s'ouvre sur une calculatrice qui
fonctionne ; sur Android, l'icône et le nom deviennent « Calculatrice »),
**profils séparés** pour un téléphone partagé (jusqu'à 3, chacun avec son
code et son coffre chiffré), verrouillage automatique, bouton de sortie
rapide sur chaque écran.

## Organisation

- **[`backend/services/core-service/`](backend/services/core-service/)** — API FastAPI (Python 3.13), SQLite en local, PostgreSQL en production.
- **[`frontend/`](frontend/)** — application Flutter `laafi_ma` (Android `bf.ztech.laafima`, testable dans un navigateur).
- **[`admin/`](admin/)** — console web React (validateurs et administrateurs) et page publique de statistiques anonymes (`/public`).
- **[`docs/API.md`](docs/API.md)** — **contrat d'API partagé par les trois parties.** À lire avant toute modification.
- **[`docs/architecture.md`](docs/architecture.md)** — flux, modèles d'IA, déploiement.

Rôles : `woman` (compte anonyme lié à l'appareil, sans e-mail ni nom),
`agent`, `validator` (sage-femme référente), `admin`.

## Démarrer en local (Windows)

```powershell
# Une seule fois : environnement Python de l'API
cd backend\services\core-service
python -m venv venv
.\venv\Scripts\pip install --extra-index-url https://download.pytorch.org/whl/cpu -r requirements.txt -r ..\..\requirements-dev.txt
copy .env.example .env          # puis renseigner ADMIN_EMAILS
.\venv\Scripts\python -m alembic upgrade head
.\venv\Scripts\python -m app.seed             # données sourcées uniquement (voir plus bas)
.\venv\Scripts\python -m app.bootstrap_admin  # premier compte admin
cd ..\..\..

# Ensuite, à chaque session
.\scripts\dev.ps1 -Services core,admin -NoModels   # API sans modèles d'IA + console
.\scripts\dev.ps1 -Services core,admin,app         # avec les modèles et l'application Flutter
.\scripts\dev.ps1 -Stop
```

| Partie | Adresse |
|---|---|
| API | http://127.0.0.1:8000 (documentation : `/docs`) |
| Console admin | http://localhost:5173 |
| Application Flutter (web) | http://localhost:5000 |

`-NoModels` (`LOAD_MODELS_ON_STARTUP=false`) est conseillé sur une machine à
8 Go de RAM : l'assistant texte en français, la base de connaissances,
l'espace agent, l'annuaire, la sauvegarde et les statistiques fonctionnent ;
la voix et le mooré/dioula répondent `503`. Avec les modèles, le chargement
prend 1 à 3 minutes.

## Déployer

Il n'y a pas d'image Docker. La démo en ligne tourne sur le runtime Python
natif de Render (`render.yaml`, voir [`docs/DEPLOY.md`](docs/DEPLOY.md)). La
voix et le mooré/dioula tournent sur un Space Hugging Face gratuit (ZeroGPU,
dossier `hf-space/`), appelé par l'API quand `VOICE_SPACE` est réglé : 5
minutes de carte graphique par jour, premier appel lent.

## Vérifications (identiques à la CI)

```powershell
# API (dans backend\services\core-service)
.\venv\Scripts\ruff check --config ..\..\pyproject.toml .
.\venv\Scripts\ruff format --config ..\..\pyproject.toml --check .
.\venv\Scripts\mypy --config-file ..\..\pyproject.toml app
.\venv\Scripts\python -m pytest tests/

# Application (dans frontend)
dart format --line-length 120 --set-exit-if-changed lib/
flutter analyze
flutter test
flutter build web --release

# Console (dans admin)
npm ci; npm run lint; npm test; npm run build
```

## Données : rien d'inventé

- `app.seed` n'ajoute que des données sourcées : le numéro vert national VBG
  **80 00 12 87** (source : Burkina24, 2021) et les numéros d'urgence
  **17** (police), **16** (gendarmerie), **18** (sapeurs-pompiers) (source :
  SPF Affaires étrangères belge, octobre 2026), marqués **non vérifiés**
  (`verified_at` vide) tant que l'équipe ne les a pas appelés.
- Il charge aussi des réponses, des capsules et des signes de danger en
  français, tirés de documents de l'OMS et de l'UNFPA, avec le statut `sourced` :
  **aucune sage-femme ne les a relus**. L'API ne les sert qu'avec
  `SERVE_SOURCED_CONTENT=true` (activé pour la démo, à laisser à `false` pour un
  vrai pilote), et l'application les affiche comme non relus.
- Sinon, l'API ne sert que le contenu **validé** dans la console ; toute
  modification le repasse en brouillon. Aucun district n'est pré-rempli.
- Le message de repli en mooré/dioula retombe sur le français tant qu'une
  traduction humaine n'est pas fournie (`ASSISTANT_FALLBACK_MESSAGES`).

## Vie privée

- Le carnet de santé reste sur le téléphone, dans un stockage chiffré
  (AES-256). La sauvegarde en ligne est chiffrée **sur le téléphone**
  (PBKDF2-SHA256 310 000 itérations + AES-256-GCM) : le serveur ne stocke
  qu'un bloc illisible.
- Les notes personnelles sont lues avec la voix du téléphone, jamais
  envoyées au serveur.
- Statistiques : opt-in, sans identifiant, stockées en compteurs journaliers ;
  la page publique masque toute case inférieure à 10.
- Les orientations VBG ne contiennent aucun nom.

## Modèles d'IA et licences

| Usage | Modèle | Licence |
|---|---|---|
| Traduction | NLLB-200-distilled-600M + adaptateur LoRA mooré | CC-BY-NC 4.0 |
| Reconnaissance vocale (fr) | Whisper-small | MIT |
| Reconnaissance vocale (mos/dyu) | MMS-1b-all | CC-BY-NC 4.0 |
| Synthèse vocale | MMS-TTS | CC-BY-NC 4.0 |

Le code est sous licence MIT ([LICENSE](LICENSE)). Les modèles NLLB et MMS
sont **non commerciaux** : à faire valider avant tout usage par une société.
Les modèles sont dans `backend/services/core-service/models/` (ignorés par
git) et dans le cache Hugging Face.

## Limites connues

- Jamais testé sur un vrai téléphone Android : micro, caméra, SMS, appels,
  notifications, voix du téléphone et changement d'icône ne sont couverts que
  par des tests avec doublures. L'APK de debug se construit
  (`flutter build apk --debug`, ~40 min la première fois sur cette machine ;
  `kotlin.incremental=false` dans `android/gradle.properties`).
- Pas de passerelle SMS opérateur (contrat à signer) : les rappels aux femmes
  sans smartphone partent du téléphone de l'agent.
- Les rappels et le scan QR par caméra ne fonctionnent que sur Android.
- L'interface est en français ; les textes sont regroupés dans
  `frontend/lib/core/l10n/strings.dart` pour la traduction.
- Le chemin du dossier contient des espaces et un `+` : à déplacer vers un
  chemin simple (ex. `D:\dev\laafi-ma`) si le build Android échoue.
