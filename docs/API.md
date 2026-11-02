# Laafi Ma — API contract (v1)

Single source of truth shared by the backend (`backend/services/core-service`), the Flutter app (`frontend`) and the admin console (`admin`). Any change to an endpoint must be reflected here first.

- Base URL (dev): `http://127.0.0.1:8000`
- JSON everywhere, UTF-8. Dates `YYYY-MM-DD`, timestamps ISO 8601 UTC (`2026-10-29T10:15:00Z`). IDs are UUID strings.
- Errors: FastAPI default `{"detail": "..."}` with the right HTTP status (400, 401, 403, 404, 409, 413, 422, 429, 503).
- Auth: `Authorization: Bearer <jwt>`.
- Languages served to users: `fr`, `mos` (Mooré), `dyu` (Dioula). `en` exists only as an internal translation pivot.

## Roles

| Role | Who | How the account is created |
| --- | --- | --- |
| `woman` | App user. Anonymous: no name, no phone, no email. | `POST /auth/device` from the app |
| `agent` | Community health worker (ASBC) | Created by an admin |
| `validator` | Midwife or doctor who validates health content | Created by an admin |
| `admin` | Ztech staff | Created by an admin, or by email in `ADMIN_EMAILS` at bootstrap (`python -m app.bootstrap_admin`) |

Staff (`agent`, `validator`, `admin`) log in with email + password. Women never need an account: the app works fully offline and without an account. An account is only needed for the optional encrypted backup.

## Privacy rules (non-negotiable, enforced by the backend)

1. The server never receives a woman's health record in clear. The backup is an opaque blob encrypted on the device.
2. Stats events carry no user id, no device id, no IP stored, no free text.
3. Public stats suppress any cell with a count below `PUBLIC_STATS_MIN_COUNT` (default 10).
4. GBV referrals by agents store no name and no beneficiary id.
5. Only `validated` health content is served to the app. Single exception: `sourced` content (see below), only when `SERVE_SOURCED_CONTENT=true`, and always flagged `provisional:true` so the app can say a midwife has not reviewed it.

### Content status `sourced`

Statuses for KB entries, danger signs and capsules: `draft` → `sourced` (seed only) → `validated` → `archived`.

- `sourced` = taken from a cited public source (WHO, UNFPA), **not reviewed by any midwife**. Created only by `app.seed`, never through the API.
- `SERVE_SOURCED_CONTENT` (default `false`) decides whether public endpoints serve it. It must stay `false` for any real pilot until the content is validated.
- Every served item carries `"provisional": true|false` (`true` only for `sourced`) and `"source": str|null`: in `entry` of `ask-*`, in `GET /assistant/faq` entries, in `GET /assistant/danger-signs` and `danger_signs` hits. `GET /learn/capsules` carries `provisional` only: capsules have no source column, the source is cited in their text.
- French fallback: a language with no text never yields nothing. `ask-*`, `GET /assistant/faq` and `GET /assistant/danger-signs` serve the French text; `GET /learn/capsules?lang=` keeps the capsule listed with its `fr` translation, and the app shows that one.
- `POST .../validate` turns `sourced` into `validated` as for a draft, with the same `409` rule. Any edit of `sourced` content sets it back to `draft`. Status filters of staff endpoints accept `sourced`.

---

## Health & meta

### `GET /health`
`200 {"status":"ok","translation_model_loaded":bool,"speech_model_loaded":bool,"fast_mode_available":bool,"database":"ok"|"error"}`

### `GET /languages`
`200 [{"code":"fr","name":"Français"},{"code":"mos","name":"Mooré"},{"code":"dyu","name":"Dioula"}]`

---

## Auth

### `POST /auth/device` (no auth)
Creates an anonymous `woman` account.
`201 {"access_token":"...","token_type":"bearer","account_id":"uuid","recovery_code":"XXXX-XXXX-XXXX-XXXX"}`
The recovery code is shown once; only its hash is stored. Rate limit 5/min.

### `POST /auth/device/recover` (no auth)
Body `{"account_id":"uuid","recovery_code":"XXXX-XXXX-XXXX-XXXX"}` → `200 {"access_token":"...","token_type":"bearer"}`. Wrong pair → `401`. Rate limit 5/min.

