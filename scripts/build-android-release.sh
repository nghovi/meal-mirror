#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_AAB="$ROOT_DIR/build/app/outputs/bundle/release/app-release.aab"
API_BASE_URL="${MEAL_MIRROR_API_BASE_URL:-}"
SYNC_BASE_URL="${MEAL_MIRROR_SYNC_API_BASE_URL:-${API_BASE_URL}}"

cd "$ROOT_DIR"

if [[ -z "$API_BASE_URL" ]]; then
  echo "ERROR: MEAL_MIRROR_API_BASE_URL is required for Android release builds."
  echo "Example:"
  echo "  MEAL_MIRROR_API_BASE_URL=https://meal-mirror-api.example.com ./scripts/build-android-release.sh"
  exit 1
fi

echo "Preparing Android release build..."
flutter clean
flutter pub get
flutter build appbundle --release \
  --dart-define=MEAL_MIRROR_API_BASE_URL="$API_BASE_URL" \
  --dart-define=MEAL_MIRROR_SYNC_API_BASE_URL="$SYNC_BASE_URL"

if [[ -f "$OUTPUT_AAB" ]]; then
  echo
  echo "Release bundle ready:"
  echo "$OUTPUT_AAB"
else
  echo "Build finished, but the expected bundle was not found at:"
  echo "$OUTPUT_AAB"
  exit 1
fi
