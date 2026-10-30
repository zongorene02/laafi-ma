"""
Hachage des mots de passe et des codes de récupération (bcrypt), génération
des secrets à usage unique.

Règle absolue : on ne stocke JAMAIS un mot de passe ni un code de
récupération en clair — si la base fuit un jour, ils seraient directement
exposés. `bcrypt` produit une empreinte à sens unique, salée différemment à
chaque fois (deux comptes au même mot de passe ont des empreintes
différentes), ce qui neutralise aussi les "tables arc-en-ciel"."""

import secrets
from typing import Annotated

import bcrypt
from pydantic import AfterValidator, Field

# Longueur minimale d'un mot de passe du personnel (voir docs/API.md,
# /auth/change-password). Une longueur minimale augmente réellement le coût
# d'une attaque par force brute, contrairement aux règles de "complexité"
# que le NIST (SP 800-63B) déconseille.
MIN_PASSWORD_LENGTH = 10

# bcrypt ne prend en compte que les 72 PREMIERS OCTETS d'un mot de passe : on
# refuse clairement au-delà plutôt que de tronquer en silence.
MAX_PASSWORD_BYTES = 72

# Alphabet du code de récupération : base32 de Crockford, sans I, L, O ni U —
# un code recopié à la main sur papier ne doit pas pouvoir confondre 0/O ou
# 1/I/L. 16 caractères x 5 bits = 80 bits d'entropie.
RECOVERY_CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
RECOVERY_CODE_GROUPS = 4
RECOVERY_CODE_GROUP_SIZE = 4


def _reject_passwords_bcrypt_would_truncate(password: str) -> str:
    # On compte les OCTETS, pas les caractères : un caractère accentué (ou le
    # ɛ/ɔ/ũ du mooré et du dioula) occupe plusieurs octets.
    if len(password.encode("utf-8")) > MAX_PASSWORD_BYTES:
        raise ValueError(f"Mot de passe trop long (maximum {MAX_PASSWORD_BYTES} octets)")
    return password


# Type réutilisable par tous les modèles qui reçoivent un NOUVEAU mot de
# passe. Volontairement PAS appliqué aux mots de passe de CONNEXION.
NewPassword = Annotated[
    str,
    Field(min_length=MIN_PASSWORD_LENGTH),
    AfterValidator(_reject_passwords_bcrypt_would_truncate),
]


def hash_password(plain_password: str) -> str:
    return bcrypt.hashpw(plain_password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str | None) -> bool:
    if not hashed_password:
        return False
    try:
        return bcrypt.checkpw(plain_password.encode("utf-8"), hashed_password.encode("utf-8"))
    except ValueError:
        # Mot de passe de plus de 72 octets saisi à la connexion, ou
        # empreinte corrompue : simple échec d'authentification, pas une 500.
        return False


def generate_temporary_password() -> str:
    """Mot de passe temporaire remis par un admin (création de compte,
    réinitialisation). ~96 bits d'aléa, sans caractères ambigus à dicter."""
    return secrets.token_urlsafe(12)


def generate_recovery_code() -> str:
    """Code de récupération "XXXX-XXXX-XXXX-XXXX", montré une seule fois."""
    groups = [
        "".join(secrets.choice(RECOVERY_CODE_ALPHABET) for _ in range(RECOVERY_CODE_GROUP_SIZE))
        for _ in range(RECOVERY_CODE_GROUPS)
    ]
    return "-".join(groups)


def normalize_recovery_code(code: str) -> str:
    """Tolère une saisie manuelle approximative : minuscules, espaces, tirets
    absents ou en trop, et les confusions classiques O->0, I/L->1."""
    compact = "".join(ch for ch in code.upper() if ch.isalnum())
    compact = compact.replace("O", "0").replace("I", "1").replace("L", "1")
    size = RECOVERY_CODE_GROUP_SIZE
    return "-".join(compact[i : i + size] for i in range(0, len(compact), size))
