#!/usr/bin/env bash
# tunnel-worker.sh — OPTIONAL. Forward a remote worker's RPC port to a local port
# on the head node over SSH. Useful when workers aren't directly routable, or to
# avoid macOS Local Network TCC prompts for detached processes.
#
# Usage: tunnel-worker.sh <local_port> <ssh_host> [remote_rpc_port]
#   tunnel-worker.sh 50052 worker-004
#   tunnel-worker.sh 50053 worker-001 50052
set -euo pipefail

LOCAL_PORT="${1:?local port}"
SSH_HOST="${2:?ssh host/alias}"
REMOTE_PORT="${3:-50052}"

# -n: don't read stdin (prevents stdin theft in loops).
# ExitOnForwardFailure: fail loudly instead of a silent dead tunnel.
exec ssh -n -N \
  -o BatchMode=yes \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -L "127.0.0.1:${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}" \
  "$SSH_HOST"
