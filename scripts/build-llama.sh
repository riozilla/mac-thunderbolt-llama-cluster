#!/usr/bin/env bash
# build-llama.sh — build llama.cpp with RPC support on macOS (Apple Silicon).
# Run on every node (head + workers). Binaries land in "$LLAMA_CPP_DIR/build/bin".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[ -f "$SCRIPT_DIR/../.env" ] && source "$SCRIPT_DIR/../.env"
LLAMA_CPP_DIR="${LLAMA_CPP_DIR:-$HOME/llama.cpp}"

if [ ! -d "$LLAMA_CPP_DIR" ]; then
  echo ">> cloning llama.cpp into $LLAMA_CPP_DIR"
  git clone https://github.com/ggml-org/llama.cpp "$LLAMA_CPP_DIR"
fi

cd "$LLAMA_CPP_DIR"
echo ">> configuring (Metal + RPC)"
cmake -B build -DGGML_RPC=ON -DGGML_METAL=ON -DCMAKE_BUILD_TYPE=Release
echo ">> building"
cmake --build build --config Release -j

echo ">> done. binaries in $LLAMA_CPP_DIR/build/bin"
ls -1 "$LLAMA_CPP_DIR/build/bin" | grep -E 'llama-server|ggml-rpc-server' || true
