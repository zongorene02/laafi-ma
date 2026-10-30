"""Assistant : seules des réponses VALIDÉES sont servies, les questions sans
réponse sont capturées anonymement, la détection des signes de danger est
indépendante du rapprochement, et le français écrit marche sans modèle."""

import io

from helpers import KB_NUTRITION, create_danger_sign, create_kb_entry, validated_kb_entry

from app.db_models import EventCount, UnansweredQuestion
from app.translation_service import translation_service

QUESTION = "qu'est ce que je dois manger pendant ma grossesse"


def _ask(client, text, lang="fr"):
    return client.post("/assistant/ask-text", json={"text": text, "lang": lang})


def test_ask_text_in_french_works_without_any_model(client, validator_headers):
    entry = validated_kb_entry(client, validator_headers)
    response = _ask(client, QUESTION)
    assert response.status_code == 200
    body = response.json()
    assert body["matched"] is True
    assert body["confidence"] >= 0.55
    assert body["transcript"] is None and body["question_fr"] is None
    assert body["entry"]["id"] == entry["id"]
    assert body["entry"]["answer"] == "Réponse de test validée (fr)."
    # Modèle vocal non chargé : pas d'URL audio plutôt qu'une URL cassée.
    assert body["entry"]["audio_url"] is None
    assert body["fallback_message"] is None


def test_draft_content_is_never_served(client, validator_headers, db):
    create_kb_entry(client, validator_headers)  # brouillon, jamais validé
    body = _ask(client, QUESTION).json()
    assert body["matched"] is False
    assert body["entry"] is None
    assert db.query(UnansweredQuestion).count() == 1


def test_archived_content_is_no_longer_served(client, validator_headers):
    entry = validated_kb_entry(client, validator_headers)
    client.post(f"/kb/entries/{entry['id']}/archive", headers=validator_headers)
    assert _ask(client, QUESTION).json()["matched"] is False


def test_an_unmatched_question_is_recorded_anonymously_with_a_fallback(client, validator_headers, db):
    validated_kb_entry(client, validator_headers)
    body = _ask(client, "comment réparer une moto").json()
    assert body["matched"] is False
    assert body["fallback_message"] == "Demandez à votre agent de santé"

    (question,) = db.query(UnansweredQuestion).all()
    assert question.text_fr == "comment réparer une moto"
    assert question.lang == "fr"
    assert question.resolved is False
    # Aucune colonne qui pourrait relier la question à une personne.
    assert set(UnansweredQuestion.__table__.columns.keys()) == {
        "id",
        "text_fr",
        "lang",
        "created_at",
        "resolved",
        "resolved_at",
    }


def test_danger_detection_uses_validated_signs_only_and_is_independent_of_the_match(client, validator_headers):
    create_danger_sign(client, validator_headers, validate=False)
    assert _ask(client, "je saigne beaucoup").json()["danger"] is False

    sign = create_danger_sign(client, validator_headers)
    body = _ask(client, "Je SAIGNE beaucoup depuis ce matin").json()
    assert body["matched"] is False  # aucune entrée de la base ne correspond...
    assert body["danger"] is True  # ...mais le danger est quand même signalé
    assert body["danger_signs"] == [
        {"id": sign["id"], "label": "Saignement pendant la grossesse", "advice": "Allez au centre de santé."}
    ]


def test_moore_question_without_translation_model_is_503(client):
    response = _ask(client, "kibaré", lang="mos")
    assert response.status_code == 503


def test_moore_question_is_translated_matched_and_answered_in_moore(client, validator_headers, models_loaded):
    validated_kb_entry(client, validator_headers)
    models_loaded["to_french"]["question en moore"] = QUESTION
    body = _ask(client, "question en moore", lang="mos").json()
    assert body["question_fr"] == QUESTION
    assert body["matched"] is True
    assert body["entry"]["answer"] == "Réponse de test (mos)"
    assert body["entry"]["audio_kind"] == "synthetic"
    assert body["entry"]["audio_url"].startswith("/media/kb/tts/")


