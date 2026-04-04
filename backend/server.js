import http from "node:http";

import { PORT } from "./src/config/env.js";
import { handleRequest } from "./src/router.js";
import { ensureStorage } from "./src/services/uploads.js";

const server = http.createServer(handleRequest);

server.listen(PORT, async () => {
  await ensureStorage();
  console.log(`Meal Mirror backend listening on http://localhost:${PORT}`);
});
