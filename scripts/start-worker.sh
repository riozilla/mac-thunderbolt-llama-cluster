#!/usr/bin/env bash
# start-worker.sh — run on each WORKER node. Serves shards over RPC to the head node.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/../.env" ] && source "$SCRIPT_DIR/../.env"

LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$HOME/llama.cpp}"
BIN="$LLAMA_CPP_DIR/build/bin"
WORKER_RPC_PORT="${WORKER_RPC_PORT:-50052}"
WORKER_DEVICE="${WORKER_DEVICE:-MTL0}"
WORKER_THREADS="${WORKER_THREADS:-12}"
USE_RDMA="${USE_RDMA:-0}"

# librdma weak-links on macOS 26+; this lets the binary resolve it at runtime.
export DYLD_FALLBACK_LIBRARY_PATH="$BIN:${DYLD_FALLBACK_LIBRARY_PATH:-}"

if [ "$USE_RDMA" = "1" ]; then
  echo ">> RDMA enabled (device=${RDMA_DEVICE:-auto}). Only safe on a direct-link star topology."
  [ -n "${RDMA_DEVICE:-}" ] && export GGML_RDMA_DEV="$RDMA_DEVICE"
else
  echo ">> TCP transport (RDMA disabled)"
  export GGML_RPC_NO_RDMA=1
fi

exec "$BIN/ggml-rpc-server" \
  --host 0.0.0.0 \
  --port "$WORKER_RPC_PORT" \
  -d "$WORKER_DEVICE" \
  -c \
  -t "$WORKER_THREADS"
