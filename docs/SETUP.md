# Setup Guide

Distributed llama.cpp inference across multiple Apple Silicon Macs connected by
Thunderbolt, using llama.cpp's RPC backend. One **head node** runs
`llama-server` and exposes an OpenAI-compatible API; one or more **worker nodes**
run `ggml-rpc-server` and contribute their GPU/unified memory.

This lets you serve a model that does not fit in any single machine's memory by
sharding it across the cluster.

---

## 1. Requirements

- 2+ Apple Silicon Macs (M-series). More unified memory = larger models.
- Thunderbolt cables between them (best bandwidth), or any IP network.
- Xcode command line tools + CMake (`brew install cmake`).
- A model in GGUF format. Large models are typically **multi-shard**.

## 2. Topology

Use a **star**: every worker connects directly to the head node, and the head
node sits in the middle. Do not chain workers behind other workers — routed /
multi-hop RPC can deadlock (a worker two links away blocks in `recv()` waiting
for ACKs).

```
      worker-1 ──┐
                 ├── head node (llama-server, :8080 API)
      worker-2 ──┘
```

Give each Thunderbolt link its own point-to-point IP, or reach workers over your
LAN / a mesh VPN (e.g. Tailscale).

## 3. Build (every node)

```bash
cp .env.example .env      # edit paths/ports for your setup
./scripts/build-llama.sh
```

This clones and builds llama.cpp with `-DGGML_RPC=ON -DGGML_METAL=ON`.

## 4. Get the model onto the head node

Download your GGUF (all shards) to `MODEL_PATH`'s directory. **Never concatenate
shards.** Point `MODEL_PATH` at the *first* shard with its original name, e.g.
`...-00001-of-00006.gguf`. llama.cpp finds the rest by filename. Concatenating
produces a garbage header and every later error looks like a bogus "connection"
failure.

## 5. Start workers

On each worker, set `WORKER_*` in `.env`, then:

```bash
./scripts/start-worker.sh
```

It listens on `0.0.0.0:50052` by default over **TCP** (the safe transport).

## 6. Connect the head node to workers

Set `WORKER_ENDPOINTS` in `.env` to the addresses the head node uses to reach
each worker's RPC port, space-separated.

**Direct routing:**
```
WORKER_ENDPOINTS="10.0.0.2:50052 10.0.0.3:50052"
```

**Via SSH tunnels** (when workers aren't directly routable, or to sidestep the
macOS Local Network permission prompt — see Troubleshooting):
```bash
./scripts/tunnel-worker.sh 50052 worker-1        # -> 127.0.0.1:50052
./scripts/tunnel-worker.sh 50053 worker-2 50052  # -> 127.0.0.1:50053
```
```
WORKER_ENDPOINTS="127.0.0.1:50052 127.0.0.1:50053"
```

## 7. Start the head node

```bash
./scripts/start-server.sh
```

A large sharded model cold-starts in several minutes. Verify it's actually
serving — a running process is not proof:

```bash
./scripts/healthcheck.sh                       # HTTP 200 + status:ok
curl http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"flash-next","messages":[{"role":"user","content":"hi"}]}'
```

## 8. Run at boot (optional)

Copy the templates in `systemd/launchd/`, replace `__USER__` and `__REPO_DIR__`,
drop them in `~/Library/LaunchAgents/`, and `launchctl load -w` them. Let
launchd be the *sole* lifecycle owner — don't also start processes by hand.

See `docs/OPERATIONS.md` for transport tradeoffs, warm-keeping, and debugging.
