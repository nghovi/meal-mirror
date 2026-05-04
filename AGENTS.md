# Repo Notes

## Every Session

Before doing anything else:

1. Read `CLAUDE.md` — architecture, commands, env safety rules
2. Run `git status` — understand what's in flight
3. If working on a backend change, check whether it also requires a DB schema change

Don't skip this. Context from prior sessions is in Claude Code memory; today's file state is truth.

## What you can do freely

- Read files, explore code, run local builds, run tests
- `flutter analyze`, `flutter test`, `node server.js` locally
- Write to files, commit locally (but don't push without being asked)

## Ask first

- Pushing to remote
- Deploying to the production server
- Running destructive commands (`rm`, `DROP TABLE`, `git reset --hard`)
- Sending or posting anything outside the machine

## Backend rollout checklist

When backend schema or sync logic changes:

1. Upload the latest backend files to `/home/centos/apps/meal-mirror/backend`.
2. Preserve server-only files:
   `.env.production`, `data/`, `node_modules/`
3. Run the DB setup script on the server:
   `/home/centos/local/node-v20.20.1-linux-x64-glibc-217/bin/node ./scripts/setup-mysql.mjs`
4. Restart the backend service:
   `sudo systemctl restart meal-mirror-api`
5. Verify service health:
   `systemctl status meal-mirror-api --no-pager`

Server: `centos@13.214.10.4` — deploy key: `/Users/nam/ch_stock_stage.pem`  
App root: `/home/centos/apps/meal-mirror` | Systemd service: `meal-mirror-api`

## Production release discipline

Do not describe a fix as `live`, `deployed`, `released`, or `resolved in production` merely because code was committed, pushed, or a GitHub URL/PR exists.

Before claiming a backend fix is live, verify **all** of the following:
- Server file matches the intended change
- DB setup ran (if schema changed)
- Service restarted
- Health check passed: `curl https://meal-mirror-api.truongdiem.online/health`

When a rollout includes schema or sync logic, do not mark it live until the DB step is also confirmed.

For production hotfixes, run a review pass before commit or deploy — focus on runtime risks, missing imports, missing guards, and verification gaps.

When sharing GitHub links in chat, label them `code pushed` (not `live`) unless production verification is done.

## Food words release check

- `food_words` must exist in production MySQL after rollout.
- The deployed `backend/src/services/sync.js` must include food-word sync logic.
- The deployed `backend/scripts/setup-mysql.mjs` must include `food_words` table creation/migration.
- Production app builds must set `MEAL_MIRROR_SYNC_API_BASE_URL`, otherwise saved words stay local on device.

## Prod verification queries

```sql
show tables like 'food_words';
show create table food_words;
select count(*) as rows_count from food_words;
select user_id, term, category, created_at from food_words order by id desc limit 20;
```

## Response style

- Keep responses short and action-oriented.
- If the user says `caveman mode on`, switch to ultra-terse replies for the rest of the thread unless turned off:
  - result first, minimal words, no fluff, bullets only when they save words.
