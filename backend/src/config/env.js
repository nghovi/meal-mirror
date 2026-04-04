import path from "node:path";
import { fileURLToPath } from "node:url";

export const PORT = Number(process.env.PORT || 8787);
export const OPENAI_API_KEY = process.env.OPENAI_API_KEY || "";
export const OPENAI_MODEL = process.env.OPENAI_MODEL || "gpt-4.1-mini";
export const DB_CONFIG = {
  host: process.env.MEAL_MIRROR_DB_HOST || process.env.DB_HOST || "127.0.0.1",
  port: Number(process.env.MEAL_MIRROR_DB_PORT || process.env.DB_PORT || 3306),
  user: process.env.MEAL_MIRROR_DB_USERNAME || process.env.DB_USERNAME || "root",
  password:
    process.env.MEAL_MIRROR_DB_PASSWORD || process.env.DB_PASSWORD || "",
  database: process.env.MEAL_MIRROR_DB_DATABASE || "meal_mirror"
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
export const BACKEND_ROOT = path.resolve(__dirname, "../..");
export const DATA_DIR = path.join(BACKEND_ROOT, "data");
export const UPLOADS_DIR = path.join(DATA_DIR, "uploads");
