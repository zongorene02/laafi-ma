#!/bin/sh
# Applique les migrations de schéma (Alembic) AVANT de démarrer l'API.
# `upgrade head` est idempotent : sur une base déjà à jour, il ne fait rien.
#
# Le seed (données sourcées uniquement) et la création du premier admin sont
# des commandes manuelles, voir le README :
#   python -m app.seed
#   python -m app.bootstrap_admin
# AUTO_BOOTSTRAP=true les lance à chaque démarrage, pour les hébergeurs sans
# accès console (offres gratuites). Les deux sont idempotents.
set -e
alembic upgrade head
if [ "$AUTO_BOOTSTRAP" = "true" ]; then
  python -m app.seed
  python -m app.bootstrap_admin
fi
exec "$@"
