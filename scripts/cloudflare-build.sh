#!/usr/bin/env bash
# Construit le site publié par Cloudflare : l'application web à la racine,
# la console admin sous /admin/. Lancé par `wrangler deploy` (voir wrangler.jsonc)
# depuis la racine du dépôt. Flutter n'existe pas dans l'image de Cloudflare :
# on clone la même version que la machine de développement et que la CI.
set -euo pipefail

FLUTTER_VERSION="3.47.2"
API_BASE_URL="${API_BASE_URL:-https://laafi-ma-api.onrender.com}"
ROOT="$(pwd)"
FLUTTER_DIR="${HOME}/flutter-${FLUTTER_VERSION}"

if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  git clone --quiet --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
fi
export PATH="${FLUTTER_DIR}/bin:${PATH}"
flutter --disable-analytics
flutter config --no-cli-animations

cd "${ROOT}/frontend"
flutter pub get
flutter build web --release --base-href / --dart-define=API_BASE_URL="${API_BASE_URL}"

cd "${ROOT}/admin"
npm ci
VITE_API_BASE_URL="${API_BASE_URL}" VITE_HASH_ROUTER=true npm run build -- --base=/admin/

cd "${ROOT}"
rm -rf site
mkdir site
cp -r frontend/build/web/. site/
cp -r admin/dist site/admin
