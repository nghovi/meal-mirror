import { analyzeMeal, coachChat, createDietGoalBrief } from "./services/ai.js";
import {
  deleteUserSession,
  extractBearerToken,
  findUserBySessionToken,
  loginWithPhone,
  registerWithPhone,
  requireAuthenticatedUser
} from "./services/auth.js";
import {
  readSyncSnapshot,
  readUserSnapshot,
  writeSyncSnapshot,
  writeUserSnapshot
} from "./services/sync.js";
import { serveUpload, storeUpload } from "./services/uploads.js";
import { sendJson, readJson, requestBaseUrl } from "./http/response.js";
import { sanitizeDeviceId } from "./utils/security.js";

export async function handleRequest(req, res) {
  if (req.method === "OPTIONS") {
    sendJson(res, 204, {});
    return;
  }

  const url = new URL(req.url || "/", requestBaseUrl(req));

  if (req.method === "GET" && url.pathname === "/health") {
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === "POST" && url.pathname === "/auth/register") {
    return respond(res, 400, async () => registerWithPhone(await readJson(req)));
  }

  if (req.method === "POST" && url.pathname === "/auth/login") {
    return respond(res, 400, async () => loginWithPhone(await readJson(req)));
  }

  if (req.method === "GET" && url.pathname === "/auth/session") {
    return respond(res, 401, async () => {
      const { user } = await requireAuthenticatedUser(req);
      return {
        userId: String(user.id),
        phoneNumber: user.phoneNumber ?? "",
        displayName: user.displayName ?? "Meal Mirror User"
      };
    });
  }

  if (req.method === "POST" && url.pathname === "/auth/logout") {
    return respond(res, 401, async () => {
      const { token } = await requireAuthenticatedUser(req);
      await deleteUserSession(token);
      return { ok: true };
    });
  }

  if (req.method === "GET" && url.pathname === "/app-state") {
    return respond(res, 401, async () => {
      const { user } = await requireAuthenticatedUser(req);
      const snapshot = await readUserSnapshot(user.id);
      if (!snapshot) {
        sendJson(res, 404, { error: "No snapshot found" });
        return null;
      }
      return { snapshot };
    });
  }

  if (req.method === "POST" && url.pathname === "/app-state") {
    return respond(res, 500, async () => {
      const { user } = await requireAuthenticatedUser(req);
      const body = await readJson(req);
      if (!body.snapshot || typeof body.snapshot !== "object") {
        sendJson(res, 400, { error: "snapshot is required" });
        return null;
      }
      await writeUserSnapshot(user.id, body.snapshot);
      return { ok: true };
    }, authAwareStatus);
  }

  if (req.method === "GET" && url.pathname === "/sync-state") {
    return respond(res, 500, async () => {
      const deviceId = sanitizeDeviceId(url.searchParams.get("deviceId"));
      if (!deviceId) {
        sendJson(res, 400, { error: "deviceId is required" });
        return null;
      }

      const snapshot = await readSyncSnapshot(deviceId);
      if (!snapshot) {
        sendJson(res, 404, { error: "No snapshot found" });
        return null;
      }

      return { snapshot };
    });
  }

  if (req.method === "POST" && url.pathname === "/sync-state") {
    return respond(res, 500, async () => {
      const body = await readJson(req);
      const deviceId = sanitizeDeviceId(body.deviceId);
      if (!deviceId || !body.snapshot || typeof body.snapshot !== "object") {
        sendJson(res, 400, { error: "deviceId and snapshot are required" });
        return null;
      }

      await writeSyncSnapshot(deviceId, body.snapshot);
      return { ok: true };
    });
  }

  if (req.method === "POST" && url.pathname === "/upload-image") {
    return respond(res, 500, async () => {
      const body = await readJson(req);
      const token = extractBearerToken(req);
      const user = token ? await findUserBySessionToken(token) : null;
      return storeUpload({
        deviceId: body.deviceId,
        userId: user?.id,
        fileName: body.fileName,
        mimeType: body.mimeType,
        base64: body.base64,
        req
      });
    });
  }

  if (req.method === "GET" && url.pathname.startsWith("/uploads/")) {
    await serveUpload(req, res);
    return;
  }

  if (req.method === "POST" && url.pathname === "/analyze-meal") {
    return respond(res, 500, async () => analyzeMeal(await readJson(req)));
  }

  if (req.method === "POST" && url.pathname === "/diet-goal-brief") {
    return respond(res, 500, async () => createDietGoalBrief(await readJson(req)));
  }

  if (req.method === "POST" && url.pathname === "/coach-chat") {
    return respond(res, 500, async () => coachChat(await readJson(req)));
  }

  sendJson(res, 404, { error: "Not found" });
}

async function respond(res, fallbackStatus, handler, statusResolver = defaultStatus) {
  try {
    const payload = await handler();
    if (payload != null) {
      sendJson(res, 200, payload);
    }
  } catch (error) {
    sendJson(res, statusResolver(error, fallbackStatus), {
      error: error instanceof Error ? error.message : "Unknown error"
    });
  }
}

function defaultStatus(_error, fallbackStatus) {
  return fallbackStatus;
}

function authAwareStatus(error, fallbackStatus) {
  if (
    error instanceof Error &&
    (error.message === "Authentication required" ||
      error.message === "Session expired")
  ) {
    return 401;
  }
  return fallbackStatus;
}
