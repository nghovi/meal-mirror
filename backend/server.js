import fs from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import mysql from "mysql2/promise";

const PORT = Number(process.env.PORT || 8787);
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || "";
const OPENAI_MODEL = process.env.OPENAI_MODEL || "gpt-4.1-mini";
const DB_CONFIG = {
  host: process.env.MEAL_MIRROR_DB_HOST || process.env.DB_HOST || "127.0.0.1",
  port: Number(process.env.MEAL_MIRROR_DB_PORT || process.env.DB_PORT || 3306),
  user: process.env.MEAL_MIRROR_DB_USERNAME || process.env.DB_USERNAME || "root",
  password:
    process.env.MEAL_MIRROR_DB_PASSWORD || process.env.DB_PASSWORD || "",
  database: process.env.MEAL_MIRROR_DB_DATABASE || "meal_mirror"
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const DATA_DIR = path.join(__dirname, "data");
const UPLOADS_DIR = path.join(DATA_DIR, "uploads");
const pool = mysql.createPool({
  ...DB_CONFIG,
  connectionLimit: 10,
  charset: "utf8mb4"
});

function sendJson(res, status, body) {
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  });
  res.end(JSON.stringify(body));
}

function sendBytes(res, status, contentType, bytes) {
  res.writeHead(status, {
    "Content-Type": contentType,
    "Access-Control-Allow-Origin": "*"
  });
  res.end(bytes);
}

async function ensureStorage() {
  await fs.mkdir(UPLOADS_DIR, { recursive: true });
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let raw = "";
    req.on("data", (chunk) => {
      raw += chunk;
    });
    req.on("end", () => {
      try {
        resolve(JSON.parse(raw || "{}"));
      } catch (error) {
        reject(error);
      }
    });
    req.on("error", reject);
  });
}

function sanitizeDeviceId(value) {
  return String(value || "").replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 128);
}

function guessContentType(fileName) {
  const lower = fileName.toLowerCase();
  if (lower.endsWith(".png")) {
    return "image/png";
  }
  if (lower.endsWith(".webp")) {
    return "image/webp";
  }
  if (lower.endsWith(".heic")) {
    return "image/heic";
  }
  return "image/jpeg";
}

function fileExtensionForMime(mimeType) {
  switch ((mimeType || "").toLowerCase()) {
    case "image/png":
      return ".png";
    case "image/webp":
      return ".webp";
    case "image/heic":
      return ".heic";
    default:
      return ".jpg";
  }
}

function requestBaseUrl(req) {
  const host = req.headers.host || `localhost:${PORT}`;
  const forwardedProto = req.headers["x-forwarded-proto"];
  const protocol = forwardedProto === "https" ? "https" : "http";
  return `${protocol}://${host}`;
}

async function callOpenAi(input) {
  if (!OPENAI_API_KEY) {
    throw new Error("OPENAI_API_KEY is missing");
  }

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`
    },
    body: JSON.stringify({
      model: OPENAI_MODEL,
      input
    })
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI error: ${response.status} ${errorText}`);
  }

  return response.json();
}

function extractOpenAiOutputText(json) {
  if (typeof json.output_text === "string" && json.output_text.trim()) {
    return json.output_text.trim();
  }

  const output = Array.isArray(json.output) ? json.output : [];
  const parts = [];

  for (const item of output) {
    const content = Array.isArray(item?.content) ? item.content : [];
    for (const piece of content) {
      const text = piece?.text;
      if (typeof text === "string" && text.trim()) {
        parts.push(text.trim());
      }
    }
  }

  return parts.join("\n").trim();
}

function extractJsonObject(text) {
  const trimmed = String(text || "").trim();
  const start = trimmed.indexOf("{");
  const end = trimmed.lastIndexOf("}");
  if (start === -1 || end === -1 || end < start) {
    throw new Error(`Could not find JSON object in output: ${trimmed}`);
  }
  return JSON.parse(trimmed.slice(start, end + 1));
}

const MEAL_TYPE_IDS = {
  breakfast: 1,
  lunch: 2,
  dinner: 3,
  snack: 4,
  drink: 5
};

