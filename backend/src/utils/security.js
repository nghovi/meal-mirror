import crypto from "node:crypto";

export function sanitizeDeviceId(value) {
  return String(value || "").replace(/[^a-zA-Z0-9_-]/g, "").slice(0, 128);
}

export function normalizePhoneNumber(value) {
  return String(value || "").replace(/\D/g, "");
}

export function isValidPhoneNumber(value) {
  return /^0\d{9,10}$/.test(normalizePhoneNumber(value));
}

export function isValidPassword(value) {
  return String(value || "").trim().length >= 8;
}

export function createPasswordHash(password) {
  const salt = crypto.randomBytes(16).toString("hex");
  const derivedKey = crypto.scryptSync(password, salt, 64).toString("hex");
  return `scrypt:${salt}:${derivedKey}`;
}

export function verifyPassword(password, hash) {
  if (!hash || typeof hash !== "string" || !hash.startsWith("scrypt:")) {
    return false;
  }

  const [, salt, derivedKey] = hash.split(":");
  if (!salt || !derivedKey) {
    return false;
  }

  const candidate = crypto.scryptSync(password, salt, 64);
  const stored = Buffer.from(derivedKey, "hex");
  return stored.length === candidate.length &&
    crypto.timingSafeEqual(stored, candidate);
}
