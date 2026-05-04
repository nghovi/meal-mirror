# Android Release Flow

## Versioning

- Update the app version in `pubspec.yaml`.
- `version:` uses the format `build-name+build-number`.
- Example: `1.0.2+5`

## Build command

Run:

```bash
MEAL_MIRROR_API_BASE_URL=https://meal-mirror-api.truongdiem.online \
./scripts/build-android-release.sh
```

This script runs:

```bash
flutter clean
flutter pub get
flutter build appbundle --release \
  --dart-define=MEAL_MIRROR_API_BASE_URL=... \
  --dart-define=MEAL_MIRROR_SYNC_API_BASE_URL=...
```

Notes:
- `MEAL_MIRROR_API_BASE_URL` is required, otherwise sign in will show `Meal Mirror auth is not configured.`
- `MEAL_MIRROR_SYNC_API_BASE_URL` defaults to the same value if not set.

## Output

- Play Store upload artifact: `build/app/outputs/bundle/release/app-release.aab`
- Android App Bundle (`.aab`) is the correct Play Store upload format.

## Local Android requirements

- `flutter doctor -v` should show no Android toolchain issues.
- Android SDK command-line tools must be installed.
- Android licenses must be accepted.
- Release signing must be configured in `android/key.properties`.

## Release metadata

- Release name format: `Meal Mirror X.Y.Z (Build N)`
- Keep release notes short and focused on user-visible changes.
