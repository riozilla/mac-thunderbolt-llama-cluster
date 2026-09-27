#!/usr/bin/env bash
# healthcheck.sh — probe the head node's API. Exit 0 only on HTTP 200 + status ok.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/../.env" ] && source "$SCRIPT_DIR/../.env"

HOST="${1:-127.0.0.1}"
PORT="${LLAMA_SERVER_PORT:-8080}"
URL="http://$HOST:$PORT/health"

body="$(curl -fsS --max-time 10 "$URL" 2>/dev/null || true)"
if echo "$body" | grep -q '"status"[[:space:]]*:[[:space:]]*"ok"'; then
  echo "OK: $URL -> $body"
  exit 0
fi
# A TCP listener or HTTP 503/loading is NOT healthy — treat as down.
echo "DOWN: $URL -> ${body:-<no response>}" >&2
exit 1
