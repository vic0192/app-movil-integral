#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="3.44.2"
FLUTTER_HOME="${FLUTTER_HOME:-$HOME/.cache/biomedica/flutter-$FLUTTER_VERSION}"

if [[ ! -x "$FLUTTER_HOME/bin/flutter" ]]; then
  mkdir -p "$(dirname "$FLUTTER_HOME")"
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi

export PATH="$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:$PATH"

flutter config --no-analytics
flutter precache --web
flutter pub get --enforce-lockfile
flutter build web --release

npm ci --prefix backend
mkdir -p backend/public
cp -R build/web/. backend/public/
