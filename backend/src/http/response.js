import { PORT } from "../config/env.js";

export function sendJson(res, status, body) {
  res.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type,Authorization"
  });
  res.end(JSON.stringify(body));
}

export function sendBytes(res, status, contentType, bytes) {
  res.writeHead(status, {
    "Content-Type": contentType,
    "Access-Control-Allow-Origin": "*"
  });
  res.end(bytes);
}

export function readJson(req) {
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

export function requestBaseUrl(req) {
  const host = req.headers.host || `localhost:${PORT}`;
  const forwardedProto = req.headers["x-forwarded-proto"];
  const protocol = forwardedProto === "https" ? "https" : "http";
  return `${protocol}://${host}`;
}
