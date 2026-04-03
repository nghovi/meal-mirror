# Meal Mirror

## Environment safety

- App snapshot sync is disabled by default.
- The app only syncs when `MEAL_MIRROR_SYNC_API_BASE_URL` is provided explicitly.
- This prevents local development builds from accidentally reading from or writing to the production sync database.

## Local development

- For purely local app work, do not set `MEAL_MIRROR_SYNC_API_BASE_URL`.
- If you need sync in development, point `MEAL_MIRROR_SYNC_API_BASE_URL` to a local or staging backend, not production.
- Set production sync URLs only in production release builds.