### `POST /auth/login` (staff)
Body `{"email":"...","password":"..."}` → `200 {"access_token":"...","token_type":"bearer"}`. Rate limit 20/min.

### `GET /auth/me`
`200 {"id":"uuid","role":"woman|agent|validator|admin","email":str|null,"full_name":str|null,"district_id":str|null,"created_at":ts}`

### `POST /auth/change-password` (staff)
Body `{"current_password":"...","new_password":"..."}` (min 10 chars) → `204`.

### `DELETE /auth/me`
Deletes the account and everything attached to it (backup blob; for agents: beneficiaries and visits). `204`.

JWT lifetime: `JWT_EXPIRE_MINUTES` (default 60 for staff); woman device tokens use `DEVICE_TOKEN_EXPIRE_DAYS` (default 30) and can be refreshed by `POST /auth/device/recover`.

---

## Assistant (module 1)

### `POST /assistant/ask-text` (no auth required)
Body `{"text":"...","lang":"fr|mos|dyu"}`
### `POST /assistant/ask-voice` (no auth required)
Multipart: `audio` (wav/webm/ogg/m4a/mp3, ≤ 10 MB), `lang`.

Both return `200`:
```json
{
  "transcript": "texte reconnu (voice only, else null)",
  "question_fr": "question traduite en français (null if lang=fr)",
  "matched": true,
  "confidence": 0.82,
  "entry": {
    "id": "uuid",
    "topic": "grossesse",
    "question": "Question canonique dans la langue demandée",
    "answer": "Réponse validée dans la langue demandée",
    "audio_url": "/media/kb/<file>.wav",
    "audio_kind": "human|synthetic",
    "provisional": false,
    "source": "référence (OMS...)"
  },
  "danger": true,
  "danger_signs": [{"id":"uuid","label":"Saignement pendant la grossesse","advice":"Allez tout de suite au centre de santé, de jour comme de nuit, sans attendre.","provisional":false,"source":"..."}],
  "fallback_message": null
}
```
- No match above `ASSISTANT_MIN_CONFIDENCE` (default 0.55) → `matched:false`, `entry:null`, `fallback_message` = "Demandez à votre agent de santé" in the requested language; the question is recorded anonymously in `unanswered_questions` (text in fr, lang, timestamp) for validators.
- Danger detection runs on `question_fr` (or the fr text) against served danger-sign keywords, independently of the match.
- `audio_url`: a validated human recording if present; otherwise MMS-TTS synthesis cached on disk (`audio_kind:"synthetic"`). Speech model unavailable → `audio_url:null`.
- Speech or translation model not loaded → `503 {"detail":"Assistant vocal indisponible"}` for `ask-voice`; `ask-text` in `fr` must still work without models.

### `POST /assistant/transcribe` (no auth, rate limited 10/min)
Multipart: `audio` (same formats and limit as `ask-voice`), `lang`.
`200 {"transcript":"texte reconnu","question_fr":"traduction fr (null if lang=fr)"}`.
Nothing is stored or logged (no unanswered question, no event). Used by the app to:
1. show « Vous avez demandé : … ? » and let the woman confirm before answering (then `ask-text` with the transcript);
2. compare the transcript, **on the device**, with her secret help phrase (code vocal, module 3).
Models not loaded → `503 {"detail":"Assistant vocal indisponible"}`. The app falls back to `ask-voice` if this endpoint answers `404`.

### `GET /assistant/faq?lang=mos` (no auth)
All served entries, in that language or else in French, for offline caching:
`200 {"version":"<max updated_at>","entries":[{"id","topic","question","answer","audio_url","audio_kind","provisional":bool,"source":str|null,"is_danger_topic":bool}]}`

### `GET /assistant/danger-signs?lang=fr` (no auth)
`200 [{"id","label","advice","provisional":bool,"source":str|null,"keywords":[...],"agent_questions":["..."],"refer_when":str|null}]` (served signs only), for on-device detection when offline and for the agent decision aid (module 4). `agent_questions` / `refer_when` come from the requested language, falling back to `fr`; empty list / `null` when the validator has not written them.

