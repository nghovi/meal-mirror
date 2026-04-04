#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export NODE_ENV=production
export PORT="${PORT:-8787}"
export PATH="$HOME/local/node-v20.20.1-linux-x64-glibc-217/bin:$PATH"

if [[ -f "$ROOT_DIR/.env.production" ]]; then
  set -a
  source "$ROOT_DIR/.env.production"
  set +a
fi

exec "$HOME/local/node-v20.20.1-linux-x64-glibc-217/bin/node" server.js
