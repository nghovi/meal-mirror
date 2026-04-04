import mysql from "mysql2/promise";

import { DB_CONFIG } from "../config/env.js";

export const pool = mysql.createPool({
  ...DB_CONFIG,
  connectionLimit: 10,
  charset: "utf8mb4"
});
