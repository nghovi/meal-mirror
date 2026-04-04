import { randomUUID } from "node:crypto";

import { pool } from "../db/pool.js";
import { sanitizeDeviceId } from "../utils/security.js";

const MEAL_TYPE_IDS = {
  breakfast: 1,
  lunch: 2,
  dinner: 3,
  snack: 4,
  drink: 5
};

export async function readSyncSnapshot(deviceId) {
  const safeDeviceId = sanitizeDeviceId(deviceId);
  const [rows] = await pool.query(
    `select snapshot_json from device_snapshots where device_id = ?`,
    [safeDeviceId]
  );
  const row = rows[0];
  if (!row) {
    return null;
  }
  return JSON.parse(row.snapshot_json);
}

export async function writeSyncSnapshot(deviceId, snapshot) {
  const safeDeviceId = sanitizeDeviceId(deviceId);
  const updatedAt = new Date(snapshot.updatedAt || Date.now());
  if (Number.isNaN(updatedAt.getTime())) {
    throw new Error("snapshot.updatedAt must be a valid ISO timestamp");
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();

    await connection.query(
      `insert into device_snapshots (device_id, snapshot_json, updated_at)
       values (?, ?, ?)
       on duplicate key update
         snapshot_json = values(snapshot_json),
         updated_at = values(updated_at)`,
      [
        safeDeviceId,
        JSON.stringify(snapshot),
        updatedAt.toISOString().slice(0, 19).replace("T", " ")
      ]
    );

    await syncNormalizedData(connection, safeDeviceId, snapshot);
    await connection.commit();
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

export async function readUserSnapshot(userId) {
  const [rows] = await pool.query(
    `select snapshot_json from user_snapshots where user_id = ?`,
    [userId]
  );
  const row = rows[0];
  if (!row) {
    return null;
  }
  return JSON.parse(row.snapshot_json);
}

export async function writeUserSnapshot(userId, snapshot) {
  const updatedAt = new Date(snapshot.updatedAt || Date.now());
  if (Number.isNaN(updatedAt.getTime())) {
    throw new Error("snapshot.updatedAt must be a valid ISO timestamp");
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();
    await connection.query(
      `insert into user_snapshots (user_id, snapshot_json, updated_at)
       values (?, ?, ?)
       on duplicate key update
         snapshot_json = values(snapshot_json),
         updated_at = values(updated_at)`,
      [
        userId,
        JSON.stringify(snapshot),
        updatedAt.toISOString().slice(0, 19).replace("T", " ")
      ]
    );

    await syncNormalizedDataForUser(connection, userId, snapshot, `user:${userId}`);
    await connection.commit();
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

async function syncNormalizedData(connection, deviceId, snapshot) {
  const userId = await ensureUserAndDevice(connection, deviceId);
  await syncNormalizedDataForUser(connection, userId, snapshot, deviceId);
}

async function syncNormalizedDataForUser(connection, userId, snapshot, deviceId) {
  await syncDietGoal(connection, userId, snapshot.dietGoal);
  await syncMeals(connection, userId, deviceId, snapshot.entries);
  await syncMiraMessages(connection, userId, snapshot.miraMessages);
}

async function ensureUserAndDevice(connection, deviceId) {
  const syncKey = `device:${deviceId}`;
  await connection.query(
    `insert into users (sync_key, display_name)
     values (?, ?)
     on duplicate key update
       display_name = values(display_name)`,
    [syncKey, "Meal Mirror User"]
  );

  const [userRows] = await connection.query(
    `select id from users where sync_key = ? limit 1`,
    [syncKey]
  );
  const userId = userRows[0]?.id;
  if (!userId) {
    throw new Error(`Could not resolve user for sync key ${syncKey}`);
  }

  await connection.query(
    `insert into devices (user_id, device_id, last_seen_at)
     values (?, ?, utc_timestamp())
     on duplicate key update
       user_id = values(user_id),
       last_seen_at = values(last_seen_at)`,
    [userId, deviceId]
  );

  return Number(userId);
}

async function syncDietGoal(connection, userId, dietGoal) {
  if (!dietGoal || typeof dietGoal !== "object") {
    await connection.query(`delete from diet_goals where user_id = ?`, [userId]);
    return;
  }

  const mission = String(dietGoal.mission || "").trim();
  const aiBrief = String(dietGoal.aiBrief || "").trim();
  const updatedAt = toMysqlDateTime(dietGoal.updatedAt);

  await connection.query(
    `insert into diet_goals (user_id, mission, ai_brief, goal_updated_at)
     values (?, ?, ?, ?)
     on duplicate key update
       mission = values(mission),
       ai_brief = values(ai_brief),
       goal_updated_at = values(goal_updated_at)`,
    [userId, mission, aiBrief, updatedAt]
  );
}

async function syncMeals(connection, userId, deviceId, entries) {
  const mealEntries = Array.isArray(entries) ? entries : [];
  await connection.query(
    `delete mi
     from meal_images mi
     inner join meals m on m.id = mi.meal_id
     where m.user_id = ? and m.device_id = ?`,
    [userId, deviceId]
  );
  await connection.query(
    `delete from meals where user_id = ? and device_id = ?`,
    [userId, deviceId]
  );

  for (const entry of mealEntries) {
    const mealTypeSlug = normalizeMealType(entry.mealType);
    const mealTypeId = MEAL_TYPE_IDS[mealTypeSlug];
    const [result] = await connection.query(
      `insert into meals (
          user_id,
          device_id,
          external_meal_id,
          meal_type_id,
          captured_at,
          feeling_rating,
          feeling_note,
          drink_volume_ml,
          ai_suggested_summary,
          ai_suggested_calories,
          ai_review,
          is_shared_meal,
          shared_meal_people_count,
          user_portion_percent,
          user_edited_summary,
          user_edited_calories,
          tags_json,
          raw_json
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        userId,
        deviceId,
        String(entry.id || randomUUID()),
        mealTypeId,
        toMysqlDateTime(entry.capturedAt),
        Number(entry.feelingRating || 3),
        String(entry.feelingNote || ""),
        Number(entry.drinkVolumeMl || 0),
        String(entry.aiSuggestedSummary || ""),
        Number(entry.aiSuggestedCalories || 0),
        String(entry.aiReview || ""),
        entry.isSharedMeal ? 1 : 0,
        Number(entry.sharedMealPeopleCount || 1),
        Number(entry.userPortionPercent || 100),
        entry.userEditedSummary == null ? null : String(entry.userEditedSummary),
        entry.userEditedCalories == null ? null : Number(entry.userEditedCalories),
        JSON.stringify(Array.isArray(entry.tags) ? entry.tags : []),
        JSON.stringify(entry)
      ]
    );

    const mealId = Number(result.insertId);
    const imagePaths = Array.isArray(entry.imagePaths) ? entry.imagePaths : [];
    for (let index = 0; index < imagePaths.length; index += 1) {
      await connection.query(
        `insert into meal_images (meal_id, sort_order, image_url)
         values (?, ?, ?)`,
        [mealId, index, String(imagePaths[index] || "")]
      );
    }
  }
}

async function syncMiraMessages(connection, userId, messages) {
  const miraMessages = Array.isArray(messages) ? messages : [];

  await connection.query(
    `insert into mira_conversations (user_id, title)
     values (?, 'Mira Chat')
     on duplicate key update
       title = values(title)`,
    [userId]
  );

  const [conversationRows] = await connection.query(
    `select id from mira_conversations where user_id = ? limit 1`,
    [userId]
  );
  const conversationId = conversationRows[0]?.id;
  if (!conversationId) {
    throw new Error(`Could not resolve Mira conversation for user ${userId}`);
  }

  await connection.query(
    `delete from mira_messages where conversation_id = ?`,
    [conversationId]
  );

  for (let index = 0; index < miraMessages.length; index += 1) {
    const message = miraMessages[index] || {};
    await connection.query(
      `insert into mira_messages (conversation_id, sort_order, role, text)
       values (?, ?, ?, ?)`,
      [
        conversationId,
        index,
        message.isUser ? "user" : "assistant",
        String(message.text || "")
      ]
    );
  }
}

function normalizeMealType(value) {
  const normalized = String(value || "").trim().toLowerCase();
  if (Object.hasOwn(MEAL_TYPE_IDS, normalized)) {
    return normalized;
  }
  return "snack";
}

function toMysqlDateTime(value) {
  const parsed = new Date(value || Date.now());
  if (Number.isNaN(parsed.getTime())) {
    return new Date().toISOString().slice(0, 19).replace("T", " ");
  }
  return parsed.toISOString().slice(0, 19).replace("T", " ");
}
