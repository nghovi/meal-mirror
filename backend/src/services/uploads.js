import fs from "node:fs/promises";
import path from "node:path";
import { randomUUID } from "node:crypto";

import { UPLOADS_DIR } from "../config/env.js";
import { sendBytes, sendJson, requestBaseUrl } from "../http/response.js";
import { sanitizeDeviceId } from "../utils/security.js";

export async function ensureStorage() {
  await fs.mkdir(UPLOADS_DIR, { recursive: true });
}

export async function storeUpload({
  deviceId,
  userId,
  fileName,
  mimeType,
  base64,
  req
}) {
  await ensureStorage();
  const safeOwnerId =
    userId != null
      ? `user_${sanitizeDeviceId(String(userId))}`
      : sanitizeDeviceId(deviceId);
  if (!safeOwnerId) {
    throw new Error("deviceId or userId is required");
  }

  const ext = fileExtensionForMime(mimeType);
  const originalBase = path.basename(
    fileName || "meal-photo",
    path.extname(fileName || "")
  );
  const safeBase =
    originalBase.replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 48) || "meal-photo";
  const finalName = `${Date.now()}-${randomUUID()}-${safeBase}${ext}`;
  const relativePath = path.join(safeOwnerId, finalName);
  const absolutePath = path.join(UPLOADS_DIR, relativePath);

  await fs.mkdir(path.dirname(absolutePath), { recursive: true });
  await fs.writeFile(absolutePath, Buffer.from(base64, "base64"));

  return {
    url: `${requestBaseUrl(req)}/uploads/${relativePath.replaceAll(path.sep, "/")}`
  };
}

export async function serveUpload(req, res) {
  const url = new URL(req.url || "/", requestBaseUrl(req));
  const relativePath = url.pathname.replace(/^\/uploads\//, "");
  const safePath = path
    .normalize(relativePath)
    .replace(/^(\.\.(\/|\\|$))+/, "");
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