async function readSyncSnapshot(deviceId) {
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

async function writeSyncSnapshot(deviceId, snapshot) {
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

async function syncNormalizedData(connection, deviceId, snapshot) {
  const userId = await ensureUserAndDevice(connection, deviceId);
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

async function storeUpload({ deviceId, fileName, mimeType, base64, req }) {
  await ensureStorage();
  const safeDeviceId = sanitizeDeviceId(deviceId);
  if (!safeDeviceId) {
    throw new Error("deviceId is required");
  }

  const ext = fileExtensionForMime(mimeType);
  const originalBase = path.basename(fileName || "meal-photo", path.extname(fileName || ""));
  const safeBase = originalBase.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 48) || "meal-photo";
  const finalName = `${Date.now()}-${randomUUID()}-${safeBase}${ext}`;
  const relativePath = path.join(safeDeviceId, finalName);
  const absolutePath = path.join(UPLOADS_DIR, relativePath);

  await fs.mkdir(path.dirname(absolutePath), { recursive: true });
  await fs.writeFile(absolutePath, Buffer.from(base64, "base64"));

  return {
    url: `${requestBaseUrl(req)}/uploads/${relativePath.replaceAll(path.sep, "/")}`
  };
}

async function serveUpload(req, res) {
  const url = new URL(req.url || "/", requestBaseUrl(req));
  const relativePath = url.pathname.replace(/^\/uploads\//, "");
  const safePath = path.normalize(relativePath).replace(/^(\.\.(\/|\\|$))+/, "");
  const absolutePath = path.join(UPLOADS_DIR, safePath);

  try {
    const bytes = await fs.readFile(absolutePath);
    sendBytes(res, 200, guessContentType(absolutePath), bytes);
  } catch (error) {
    if (error && typeof error === "object" && error.code === "ENOENT") {
      sendJson(res, 404, { error: "Not found" });
      return;
    }
    sendJson(res, 500, {
      error: error instanceof Error ? error.message : "Unknown error"
    });
  }
}

async function analyzeMeal(body) {
  const images = Array.isArray(body.images) ? body.images : [];
  if (images.length === 0) {
    throw new Error("At least one image is required");
  }

  const input = [
    {
      role: "user",
      content: [
        {
          type: "input_text",
          text:
            `Analyze this ${body.mealType || "meal"} captured at ${body.capturedAt || "unknown time"}. ` +
            "If images are provided, estimate the full meal exactly as shown now across all images, including shared dishes for the whole table when relevant. " +
            "If no images are provided, rely on the user-written meal description only and say so implicitly through your estimate. " +
            "Use the user diet goal context when it is provided, but do not force the answer to sound medical or judgmental. " +
            "If the images only show a drink, fruit, dessert, or a very small item, say that directly instead of inventing a rice or protein plate. " +
            'If the images clearly show only a beverage, set detectedMealType to "drink" and estimateDrinkVolumeMl to a reasonable integer guess for the visible liquid. ' +
            "Do not reuse assumptions from earlier images beyond what is visibly present in the current set. " +
            "If the user has typed extra meal details, use them as additional context, especially counts like number of dishes, cups, glasses, bowls, portions, or water volume. " +
            "When estimating calories, count the whole meal across all visible items and the user-provided dish count or portion note when it fits the images or text description. " +
            "Do not guess how much the user personally ate unless the user explicitly gives a portion clue. " +
            "Return strict JSON only with keys: summary, estimatedCalories, review, detectedMealType, estimatedDrinkVolumeMl. " +
            "The summary should be a concise meal description. estimatedCalories must be an integer. " +
            "review should be one short helpful note about the meal for diet tracking. " +
            "detectedMealType must be one of: breakfast, lunch, dinner, snack, drink, or null. " +
            "estimatedDrinkVolumeMl must be an integer or null."
        },
        ...(body.dietGoalBrief
          ? [
              {
                type: "input_text",
                text: `User diet goal context: ${body.dietGoalBrief}`
              }
            ]
          : []),
        ...(body.userEditedSummary
          ? [
              {
                type: "input_text",
                text: `User-added meal details to consider if they match the images: ${body.userEditedSummary}`
              }
            ]
          : []),
        ...images.map((image) => ({
          type: "input_image",
          image_url: `data:${image.mimeType || "image/jpeg"};base64,${image.base64}`
        }))
      ]
    }
  ];

  const data = await callOpenAi(input);
  const outputText = extractOpenAiOutputText(data);
  const parsed = extractJsonObject(outputText);

  return {
    summary: String(parsed.summary || "").trim(),
    estimatedCalories: Number(parsed.estimatedCalories || 0),
    review: String(parsed.review || "").trim(),
    detectedMealType:
      parsed.detectedMealType == null ? null : String(parsed.detectedMealType),
    estimatedDrinkVolumeMl:
      parsed.estimatedDrinkVolumeMl == null
        ? null
        : Number(parsed.estimatedDrinkVolumeMl)
  };
}

async function createDietGoalBrief(body) {
  const mission = String(body.mission || "").trim();
  if (!mission) {
    return { brief: "" };
  }

  const data = await callOpenAi([
    {
      role: "user",
      content: [
        {
          type: "input_text",
          text:
            "Condense this diet mission into a very short reusable AI context brief. " +
            "Keep the user intent, preferred outcome, and important guardrails. " +
            "Do not repeat filler words. Keep it under 35 words. " +
            `Return strict JSON only with key: brief.\n\nMission: ${mission}`
        }
      ]
    }
  ]);

  const parsed = extractJsonObject(extractOpenAiOutputText(data));
  return {
    brief: String(parsed.brief || "").trim()
  };
}

async function coachChat(body) {
  const message = String(body.message || "").trim();
  if (!message) {
    return {
      reply:
        "Tell me what you want help with, and I will look at your recent meals with you."
    };
  }

  const dietGoalBrief = String(body.dietGoalBrief || "").trim();
  const recentSummary = String(
    body.recentSummary || "No recent meals were logged."
  ).trim();

  const data = await callOpenAi([
    {
      role: "system",
      content: [
        {
          type: "input_text",
          text:
            "You are Mira, the in-app meal reflection coach for Meal Mirror. " +
            "Be warm, observant, concise, and non-judgmental. " +
            "Do not pretend to be a doctor. " +
            "Use the user mission and recent meal history to answer clearly. " +
            "Prefer practical, specific advice over generic nutrition talk. " +
            "Keep replies under 140 words unless the user asks for more detail."
        }
      ]
    },
    {
      role: "user",
      content: [
        ...(dietGoalBrief
          ? [
              {
                type: "input_text",
                text: `Diet mission: ${dietGoalBrief}`
              }
            ]
          : []),
        {
          type: "input_text",
          text: `Recent meals:\n${recentSummary}`
        },
        {
          type: "input_text",
          text: `User message: ${message}`
        }
      ]
    }
  ]);

  return {
    reply: extractOpenAiOutputText(data).trim()
  };
}

const server = http.createServer(async (req, res) => {
  if (req.method === "OPTIONS") {
    sendJson(res, 204, {});
    return;
  }

  const url = new URL(req.url || "/", requestBaseUrl(req));

  if (req.method === "GET" && url.pathname === "/health") {
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === "GET" && url.pathname === "/sync-state") {
    try {
      const deviceId = sanitizeDeviceId(url.searchParams.get("deviceId"));
      if (!deviceId) {
        sendJson(res, 400, { error: "deviceId is required" });
        return;
      }

      const snapshot = await readSyncSnapshot(deviceId);
      if (!snapshot) {
        sendJson(res, 404, { error: "No snapshot found" });
        return;
      }

      sendJson(res, 200, { snapshot });
    } catch (error) {
      sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Unknown error"
      });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/sync-state") {
    try {
      const body = await readJson(req);
      const deviceId = sanitizeDeviceId(body.deviceId);
      if (!deviceId || !body.snapshot || typeof body.snapshot !== "object") {
        sendJson(res, 400, { error: "deviceId and snapshot are required" });
        return;
      }

      await writeSyncSnapshot(deviceId, body.snapshot);
      sendJson(res, 200, { ok: true });
    } catch (error) {
      sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Unknown error"
      });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/upload-image") {
    try {
      const body = await readJson(req);
      const result = await storeUpload({
        deviceId: body.deviceId,
        fileName: body.fileName,
        mimeType: body.mimeType,
        base64: body.base64,
        req
      });
      sendJson(res, 200, result);
    } catch (error) {
      sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Unknown error"
      });
    }
    return;
  }

  if (req.method === "GET" && url.pathname.startsWith("/uploads/")) {
    await serveUpload(req, res);
    return;
  }

  if (req.method === "POST" && url.pathname === "/analyze-meal") {
    try {
      const body = await readJson(req);
      const result = await analyzeMeal(body);
      sendJson(res, 200, result);
    } catch (error) {
      sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Unknown error"
      });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/diet-goal-brief") {
    try {
      const body = await readJson(req);
      const result = await createDietGoalBrief(body);
      sendJson(res, 200, result);
    } catch (error) {
      sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Unknown error"
      });
    }
    return;
  }

  if (req.method === "POST" && url.pathname === "/coach-chat") {
    try {
      const body = await readJson(req);
      const result = await coachChat(body);
      sendJson(res, 200, result);
    } catch (error) {
      sendJson(res, 500, {
        error: error instanceof Error ? error.message : "Unknown error"
      });
    }
    return;
  }

  sendJson(res, 404, { error: "Not found" });
});

server.listen(PORT, async () => {
  await ensureStorage();
  console.log(`Meal Mirror backend listening on http://localhost:${PORT}`);
});