### `GET /media/{path}` (no auth)
Static audio files (`/media/kb/...`, `/media/capsules/...`).

---

## Knowledge base (validators and admins)

Entry status: `draft` → `sourced` (seed only) → `validated` → `archived`. Any edit of a `sourced` or `validated` entry sets it back to `draft`.

### `GET /kb/entries?status=&topic=&q=` → `200 [KbEntry]`
### `POST /kb/entries` → `201 KbEntry`
### `GET /kb/entries/{id}` / `PUT /kb/entries/{id}` / `DELETE /kb/entries/{id}` (`204`)
### `POST /kb/entries/{id}/validate` (role `validator` or `admin`) → `200 KbEntry` (sets `validated_by`, `validated_at`). Refused `409` if the `fr` translation is missing.
### `POST /kb/entries/{id}/archive` → `200 KbEntry`
### `POST /kb/entries/{id}/audio/{lang}` multipart `audio` → `200 KbEntry` (human recording)
### `POST /kb/entries/{id}/translate` → `200 KbEntry`: fills missing `mos`/`dyu` texts by machine translation, flagged `machine_translated:true` until a human edits them.

```json
KbEntry = {
  "id":"uuid","topic":"grossesse|post_partum|contraception|menstruation|nutrition|maladies|sante_mentale|violences|enfant|hygiene|autre",
  "status":"draft|sourced|validated|archived","is_danger_topic":false,
  "translations":{
    "fr":{"question":"...","variants":["autre formulation", "..."],"answer":"...","audio_url":null,"audio_kind":null,"machine_translated":false},
    "mos":{...},"dyu":{...}
  },
  "source":"référence (protocole national, OMS...)",
  "validated_by":{"id":"uuid","full_name":"..."}|null,"validated_at":ts|null,
  "created_at":ts,"updated_at":ts
}
```

### Danger signs
`GET /kb/danger-signs` · `POST /kb/danger-signs` · `PUT /kb/danger-signs/{id}` · `DELETE /kb/danger-signs/{id}` · `POST /kb/danger-signs/{id}/validate`
```json
DangerSign = {"id":"uuid","status":"draft|sourced|validated|archived",
  "translations":{"fr":{"label":"...","advice":"...","agent_questions":["Depuis quand ?","Combien de linges ?"],"refer_when":"..."},"mos":{...},"dyu":{...}},
  "keywords_fr":["saigne","saignement","sang"],"source":"...","validated_by":...,"validated_at":...}
```
`agent_questions` (≤ 10 items, each ≤ 300 chars, default `[]`) and `refer_when` (≤ 1000 chars, default `null`) form the agent decision aid sheet: questions to ask, when to refer. Like every field, editing them sets a validated sign back to `draft`. In `mos`/`dyu`, `label` and `advice` may be empty (`""`): the public endpoint then serves the French label/advice, while the decision-aid fields stay in the requested language. Only `fr` label and advice are required, checked at validation (`409`).

### Unanswered questions
`GET /kb/unanswered?resolved=false` → `[{"id","text_fr","lang","created_at","resolved":bool}]` · `POST /kb/unanswered/{id}/resolve` → `204`.

---

## Health record backup (module 2) — role `woman`

### `PUT /records/backup`
Body `{"ciphertext":"base64","nonce":"base64","salt":"base64","kdf":"pbkdf2-sha256","kdf_iterations":310000,"cipher":"aes-256-gcm","schema_version":1,"client_updated_at":ts}` (ciphertext ≤ `MAX_BACKUP_BYTES`, default 5 MB) → `200 {"updated_at":ts,"size_bytes":int}`
### `GET /records/backup` → `200` same body + `updated_at`, or `404`.
### `DELETE /records/backup` → `204`.

The server stores the blob as-is. Key derivation and encryption happen on the device from a passphrase the woman chooses; the server never sees the passphrase.

---

## Help & protection (module 3)

### `GET /help/services?city=&category=` (no auth)
Active services only.
```json
HelpService = {"id":"uuid","name":"...","category":"hotline|vbg_center|police|gendarmerie|emergency|health|social|legal|psychosocial",
  "phone":"80 00 12 87","city":str|null,"region":str|null,"address":str|null,"hours":str|null,
  "free_call":bool,"languages":["fr","mos","dyu"],"source_url":str|null,
  "verified_at":date|null,"active":true}
```
`verified_at:null` means "not confirmed yet": the app must show it as such.
`emergency` = fire brigade / medical emergency (e.g. 18), used by the « Appeler les urgences » button of the danger banner.

