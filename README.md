# Laafi Ma — women's health and protection, by voice

Laafi Ma is a voice-first application for women and girls in Burkina Faso, in
**French, Mooré and Dioula**, usable by a woman who cannot read. It serves all
women, pregnant or not, and much of it works offline. It is 100% open source
and self-hosted: no paid AI API.

French version: [README.fr.md](README.fr.md).

| Module | For | What it does |
|---|---|---|
| 1. Voice health assistant | Women | Spoken or typed question, confirmed before answering; answers come **only** from a base validated by a midwife; danger signs route her to a health centre, the hotline or emergency services |
| 2. Virtual health record | Women | Profile, cycle, contraception, pregnancy, postpartum, children and vaccines, consultations, documents, medicines, agenda, reminders, wellbeing, time-limited QR sharing, encrypted backup |
| 3. Help and protection (GBV) | Women | Separate help code, secret spoken phrase, discreet alert to trusted contacts, service directory, encrypted private journal, breathing exercise, quick exit |
| 4. Health worker space | Community health workers | Consented beneficiaries, visits, decision aid per danger sign, appointment reminders, anonymous GBV referrals, offline sync, voice translation |
| 5. Audio learning | Women, families | Short audio lessons, tracks for adolescents, mothers, men and families, rights, quizzes without scores, offline download |

Built-in protection: PIN, decoy PIN that opens an empty record, working
calculator disguise with an Android icon and name change, up to three separate
profiles on a shared phone, auto-lock.

## Repository

- [`backend/services/core-service/`](backend/services/core-service/): FastAPI API (Python 3.13), SQLite locally, PostgreSQL in production.
- [`frontend/`](frontend/): Flutter app `laafi_ma` (Android and web).
- [`admin/`](admin/): React console for validators and admins, plus the public anonymous statistics page.
- [`docs/API.md`](docs/API.md): the API contract shared by the three parts.
- [`docs/architecture.md`](docs/architecture.md): flows, AI models, deployment.
- [`docs/DEPLOY.md`](docs/DEPLOY.md): free online demo (GitHub Pages, Render, Neon).

## Install and run locally (Windows, no Docker)

```powershell
cd backend\services\core-service
python -m venv venv
.\venv\Scripts\pip install --extra-index-url https://download.pytorch.org/whl/cpu -r requirements.txt -r ..\..\requirements-dev.txt
copy .env.example .env              # then set ADMIN_EMAILS
.\venv\Scripts\python -m alembic upgrade head
.\venv\Scripts\python -m app.seed   # sourced data only
.\venv\Scripts\python -m app.bootstrap_admin
cd ..\..\..

.\scripts\dev.ps1 -Services core,admin -NoModels   # API without AI models, plus the console
.\scripts\dev.ps1 -Services core,admin,app         # with AI models and the Flutter app
.\scripts\dev.ps1 -Stop
```

API: http://127.0.0.1:8000 (docs at `/docs`). Console: http://localhost:5173.
App (web): http://localhost:5000. The AI models need about 6 GB of RAM. Without
them, voice and Mooré/Dioula return `503`; everything else works.

## Tests

```powershell
# backend\services\core-service
.\venv\Scripts\python -m pytest tests/
# frontend
flutter analyze; flutter test
# admin
npm ci; npm run lint; npm test; npm run build
```

## Data and content

- Health answers and lessons are not invented: they are entered and **validated
  by a midwife** in the console. The API serves validated content only.
- The hotline and emergency numbers are seeded as **not verified** until the
  team has confirmed them.
- The health record stays on the phone, encrypted. The optional backup is
  encrypted on the device: the server stores an unreadable blob.
- Statistics are opt-in and anonymous, stored as daily counters. The public page
  hides any figure under 10.

## Licences

The code is under the [MIT licence](LICENSE).

| Use | Model | Licence |
|---|---|---|
| Translation | NLLB-200 + Mooré LoRA adapter | CC-BY-NC 4.0 |
| Speech recognition (fr) | Whisper-small | MIT |
| Speech recognition (mos/dyu) | MMS-1b-all | CC-BY-NC 4.0 |
| Speech synthesis | MMS-TTS | CC-BY-NC 4.0 |

NLLB and MMS are **non-commercial**, and model files are not in this repository.
The Mooré training data in `backend/services/core-service/data/` comes from
[Google SMOL](https://huggingface.co/datasets/google/smol) (CC-BY-4.0).

## Known limits

- Never tested on a real Android phone: microphone, camera, SMS, calls,
  notifications and the icon change are only covered by tests with doubles.
- No operator SMS gateway yet: reminders to women without a smartphone are sent
  from the health worker's phone.
- The interface is in French; the voice and health content follow the chosen
  language.
