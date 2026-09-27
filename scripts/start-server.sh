#!/usr/bin/env bash
# start-server.sh — run on the HEAD node. Serves an OpenAI-compatible API on :PORT.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/../.env" ] && source "$SCRIPT_DIR/../.env"

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$HOME/llama.cpp}"
BIN="$LLAMA_CPP_DIR/build/bin"
MODEL_PATH="${MODEL_PATH:?set MODEL_PATH in .env}"
MODEL_ALIAS="${MODEL_ALIAS:-local-cluster}"
LLAMA_SERVER_HOST="${LLAMA_SERVER_HOST:-0.0.0.0}"
LLAMA_SERVER_PORT="${LLAMA_SERVER_PORT:-8080}"
CONTEXT_SIZE="${CONTEXT_SIZE:-32768}"
WORKER_ENDPOINTS="${WORKER_ENDPOINTS:?set WORKER_ENDPOINTS in .env}"

# CRITICAL: point at the FIRST shard with its original name. Do NOT concatenate
# multi-shard GGUFs — llama.cpp discovers siblings by filename.
if [[ "$MODEL_PATH" == *"of-"* && "$MODEL_PATH" != *"00001-of-"* ]]; then
  echo "!! MODEL_PATH does not look like shard 1 (…00001-of-N…). Loading a wrong/concatenated shard produces a garbage header and misleading connection errors." >&2
fi

# Build --rpc arg: comma-separated worker endpoints.
RPC_ARG="$(echo "$WORKER_ENDPOINTS" | tr ' ' ',')"

echo ">> starting llama-server alias=$MODEL_ALIAS on $LLAMA_SERVER_HOST:$LLAMA_SERVER_PORT"
echo ">> workers: $RPC_ARG"
echo ">> cold start for a large sharded model can take several minutes."

exec "$BIN/llama-server" \
  -m "$MODEL_PATH" \
  --rpc "$RPC_ARG" \
  --host "$LLAMA_SERVER_HOST" \
  --port "$LLAMA_SERVER_PORT" \
  -c "$CONTEXT_SIZE" \
  -ngl 999 \
  --alias "$MODEL_ALIAS"