### Admin: `POST /help/services` · `PUT /help/services/{id}` · `DELETE /help/services/{id}` · `POST /help/services/{id}/verify` (sets `verified_at` today). Role `admin`.

---

## Agent space (module 4) — role `agent`

All records are scoped to the logged-in agent. IDs are generated on the device (UUID v4) so records can be created offline.

```json
Beneficiary = {"id":"uuid","pseudonym":"...","village":str|null,"age_range":"<15|15-19|20-24|25-34|35-49|50+",
  "pregnant":bool,"expected_due_date":date|null,"children_under_5":int,
  "next_appointment_date":date|null,"next_appointment_reason":"prenatal|postnatal|vaccine|family_planning|follow_up|other"|null,
  "consent_given_at":ts,"notes":str|null,"updated_at":ts,"deleted":false}
Visit = {"id":"uuid","beneficiary_id":"uuid","visit_date":date,
  "type":"prenatal|postnatal|child|family_planning|follow_up|other",
  "danger_sign_ids":["uuid"],"referred":bool,"referred_to":str|null,"notes":str|null,"updated_at":ts,"deleted":false}
GbvReferral = {"id":"uuid","referral_date":date,"service_id":"uuid"|null,
  "category":"physical|sexual|psychological|economic|early_marriage|fgm|other","updated_at":ts}
```
`consent_given_at` is required: a beneficiary without consent is refused (`422`).
`next_appointment_*` drive the agent's « Rappels à faire » list (reminders for women without a smartphone). The woman's phone number, if the agent notes one, **stays on the agent's device** and is never sent to the server. No SMS gateway is wired yet (operator contract pending): the agent sends the reminder from her own phone (SMS composer or call).

### `POST /agent/sync`
Body `{"since":ts|null,"beneficiaries":[Beneficiary],"visits":[Visit],"gbv_referrals":[GbvReferral]}`
Upsert, last-write-wins on `updated_at`; `deleted:true` is a soft delete.
`200 {"server_time":ts,"beneficiaries":[...changed since `since`...],"visits":[...],"gbv_referrals":[...]}`

### Plain REST (same objects): `GET/POST /agent/beneficiaries`, `GET/PUT/DELETE /agent/beneficiaries/{id}`, `GET/POST /agent/visits?beneficiary_id=`, `POST /agent/gbv-referrals`.

### `GET /agent/summary`
`200 {"beneficiaries":int,"pregnant":int,"visits_last_30_days":int,"referrals_last_30_days":int,"danger_signs_last_30_days":int}`

### Translation and speech (reused from Trad IA, languages fr/mos/dyu only)
- **No auth required**, rate-limited per IP: `POST /translate` `{"text","source_lang","target_lang","mode":"verified|fast"}` (30/min) and `POST /text-to-speech` `{"text","language"}` → `audio/wav` (20/min). The app's "Écouter" button reads the interface in Mooré/Dioula with them, without an account. Never send a woman's personal notes there: those are read with the phone's own voice.
- **Role `agent`**: `POST /speech-to-text` · `POST /translate-voice` (same shapes as Trad IA).

---

## Learning capsules (module 5)

### `GET /learn/capsules?lang=&track=` (no auth) — served capsules only
```json
Capsule = {"id":"uuid","track":"adolescente|future_mere|jeune_mere|hommes_familles|droits|bien_etre|general",
  "status":"draft|sourced|validated|archived","order":int,
  "translations":{"fr":{"title":"...","text":"...","audio_url":str|null,"audio_kind":"human|synthetic"|null},"mos":{...},"dyu":{...}},
  "quiz":[{"question":{"fr":"..."},"choices":[{"fr":"..."}],"correct_index":0}],
  "license":"CC-BY-4.0","provisional":false,"validated_by":...,"validated_at":...}
```
### Admin/validator: `POST /learn/capsules` · `PUT /learn/capsules/{id}` · `DELETE /learn/capsules/{id}` · `POST /learn/capsules/{id}/validate` · `POST /learn/capsules/{id}/audio/{lang}`.

