import nodemailer from "nodemailer";

import { FEEDBACK_EMAIL, SMTP_CONFIG } from "../config/env.js";
import { pool } from "../db/pool.js";

export async function saveFeedback({ userId, message, platform, appVersion }) {
  const [result] = await pool.query(
    `insert into feedback (user_id, message, platform, app_version)
     values (?, ?, ?, ?)`,
    [userId ?? null, message.trim(), platform ?? "", appVersion ?? ""]
  );

  sendFeedbackEmail({ userId, message, platform, appVersion }).catch(() => {});

  return { id: Number(result.insertId) };
}

async function sendFeedbackEmail({ userId, message, platform, appVersion }) {
  if (!SMTP_CONFIG.host) {
    return;
  }

  const transporter = nodemailer.createTransport({
    host: SMTP_CONFIG.host,
    port: SMTP_CONFIG.port,
    secure: SMTP_CONFIG.secure,
    auth: SMTP_CONFIG.user
      ? { user: SMTP_CONFIG.user, pass: SMTP_CONFIG.password }
      : undefined,
  });

  const lines = [
    message,
    "",
    "---",
    `User: ${userId ? `#${userId}` : "anonymous"}`,
    `Platform: ${platform || "unknown"}`,
    `Version: ${appVersion || "unknown"}`,
  ];

  await transporter.sendMail({
    from: SMTP_CONFIG.from || SMTP_CONFIG.user || "noreply@meal-mirror",
    to: FEEDBACK_EMAIL,
    subject: "Meal Mirror Feedback",
    text: lines.join("\n"),
  });
}
