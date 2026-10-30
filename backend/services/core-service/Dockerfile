# Image de base "slim" : une version minimale de Python (sans les outils de
# développement inutiles à l'exécution), pour un conteneur plus léger et une
# surface d'attaque de sécurité plus petite.
#
# Version 3.13, PAS 3.11 : `requirements.txt` est figé (`pip freeze`) depuis
# l'environnement de développement Windows, qui tourne en Python 3.13.
# Certains paquets pinnés à une version précise (ex. numpy==2.5.2) exigent
# Python 3.12+ et n'ont tout simplement aucun paquet pré-compilé pour 3.11 — on a
# découvert ce décalage en tentant de construire l'image (erreur claire de
# pip : "Could not find a version that satisfies..."). La bonne pratique est
# de garder la même version de Python entre l'environnement qui fige les
# dépendances et celui qui les installe pour de vrai.
FROM python:3.13-slim

# ffmpeg est nécessaire ici (pas via imageio-ffmpeg comme sur la machine de
# dev Windows) : dans un conteneur Linux, on installe le vrai paquet système,
# plus simple et plus léger qu'embarquer un binaire par un paquet Python.
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Image de Laafi Ma (core-service) : API FastAPI + modèles NLLB/Whisper/MMS.
#
# On copie d'abord UNIQUEMENT requirements.txt, puis on installe les
# dépendances, AVANT de copier le reste du code. Pourquoi cet ordre précis :
# Docker met en cache chaque étape ("layer") d'un Dockerfile ; tant que
# requirements.txt ne change pas, Docker réutilise le cache de l'installation
# des dépendances (souvent l'étape la plus longue) même si on modifie le code
# — au lieu de tout réinstaller à chaque petit changement de code.
COPY requirements.txt .
# --extra-index-url : requirements.txt contient des versions de torch/torchaudio
# spécifiques au CPU (ex. "2.14.0+cpu"), qui n'existent que sur l'index
# PyTorch officiel, pas sur PyPI. On ajoute cet index EN PLUS de PyPI (pas à
# la place) pour que pip trouve tout le reste normalement.
RUN pip install --no-cache-dir --extra-index-url https://download.pytorch.org/whl/cpu -r requirements.txt

COPY app/ ./app/
COPY models/ ./models/
COPY migrations/ ./migrations/
COPY alembic.ini .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

# Dossier des fichiers audio (enregistrements humains, synthèses en cache),
# monté sur un volume persistant dans docker-compose.yml.
ENV MEDIA_DIR=/app/media
RUN mkdir -p /app/media

EXPOSE 8000

ENTRYPOINT ["./entrypoint.sh"]

# --host 0.0.0.0 (pas 127.0.0.1) : à l'intérieur d'un conteneur, le service
# doit écouter sur toutes les interfaces pour être joignable depuis
# l'extérieur (le gateway Traefik). Commande par défaut de l'entrypoint, qui
# applique d'abord les migrations.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
