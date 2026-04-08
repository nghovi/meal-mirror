import { pool } from "../db/pool.js";

const TRIAL_DAYS = 30;
const DAILY_ANALYZE_MEAL_LIMIT = 30;
const DAILY_COACH_CHAT_LIMIT = 20;
const USAGE_TZ_OFFSET_HOURS = 7;

export class ApiUsageError extends Error {
  constructor(message, { status = 400, code = "API_USAGE_ERROR" } = {}) {
    super(message);
    this.name = "ApiUsageError";
    this.status = status;
    this.code = code;
  }
}

export async function assertCanUseAi({ userId, action }) {
  const [userRows] = await pool.query(
    `select id, trial_started_at as trialStartedAt, created_at as createdAt
     from users
     where id = ?
     limit 1`,
    [userId]
  );
  const user = userRows[0];
  if (!user) {
    throw new ApiUsageError("Authentication required.", {
      status: 401,
      code: "AUTH_REQUIRED"
    });
  }

  const trialStartedAt = new Date(
    user.trialStartedAt || user.createdAt || Date.now()
  );
  const trialEndsAt = new Date(trialStartedAt.getTime());
  trialEndsAt.setDate(trialEndsAt.getDate() + TRIAL_DAYS);
  if (Date.now() >= trialEndsAt.getTime()) {
    throw new ApiUsageError(
      "Your 30-day free trial has ended. Upgrade to keep using Meal Mirror AI.",
      {
        status: 403,
        code: "TRIAL_EXPIRED"
      }
    );
  }

  const usageDate = currentUsageDate();
  const [usageRows] = await pool.query(
    `select analyze_meal_count as analyzeMealCount,
            coach_chat_count as coachChatCount
     from ai_daily_usage
     where user_id = ? and usage_date = ?
     limit 1`,
    [userId, usageDate]
  );
  const usage = usageRows[0] ?? {
    analyzeMealCount: 0,
    coachChatCount: 0
  };

  if (
    action === "analyze_meal" &&
    Number(usage.analyzeMealCount || 0) >= DAILY_ANALYZE_MEAL_LIMIT
  ) {
    throw new ApiUsageError(
      "You have reached today’s limit of 30 meal and drink analyses on the free trial.",
      {
        status: 429,
        code: "DAILY_ANALYZE_LIMIT_REACHED"
      }
    );
  }

  if (
    action === "coach_chat" &&
    Number(usage.coachChatCount || 0) >= DAILY_COACH_CHAT_LIMIT
  ) {
    throw new ApiUsageError(
      "You have reached today’s limit of 20 Mira messages on the free trial.",
      {
        status: 429,
        code: "DAILY_CHAT_LIMIT_REACHED"
      }
    );
  }
}

export async function recordAiUsage({ userId, action }) {
  const usageDate = currentUsageDate();
  const analyzeMealIncrement = action === "analyze_meal" ? 1 : 0;
  const coachChatIncrement = action === "coach_chat" ? 1 : 0;

  await pool.query(
    `insert into ai_daily_usage (
       user_id,
       usage_date,
       analyze_meal_count,
       coach_chat_count
     )
     values (?, ?, ?, ?)
     on duplicate key update
       analyze_meal_count = analyze_meal_count + values(analyze_meal_count),
       coach_chat_count = coach_chat_count + values(coach_chat_count)`,
    [userId, usageDate, analyzeMealIncrement, coachChatIncrement]
  );
}

function currentUsageDate() {
  const localNow = new Date(Date.now() + (USAGE_TZ_OFFSET_HOURS * 60 * 60 * 1000));
  return localNow.toISOString().slice(0, 10);
}