---

## Districts (admin)

`GET /districts` (no auth) → `[{"id":"uuid","name":"...","region":"..."}]` · `POST /districts` · `PUT /districts/{id}` · `DELETE /districts/{id}` (admin). Empty until an admin enters the real list. No district is invented.

---

## Anonymous stats

### `POST /events` (no auth, rate limited 30/min)
Body `{"events":[{"type":"app_opened|question_asked|question_unanswered|danger_flagged|help_opened|help_call|help_alert_sent|directory_viewed|capsule_played|reminder_done|record_backup|monthly_active|question_voice|answer_understood|answer_not_understood|anc_visit_recorded|vaccine_recorded","lang":"fr|mos|dyu","district_id":"uuid"|null,"occurred_on":"YYYY-MM-DD"}]}` (≤ 100 events) → `202`.
Only sent by the app if the woman accepted anonymous statistics. Dates only, no time of day. Unknown type → `422`.

| Type | Sent when | Indicator (dossier) |
| --- | --- | --- |
| `monthly_active` | at most once per calendar month per device (the device remembers the month, no id is sent) | Utilisatrices actives par mois |
| `question_voice` | a question asked with the microphone (in addition to `question_asked`) | Questions vocales traitées, par langue |
| `answer_understood` / `answer_not_understood` | the woman answers « Avez-vous compris ? » after an answer | Taux de réponses jugées comprises |
| `anc_visit_recorded` | a prenatal consultation is saved in her record | Consultations prénatales chez les utilisatrices |
| `vaccine_recorded` | a child vaccine is saved in her record | Rappels de vaccination suivis d'un vaccin |

### `GET /public/stats?from=&to=` (no auth)
```json
{"generated_at":ts,"min_count":10,"period":{"from":"YYYY-MM-DD","to":"YYYY-MM-DD"},
 "totals":[{"type":"question_asked","count":123}],
 "by_week":[{"week":"2026-W44","type":"question_asked","count":40}],
 "by_lang":[{"lang":"mos","type":"question_asked","count":60}],
 "by_district":[{"district":"...","type":"question_asked","count":30}],
 "by_month":[{"month":"2026-11","type":"help_call","count":12}],
 "by_region":[{"region":"Hauts-Bassins","type":"help_call","count":12}],
 "agent_activity":[{"month":"2026-11","region":"Hauts-Bassins","type":"agents_active|agent_visits|danger_referrals|gbv_referrals","count":14}],
 "suppressed_cells":4}
```
`agent_activity` is computed from agent records (no woman event involved): distinct agents with at least one visit or referral that month, visits, visits with `referred:true` **and** a non-empty `danger_sign_ids` (referrals for a danger sign), and GBV referrals, per month and per region of the agent's district (agents without district are skipped). Like `help_*`, these figures are only ever broken down by month and region, never by district or week. The same `min_count` suppression applies.
`monthly_active` only means something per month: clients must not sum it over a period (the `totals` cell is kept for completeness but must not be shown as « utilisatrices »).
Any cell with `count < min_count` is removed and counted in `suppressed_cells`. `help_*` and `danger_flagged` are only broken down by month and region (never by district or week).

---

## Admin

`GET /admin/users?role=` · `POST /admin/users` `{"email","full_name","role":"agent|validator|admin","district_id"}` → `201 {"user":User,"temporary_password":"..."}` (shown once) · `PATCH /admin/users/{id}` `{"role"?,"full_name"?,"district_id"?,"active"?}` · `POST /admin/users/{id}/reset-password` → `200 {"temporary_password":"..."}` · `DELETE /admin/users/{id}`.
Woman accounts are never listed individually: `GET /admin/users` excludes role `woman`.

`GET /admin/stats` → `{"women_accounts":int,"agents":int,"validators":int,"kb":{"draft":int,"sourced":int,"validated":int},"capsules":{"draft":int,"sourced":int,"validated":int},"unanswered_open":int,"events_last_30_days":int}`
`GET /admin/health` → same as `/health` plus DB and disk checks.
