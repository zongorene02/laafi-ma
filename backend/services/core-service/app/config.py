"""
Configuration centralisée du service.

Pourquoi `pydantic-settings` plutôt que des `os.environ.get(...)` éparpillés
dans le code : toute la configuration du service est déclarée à un seul
endroit, avec un TYPE et une valeur par défaut pour chaque paramètre.
Pydantic valide automatiquement les valeurs au démarrage (ex: si
LOG_LEVEL contient une faute de frappe, l'erreur apparaît immédiatement au
lancement, pas au milieu d'une requête trois semaines plus tard). Les
valeurs viennent, dans l'ordre de priorité : variables d'environnement
réelles > fichier `.env` > valeurs par défaut ci-dessous — un principe
standard ("configuration externalisée") qui permet de déployer EXACTEMENT
le même code en dev/staging/production, seule la config change.
"""

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

# Valeur d'exemple, volontairement identique dans .env.example : sert de
# repère au garde-fou de démarrage plus bas (voir
# `_refuse_dev_defaults_outside_development`).
DEV_ONLY_PLACEHOLDER_SECRET = "changeme-dev-only-insecure-secret"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Nom de l'environnement d'exécution, utile dans les logs/métriques pour
    # savoir d'où vient une requête (dev, staging, production).
    environment: str = "development"

    # Niveau de verbosité des logs : DEBUG (tout), INFO (normal), WARNING,
    # ERROR. En production on utilise généralement INFO ou WARNING.
    log_level: str = "INFO"

    # Charger NLLB/Whisper/MMS au démarrage. À désactiver sur une machine à
    # 8 Go de RAM quand on travaille sur autre chose que la voix : l'assistant
    # texte en français, la base de connaissances, l'espace agent, l'annuaire
    # et les statistiques fonctionnent sans aucun modèle chargé.
    load_models_on_startup: bool = True

    # --- Sécurité ---

    # Clé utilisée pour signer les jetons JWT. DOIT être remplacée par une
    # vraie valeur secrète (longue, aléatoire) en dehors du développement
    # local — voir .env.example.
    jwt_secret_key: str = DEV_ONLY_PLACEHOLDER_SECRET
    jwt_algorithm: str = "HS256"
    # Durée de vie des jetons du personnel (agents, validateurs, admins).
    jwt_expire_minutes: int = 60
    # Durée de vie des jetons "appareil" des femmes (compte anonyme) :
    # renouvelables par /auth/device/recover avec le code de récupération.
    device_token_expire_days: int = 30

    # Origines autorisées à appeler l'API depuis un navigateur (CORS). "*"
    # (tout autoriser) est pratique en dev mais refusé hors développement.
    cors_allowed_origins: list[str] = ["*"]

    # --- Administration ---

    # Emails des tout premiers admins, créés par `python -m app.bootstrap_admin`
    # (format JSON dans .env, ex: ADMIN_EMAILS=["admin@ztech.example"]).
    # Vide par défaut : personne n'est admin tant que ce n'est pas configuré.
    admin_emails: list[str] = []

    # --- Assistant (module 1) ---

    # Score de similarité minimal (0..1) pour considérer qu'une question
    # correspond à une entrée validée de la base de connaissances. En dessous,
    # la question est enregistrée (anonymement) pour les validateurs.
    assistant_min_confidence: float = 0.55

    # Message renvoyé quand aucune réponse validée ne correspond, par langue.
    # Seul le français est fourni : les versions mooré/dioula doivent être
    # écrites et relues par des locuteurs natifs, jamais inventées — tant
    # qu'elles manquent, le message français est renvoyé.
    assistant_fallback_messages: dict[str, str] = {"fr": "Demandez à votre agent de santé"}

    # Sert aussi le contenu `sourced` (OMS, UNFPA, relu par AUCUNE sage-femme),
    # toujours signalé `provisional: true`. Pour la démo uniquement : à garder
    # à False pour un vrai pilote tant que ce contenu n'est pas validé.
    serve_sourced_content: bool = False

    # Taille maximale d'un fichier audio envoyé (question vocale,
    # enregistrement humain d'une réponse...).
    max_audio_upload_bytes: int = 10 * 1024 * 1024  # 10 Mo

    # Dossier des fichiers audio servis sous /media (enregistrements humains
    # et synthèses MMS-TTS mises en cache).
    media_dir: str = "./media"

    # --- Carnet de santé (module 2) ---

    # Taille maximale du chiffré de sauvegarde (octets, après décodage base64).
    max_backup_bytes: int = 5 * 1024 * 1024  # 5 Mo

    # --- Statistiques publiques ---

    # Toute cellule dont le compte est inférieur à ce seuil est supprimée des
    # statistiques publiques (protection contre la ré-identification).
    public_stats_min_count: int = 10

    # --- Traçage distribué ---
    # Désactivé par défaut. À activer seulement si un collecteur OpenTelemetry
    # (Jaeger...) écoute à l'adresse ci-dessous.
    tracing_enabled: bool = False
    otel_exporter_endpoint: str = "http://localhost:4317"
    service_name: str = "laafi-ma-core"

    # --- Base de données ---
    # SQLite par défaut : zéro serveur à lancer, parfait pour le
    # développement local. En production : une URL PostgreSQL (voir
    # docs/DEPLOY.md) — le code SQLAlchemy ne change pas.
    database_url: str = "sqlite:///./dev.db"

    @model_validator(mode="after")
    def _refuse_dev_defaults_outside_development(self) -> "Settings":
        """Empêche de démarrer en production avec les secrets d'exemple.

        Ces valeurs par défaut sont publiques (elles sont dans ce dépôt et
        dans .env.example) : quiconque les connaît peut forger un jeton pour
        N'IMPORTE QUEL compte, y compris un compte admin. Mieux vaut refuser
        de démarrer, ce qui se voit tout de suite, qu'un déploiement ouvert
        qui a l'air de fonctionner.

        Le développement local reste volontairement sans friction.
        """
        if self.environment == "development":
            return self

        if self.jwt_secret_key == DEV_ONLY_PLACEHOLDER_SECRET:
            raise ValueError(
                "Secrets par défaut détectés hors développement : JWT_SECRET_KEY. "
                'Générer une vraie valeur, ex: python -c "import secrets; print(secrets.token_hex(32))"'
            )

        if self.cors_allowed_origins == ["*"]:
            raise ValueError(
                "CORS_ALLOWED_ORIGINS=['*'] est refusé hors développement : indiquer les domaines réels "
                "de l'app et de la console d'administration."
            )
        return self


settings = Settings()
