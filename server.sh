#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-3000}"
cd "$(dirname "$0")/server"

if fuser -s "${PORT}/tcp" 2>/dev/null; then
  echo "killing existing process on port ${PORT}..."
  fuser -k -TERM "${PORT}/tcp" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    fuser -s "${PORT}/tcp" 2>/dev/null || break
    sleep 0.5
  done
  if fuser -s "${PORT}/tcp" 2>/dev/null; then
    echo "process on port ${PORT} did not exit, sending SIGKILL..."
    fuser -k -KILL "${PORT}/tcp" >/dev/null 2>&1 || true
    sleep 0.5
  fi
fi

exec npm run dev
