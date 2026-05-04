# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Meal Mirror is a Flutter mobile app (package name `my_diet`) paired with a Node.js backend. The app lets users photograph meals, get AI-powered nutritional analysis, chat with an AI coach ("Mira"), track a diet goal, and collect a vocabulary of food words. App state syncs across devices via the backend.

## Development commands

### Flutter app

```bash
# Local dev — no sync (safe default)
flutter run

# Local dev with AI features via backend
flutter run \
  --dart-define=MEAL_MIRROR_API_BASE_URL=http://10.0.2.2:8787

# Local dev with sync (point at local backend, not production)
flutter run \
  --dart-define=MEAL_MIRROR_API_BASE_URL=http://10.0.2.2:8787 \
  --dart-define=MEAL_MIRROR_SYNC_API_BASE_URL=http://10.0.2.2:8787

# Local dev with AI features bypassing backend entirely (key exposed to client)
flutter run --dart-define=OPENAI_API_KEY=your_key_here

# Run tests
flutter test

# Run a single test file
flutter test test/widget_test.dart

# Analyze for lint errors
flutter analyze
```

### Backend

```bash
cd backend
OPENAI_API_KEY=your_key_here node server.js   # default port 8787

# First-time DB setup (also used for migrations)
npm run db:setup
```

### Android release build

```bash
# Bump version in pubspec.yaml first
MEAL_MIRROR_API_BASE_URL=https://meal-mirror-api.truongdiem.online ./scripts/build-android-release.sh
# Output: build/app/outputs/bundle/release/app-release.aab
```

## Environment safety rule

**Never set `MEAL_MIRROR_SYNC_API_BASE_URL` in local builds.** Sync is disabled when that variable is absent, which prevents accidentally reading from or writing to the production database during development.

## Architecture

### Flutter app (`lib/`)

- **`app.dart`** — root widget; listens to `AuthService` and routes to `AuthPage` or `HomePage`
- **`services/auth_service.dart`** — singleton `AuthService` (extends `ChangeNotifier`); holds the auth session and persists it via `flutter_secure_storage`; reads `MEAL_MIRROR_API_BASE_URL` at compile time
- **`services/meal_repository.dart`** — central state hub; persists all app data to `SharedPreferences`; orchestrates sync with the backend on load and after every write via a serial `_syncQueue`
- **`services/meal_analysis_service.dart`** — calls `/analyze-meal`, `/diet-goal-brief`, `/coach-chat`, and dictionary/image APIs; reads `MEAL_MIRROR_API_BASE_URL` and optionally `OPENAI_API_KEY` at compile time

All `--dart-define` values are resolved at **compile time**, not runtime.

#### Sync modes

`MealRepository` operates in two modes depending on auth state:
- **Authenticated** — syncs via `/app-state` with a `Bearer` token (server-scoped to `user_id`)
- **Anonymous** — syncs via `/sync-state` with a stable random `deviceId` stored in `SharedPreferences`

On startup it merges local vs. remote state by comparing `updatedAt` timestamps. After every write it enqueues an async push that runs serially.

### Backend (`backend/`)

Single-file entry point `server.js` → `src/router.js` dispatches all routes. No web framework; uses Node's built-in `http` module.

**Service modules (`src/services/`):**
- `ai.js` — wraps OpenAI calls for meal analysis, diet brief, and coach chat
- `auth.js` — phone-number auth: register, login, session tokens, display name/password updates
- `sync.js` — reads/writes device snapshots (`device_snapshots` table) and user snapshots (`app_state` table); also materializes normalized records into `users`, `devices`, `meals`, `meal_images`, `diet_goals`, `mira_conversations`, `mira_messages`, `food_words`
- `trial.js` — AI usage gating and rate limiting
- `uploads.js` — stores and serves meal images from `backend/data/uploads/`

**DB (`src/db/pool.js`)** — mysql2 connection pool; credentials from env.

**Error handling pattern** — `respond()` in `router.js` wraps every handler; `authAwareStatus()` maps `Authentication required` / `Session expired` to 401 and `ApiUsageError` to its own status code.

### Production deployment

- Server: `centos@13.214.10.4`, app root `/home/centos/apps/meal-mirror`
- Systemd service: `meal-mirror-api`
- After any backend schema change: run `npm run db:setup` on the server before restarting the service
- Do not declare a backend fix "live" until the server files, DB setup, service restart, and health check are all verified (see `AGENTS.md` for the full checklist)