def test_dioula_without_validated_dioula_text_falls_back_to_french(client, validator_headers, models_loaded):
    validated_kb_entry(client, validator_headers)
    models_loaded["to_french"]["question en dioula"] = QUESTION
    body = _ask(client, "question en dioula", lang="dyu").json()
    assert body["matched"] is True
    assert body["entry"]["answer"] == "Réponse de test validée (fr)."


def test_unknown_language_is_422(client):
    assert _ask(client, "hello", lang="en").status_code == 422


# --- Questions vocales --------------------------------------------------------


def _ask_voice(client, lang="fr", content=b"audio factice"):
    return client.post(
        "/assistant/ask-voice",
        files={"audio": ("question.m4a", io.BytesIO(content), "audio/mp4")},
        data={"lang": lang},
    )


def test_ask_voice_without_speech_model_is_503(client):
    response = _ask_voice(client)
    assert response.status_code == 503
    assert response.json()["detail"] == "Assistant vocal indisponible"


def test_ask_voice_transcribes_then_answers(client, validator_headers, models_loaded):
    validated_kb_entry(client, validator_headers)
    models_loaded["transcript"] = QUESTION
    body = _ask_voice(client).json()
    assert body["transcript"] == QUESTION
    assert body["matched"] is True


def test_ask_voice_in_moore_goes_through_french(client, validator_headers, models_loaded):
    validated_kb_entry(client, validator_headers)
    models_loaded["transcript"] = "transcription moore"
    models_loaded["to_french"]["transcription moore"] = QUESTION
    body = _ask_voice(client, lang="mos").json()
    assert body["transcript"] == "transcription moore"
    assert body["question_fr"] == QUESTION
    assert body["entry"]["answer"] == "Réponse de test (mos)"


def test_ask_voice_rejects_files_over_10_mb(client, models_loaded):
    response = _ask_voice(client, content=b"0" * (10 * 1024 * 1024 + 1))
    assert response.status_code == 413


# --- Transcription seule (confirmation, code vocal) ---------------------------


def _transcribe(client, lang="fr", content=b"audio factice"):
    return client.post(
        "/assistant/transcribe",
        files={"audio": ("question.m4a", io.BytesIO(content), "audio/mp4")},
        data={"lang": lang},
    )


def test_transcribe_without_speech_model_is_503(client):
    response = _transcribe(client)
    assert response.status_code == 503
    assert response.json()["detail"] == "Assistant vocal indisponible"


def test_transcribe_in_moore_without_translation_model_is_503(client, models_loaded, monkeypatch):
    monkeypatch.setattr(translation_service, "_model", None)
    assert _transcribe(client, lang="mos").status_code == 503
    # Le français n'a pas besoin du modèle de traduction.
    assert _transcribe(client, lang="fr").status_code == 200


def test_transcribe_in_french_returns_the_transcript_only(client, models_loaded):
    models_loaded["transcript"] = "  je saigne beaucoup  "
    response = _transcribe(client)
    assert response.status_code == 200
    assert response.json() == {"transcript": "je saigne beaucoup", "question_fr": None}


def test_transcribe_in_moore_also_returns_the_french_translation(client, models_loaded):
    models_loaded["transcript"] = "transcription moore"
    models_loaded["to_french"]["transcription moore"] = QUESTION
    assert _transcribe(client, lang="mos").json() == {"transcript": "transcription moore", "question_fr": QUESTION}


def test_transcribe_stores_nothing(client, validator_headers, models_loaded, db):
    """Ni question sans réponse, ni compteur d'événement : la phrase d'aide
    secrète d'une femme ne doit laisser aucune trace sur le serveur."""
    validated_kb_entry(client, validator_headers)
    models_loaded["transcript"] = "comment réparer une moto"  # aucune réponse validée
    assert _transcribe(client).status_code == 200
    assert db.query(UnansweredQuestion).count() == 0
    assert db.query(EventCount).count() == 0


def test_transcribe_validates_like_ask_voice(client, models_loaded):
    assert _transcribe(client, content=b"0" * (10 * 1024 * 1024 + 1)).status_code == 413
    assert _transcribe(client, lang="en").status_code == 422


