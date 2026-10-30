"""
Création du tout premier compte administrateur.

    python -m app.bootstrap_admin [--full-name "Nom Prénom"]

Pour chaque email de `ADMIN_EMAILS` (voir .env) :
- s'il n'existe pas encore : crée un compte `admin` avec le mot de passe lu
  dans la variable d'environnement `ADMIN_BOOTSTRAP_PASSWORD`, ou demandé au
  clavier (saisie masquée, deux fois) si elle est absente ;
- s'il existe déjà : le (re)passe `admin` et le réactive, sans toucher à son
  mot de passe.

Idempotent : le relancer ne crée jamais de doublon. Les comptes suivants se
créent ensuite depuis la console d'administration (POST /admin/users).
"""

import argparse
import getpass
import os
import sys
from collections.abc import Callable

from pydantic import TypeAdapter, ValidationError
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.config import settings
from app.db import SessionLocal
from app.db_models import ROLE_ADMIN, ROLE_WOMAN, User
from app.security import NewPassword, hash_password

PASSWORD_ENV_VAR = "ADMIN_BOOTSTRAP_PASSWORD"
_password_adapter: TypeAdapter[str] = TypeAdapter(NewPassword)


def validate_password(password: str) -> str:
    """Même règle que pour tout nouveau mot de passe (10 caractères min.)."""
    try:
        return _password_adapter.validate_python(password)
    except ValidationError as e:
        raise ValueError(e.errors()[0]["msg"]) from e


def prompt_password() -> str:
    first = getpass.getpass("Mot de passe du premier admin (10 caractères minimum) : ")
    second = getpass.getpass("Confirmer le mot de passe : ")
    if first != second:
        raise ValueError("Les deux saisies ne correspondent pas")
    return first


def bootstrap_admins(
    db: Session, emails: list[str], password_provider: Callable[[], str], full_name: str | None = None
) -> list[str]:
    """Crée ou promeut les admins. Renvoie une ligne de compte rendu par email.
    Le mot de passe n'est demandé QUE s'il faut créer au moins un compte."""
    report: list[str] = []
    password_hash: str | None = None
    for raw_email in emails:
        email = raw_email.strip().lower()
        if not email:
            continue
        user = db.scalar(select(User).where(func.lower(User.email) == email))
        if user is not None:
            if user.role == ROLE_WOMAN:
                report.append(f"{email} : ignoré (compte non personnel)")
                continue
            changed = user.role != ROLE_ADMIN or not user.active
            user.role = ROLE_ADMIN
            user.active = True
            report.append(f"{email} : {'promu admin' if changed else 'déjà admin'}")
            continue

        if password_hash is None:
            password_hash = hash_password(validate_password(password_provider()))
        db.add(User(role=ROLE_ADMIN, email=email, full_name=full_name, hashed_password=password_hash))
        report.append(f"{email} : compte admin créé")
    db.commit()
    return report


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Crée le premier compte admin à partir de ADMIN_EMAILS.")
    parser.add_argument("--full-name", default=None, help="Nom affiché du (des) compte(s) créé(s)")
    args = parser.parse_args(argv)

    if not settings.admin_emails:
        print('ADMIN_EMAILS est vide : renseigner ex. ADMIN_EMAILS=["admin@exemple.org"] dans .env', file=sys.stderr)
        return 1

    def _password() -> str:
        from_env = os.environ.get(PASSWORD_ENV_VAR)
        return from_env if from_env else prompt_password()

    with SessionLocal() as db:
        try:
            report = bootstrap_admins(db, settings.admin_emails, _password, args.full_name)
        except ValueError as e:
            print(f"Erreur : {e}", file=sys.stderr)
            return 1
    for line in report:
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
