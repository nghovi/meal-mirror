# Meal Mirror

## Environment safety

- App snapshot sync is disabled by default.
- The app only syncs when `MEAL_MIRROR_SYNC_API_BASE_URL` is provided explicitly.
- This prevents local development builds from accidentally reading from or writing to the production sync database.

## Local development

- For purely local app work, do not set `MEAL_MIRROR_SYNC_API_BASE_URL`.
- If you need sync in development, point `MEAL_MIRROR_SYNC_API_BASE_URL` to a local or staging backend, not production.
- Set production sync URLs only in production release builds.

## Android release

- Bump the app version in [pubspec.yaml](/Users/nam/projects/an_kieng/pubspec.yaml).
- Build the Play Store bundle with `MEAL_MIRROR_API_BASE_URL=https://meal-mirror-api.truongdiem.online ./scripts/build-android-release.sh`.
- Upload [app-release.aab](/Users/nam/projects/an_kieng/build/app/outputs/bundle/release/app-release.aab) when present.
- See [RELEASES.md](/Users/nam/projects/an_kieng/RELEASES.md) for the quick checklist.