def test_transcribe_is_rate_limited(client, models_loaded):
    statuses = [_transcribe(client).status_code for _ in range(11)]
    assert statuses[:10] == [200] * 10
    assert statuses[-1] == 429


# --- FAQ et signes de danger (hors ligne) -------------------------------------


def test_faq_lists_validated_entries_having_text_in_that_language(client, validator_headers):
    validated = validated_kb_entry(client, validator_headers)
    create_kb_entry(client, validator_headers)  # brouillon : absent

    fr = client.get("/assistant/faq", params={"lang": "fr"}).json()
    mos = client.get("/assistant/faq", params={"lang": "mos"}).json()
    dyu = client.get("/assistant/faq", params={"lang": "dyu"}).json()

    assert [e["id"] for e in fr["entries"]] == [validated["id"]]
    assert fr["entries"][0]["is_danger_topic"] is False
    assert mos["entries"][0]["answer"] == "Réponse de test (mos)"
    assert dyu["entries"] == []  # pas de texte dioula validé
    assert fr["version"].endswith("Z")


def test_faq_version_changes_when_an_entry_is_archived(client, validator_headers):
    entry = validated_kb_entry(client, validator_headers)
    before = client.get("/assistant/faq").json()["version"]
    client.post(f"/kb/entries/{entry['id']}/archive", headers=validator_headers)
    after = client.get("/assistant/faq").json()
    assert after["entries"] == []
    assert after["version"] != before


def test_public_danger_signs_are_validated_only_with_keywords(client, validator_headers):
    create_danger_sign(client, validator_headers, validate=False)
    sign = create_danger_sign(client, validator_headers)
    body = client.get("/assistant/danger-signs", params={"lang": "mos"}).json()
    # Pas de texte mooré : le français validé est renvoyé, jamais du vide.
    assert body == [
        {
            "id": sign["id"],
            "label": "Saignement pendant la grossesse",
            "advice": "Allez au centre de santé.",
            "keywords": ["saigne", "saignement", "sang"],
            "agent_questions": [],
            "refer_when": None,
        }
    ]


def test_public_danger_signs_serve_the_agent_aid_with_french_fallback(client, validator_headers):
    payload = {
        "translations": {
            "fr": {
                "label": "Saignement",
                "advice": "Allez au centre de santé.",
                "agent_questions": ["Depuis quand ?", "Combien de linges ?"],
                "refer_when": "Plus d'un linge mouillé par heure.",
            },
            "mos": {"label": "Libellé (mos)", "advice": "Conseil (mos)", "agent_questions": ["Question (mos)"]},
        },
        "keywords_fr": ["saigne"],
    }
    sign = client.post("/kb/danger-signs", json=payload, headers=validator_headers).json()
    client.post(f"/kb/danger-signs/{sign['id']}/validate", headers=validator_headers)

    (mos,) = client.get("/assistant/danger-signs", params={"lang": "mos"}).json()
    assert mos["agent_questions"] == ["Question (mos)"]
    # Pas de « quand orienter » en mooré : le français validé, champ par champ.
    assert mos["refer_when"] == "Plus d'un linge mouillé par heure."
    (dyu,) = client.get("/assistant/danger-signs", params={"lang": "dyu"}).json()
    assert dyu["agent_questions"] == ["Depuis quand ?", "Combien de linges ?"]
    assert dyu["label"] == "Saignement"


def test_human_recording_is_preferred_to_synthesis(client, validator_headers, models_loaded):
    entry = create_kb_entry(client, validator_headers, KB_NUTRITION)
    client.post(
        f"/kb/entries/{entry['id']}/audio/fr",
        files={"audio": ("voix.wav", io.BytesIO(b"wav"), "audio/wav")},
        headers=validator_headers,
    )
    client.post(f"/kb/entries/{entry['id']}/validate", headers=validator_headers)
    body = _ask(client, QUESTION).json()
    assert body["entry"]["audio_kind"] == "human"
    assert body["entry"]["audio_url"].startswith("/media/kb/human/")
    assert client.get(body["entry"]["audio_url"]).status_code == 200
