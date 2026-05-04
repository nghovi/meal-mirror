import crypto from "node:crypto";

import { pool } from "../db/pool.js";
import {
  createPasswordHash,
  isValidPassword,
  isValidPhoneNumber,
  normalizePhoneNumber,
  verifyPassword
} from "../utils/security.js";

export function extractBearerToken(req) {
  const authorization = req.headers.authorization || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  return match ? match[1].trim() : "";
}

export async function findUserByPhoneNumber(phoneNumber) {
  const [rows] = await pool.query(
    `select id, display_name as displayName, phone_number as phoneNumber,
            password_hash as passwordHash, auth_provider as authProvider
     from users
     where phone_number = ?
     limit 1`,
    [phoneNumber]
  );
  return rows[0] ?? null;
}

async function findUserCredentialsById(userId) {
  const [rows] = await pool.query(
    `select id, display_name as displayName, phone_number as phoneNumber,
            password_hash as passwordHash, auth_provider as authProvider
     from users
     where id = ?
     limit 1`,
    [userId]
  );
  return rows[0] ?? null;
}

export async function createPhoneUser({ phoneNumber, password, displayName }) {
  const passwordHash = createPasswordHash(password);
  const normalizedDisplayName =
    String(displayName || "").trim() || `Meal Mirror ${phoneNumber.slice(-4)}`;

  const [result] = await pool.query(
     `insert into users (
       sync_key, display_name, phone_number, password_hash, auth_provider, trial_started_at
     )
     values (null, ?, ?, ?, 'phone', utc_timestamp())`,
    [normalizedDisplayName, phoneNumber, passwordHash]
  );

  return {
    id: Number(result.insertId),
    displayName: normalizedDisplayName,
    phoneNumber,
    passwordHash,
    authProvider: "phone"
  };
}

export async function createUserSession(userId) {
  const sessionToken = crypto.randomUUID().replaceAll("-", "");
  await pool.query(
    `insert into user_sessions (session_token, user_id, expires_at)
     values (?, ?, date_add(utc_timestamp(), interval 30 day))`,
    [sessionToken, userId]
  );
  return sessionToken;
}

export async function findUserBySessionToken(sessionToken) {
  const [rows] = await pool.query(
    `select u.id, u.display_name as displayName, u.phone_number as phoneNumber
     from user_sessions us
     join users u on u.id = us.user_id
     where us.session_token = ?
       and us.expires_at > utc_timestamp()
     limit 1`,
    [sessionToken]
  );
  return rows[0] ?? null;
}

export async function deleteUserSession(sessionToken) {
  await pool.query(
    `delete from user_sessions where session_token = ?`,
    [sessionToken]
  );
}

export async function requireAuthenticatedUser(req) {
  const token = extractBearerToken(req);
  if (!token) {
    throw new Error("Authentication required");
  }

  const user = await findUserBySessionToken(token);
  if (!user) {
    throw new Error("Session expired");
  }

  return { token, user };
}

export async function registerWithPhone(body) {
  const phoneNumber = normalizePhoneNumber(body.phoneNumber);
  const password = String(body.password || "");
  const confirmPassword = String(body.confirmPassword || "");
  const displayName = String(body.displayName || "").trim();

  if (!isValidPhoneNumber(phoneNumber)) {
    throw new Error("Please enter a valid phone number.");
  }
  if (!isValidPassword(password)) {
    throw new Error("Password must be at least 8 characters.");
  }
  if (password !== confirmPassword) {
    throw new Error("Password confirmation does not match.");
  }

  const existing = await findUserByPhoneNumber(phoneNumber);
  if (existing) {
    throw new Error("That phone number is already registered.");
  }

  const user = await createPhoneUser({
    phoneNumber,
    password,
    displayName
  });
  const token = await createUserSession(user.id);
  return {
    token,
    userId: String(user.id),
    phoneNumber: user.phoneNumber,
    displayName: user.displayName
  };
}

export async function loginWithPhone(body) {
  const phoneNumber = normalizePhoneNumber(body.phoneNumber);
  const password = String(body.password || "");

  if (!isValidPhoneNumber(phoneNumber)) {
    throw new Error("Please enter a valid phone number.");
  }

  const user = await findUserByPhoneNumber(phoneNumber);
  if (!user || !verifyPassword(password, user.passwordHash)) {
    throw new Error("Phone number or password is incorrect.");
  }

  const token = await createUserSession(user.id);
  return {
    token,
    userId: String(user.id),
    phoneNumber: user.phoneNumber ?? phoneNumber,
    displayName: user.displayName ?? "Meal Mirror User"
  };
}

export async function updateDisplayName(userId, body) {
  const displayName = String(body.displayName || body.nickname || "").trim();
  if (displayName.isEmpty) {
    throw new Error("Nickname is required.");
  }
  if (displayName.length > 60) {
    throw new Error("Nickname is too long.");
  }

  await pool.query(
    `update users
     set display_name = ?
     where id = ?`,
    [displayName, userId]
  );

  const user = await findUserCredentialsById(userId);
  if (!user) {
    throw new Error("User not found.");
  }

  return {
    userId: String(user.id),
    phoneNumber: user.phoneNumber ?? "",
    displayName: user.displayName ?? displayName
  };
}

export async function updatePassword(userId, body) {
  const currentPassword = String(body.currentPassword || "");
  const newPassword = String(body.newPassword || "");
  const confirmPassword = String(body.confirmPassword || "");

  if (currentPassword.isEmpty) {
    throw new Error("Current password is required.");
  }
  if (!isValidPassword(newPassword)) {
    throw new Error("New password must be at least 8 characters.");
  }
  if (newPassword !== confirmPassword) {
    throw new Error("Password confirmation does not match.");
  }

  const user = await findUserCredentialsById(userId);
  if (!user || !verifyPassword(currentPassword, user.passwordHash)) {
    throw new Error("Current password is incorrect.");
  }

  await pool.query(
    `update users
     set password_hash = ?
     where id = ?`,
    [createPasswordHash(newPassword), userId]
  );

  return { ok: true };
}
