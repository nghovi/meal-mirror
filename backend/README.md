# Meal Mirror Backend

Small backend service for secure OpenAI-backed meal analysis, Mira chat, diet-goal summarizing, and device sync.

The Flutter app can now call OpenAI directly without this backend if you pass:

```bash
flutter run --dart-define=OPENAI_API_KEY=your_key_here
```

Optional:

```bash
flutter run \
  --dart-define=OPENAI_API_KEY=your_key_here \
  --dart-define=OPENAI_MODEL=gpt-4.1-mini
```

This is convenient for local iteration, but it exposes your API key to the client app and is not recommended for production distribution.

For production, prefer:

```bash
flutter run \
  --dart-define=MEAL_MIRROR_API_BASE_URL=https://meal-mirror-api.truongdiem.online \
  --dart-define=MEAL_MIRROR_SYNC_API_BASE_URL=https://meal-mirror-api.truongdiem.online
```

Then keep `OPENAI_API_KEY` only on the server.

## Production files

Templates for the production server are included here:

- env example: [backend/.env.production.example](/Users/nam/projects/meal_mirror/backend/.env.production.example)
- run script: [backend/ops/run.sh](/Users/nam/projects/meal_mirror/backend/ops/run.sh)
- systemd unit: [backend/ops/meal-mirror-api.service](/Users/nam/projects/meal_mirror/backend/ops/meal-mirror-api.service)
- apache vhost: [backend/ops/meal-mirror-api.httpd.conf](/Users/nam/projects/meal_mirror/backend/ops/meal-mirror-api.httpd.conf)
- apache ssl vhost: [backend/ops/meal-mirror-api-ssl.httpd.conf](/Users/nam/projects/meal_mirror/backend/ops/meal-mirror-api-ssl.httpd.conf)
- nginx vhost: [backend/ops/meal-mirror-api.nginx.conf](/Users/nam/projects/meal_mirror/backend/ops/meal-mirror-api.nginx.conf)

Suggested production layout:

- repo path: `/home/centos/apps/meal-mirror`
- backend path: `/home/centos/apps/meal-mirror/backend`
- public host: `https://meal-mirror-api.truongdiem.online`

Suggested rollout:

1. Copy this repo to `/home/centos/apps/meal-mirror`.
2. Create `backend/.env.production` from the example and set `OPENAI_API_KEY`.
3. Set the `MEAL_MIRROR_DB_*` values in `backend/.env.production`.
4. Install a modern compatible Node runtime on the server, for example:
   `~/local/node-v20.20.1-linux-x64-glibc-217`
5. Run backend install/setup with that Node first in `PATH`, for example:
   `export PATH=$HOME/local/node-v20.20.1-linux-x64-glibc-217/bin:$PATH`
   then `npm install` in `backend/`.
6. Run `npm run db:setup` in `backend/`.
7. Copy the systemd unit into `/etc/systemd/system/meal-mirror-api.service`.
8. Copy the Apache vhost files into `/etc/httpd/conf.d/`.
9. Issue the certificate and copy the generated fullchain/key into `/etc/ssl/private/`.
10. Restart `systemd` and `httpd`.

## Run locally

```bash
cd backend
OPENAI_API_KEY=your_key_here node server.js
```

Default port: `8787`

## Flutter app configuration

Run the app with:

```bash
flutter run \
  --dart-define=MEAL_MIRROR_API_BASE_URL=http://10.0.2.2:8787 \
  --dart-define=MEAL_MIRROR_SYNC_API_BASE_URL=http://10.0.2.2:8787
```

For Android emulators, `10.0.2.2` points to the host machine.

Use the backend route for production-style architecture, because it keeps the OpenAI key off the client.

## Endpoints

- `POST /analyze-meal`
- `POST /diet-goal-brief`
- `POST /coach-chat`
- `GET /sync-state?deviceId=...`
- `POST /sync-state`
- `POST /upload-image`
- `GET /uploads/...`

Request JSON:

```json
{
  "mealType": "lunch",
  "capturedAt": "2026-04-01T12:30:00.000Z",
  "images": [
    {
      "mimeType": "image/jpeg",
      "base64": "..."
    }
  ]
}
```

## Sync behavior

The Flutter app now uses:
- `MEAL_MIRROR_API_BASE_URL` for meal analysis, Mira chat, and diet-goal summarizing
- `MEAL_MIRROR_SYNC_API_BASE_URL` for full app snapshot sync and image upload/restore

Important:
- Sync is now disabled unless `MEAL_MIRROR_SYNC_API_BASE_URL` is set explicitly.
- This prevents local builds from accidentally syncing with production data.
- Use a local/staging sync URL for development, and set the production sync URL only in production release builds.

The synced snapshot includes:
- meal entries
- diet goal
- Mira chat history

Meal images are uploaded separately and stored under `backend/data/uploads/`.
Per-device snapshots are stored in the `device_snapshots` table in the `meal_mirror` MySQL database.

The backend also materializes normalized records during sync into:
- `users`
- `devices`
- `meal_types`
- `meals`
- `meal_images`
- `diet_goals`
- `mira_conversations`
- `mira_messages`

Production sync can live at `https://meal-mirror-api.truongdiem.online`, but it must be set explicitly in the build configuration.

Example sync request:

```json
{
  "deviceId": "abc123",
  "snapshot": {
    "updatedAt": "2026-04-03T08:00:00.000Z",
    "entries": [],
    "dietGoal": null,
    "miraMessages": []
  }
}
```
