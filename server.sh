#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-3000}"
cd "$(dirname "$0")/server"

port_pids() {
  lsof -ti:"${PORT}" 2>/dev/null || true
}

pids=$(port_pids)
if [ -n "${pids}" ]; then
  echo "killing existing process on port ${PORT}..."
  kill -TERM ${pids} >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    pids=$(port_pids)
    [ -z "${pids}" ] && break
    sleep 0.5
  done
  pids=$(port_pids)
  if [ -n "${pids}" ]; then
    echo "process on port ${PORT} did not exit, sending SIGKILL..."
    kill -KILL ${pids} >/dev/null 2>&1 || true
    sleep 0.5
  fi
fi

exec npm run dev
