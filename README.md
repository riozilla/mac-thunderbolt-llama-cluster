# apple-rdma-llama-cluster

Serve large LLMs across multiple Apple Silicon Macs with
[llama.cpp](https://github.com/ggml-org/llama.cpp)'s RPC backend over
Thunderbolt. Pool the unified memory of several Macs to run models that don't fit
on any single machine — exposed as a single OpenAI-compatible API endpoint.

Built and battle-tested on a Mac Studio cluster. The personal bits (IPs,
hostnames, model paths) are pulled out into `.env`; the scripts are generic.

## What it does

- One **head node** runs `llama-server` and serves `http://host:8080/v1/...`.
- One or more **worker nodes** run `ggml-rpc-server` and lend their GPU + unified
  memory over the network.
- A large **multi-shard GGUF** is split across the cluster automatically.

```
      worker-1 ──┐
                 ├── head node ── OpenAI-compatible API :8080
      worker-2 ──┘
```

## Quick start

```bash
git clone https://github.com/<you>/apple-rdma-llama-cluster
cd apple-rdma-llama-cluster
cp .env.example .env          # edit for your machines

# on every node:
./scripts/build-llama.sh

# on each worker:
./scripts/start-worker.sh

# on the head node (after setting WORKER_ENDPOINTS in .env):
./scripts/start-server.sh
./scripts/healthcheck.sh
```

Full walkthrough in **[docs/SETUP.md](docs/SETUP.md)**.

## Why this exists (the non-obvious parts)

Running llama.cpp RPC across Macs works, but a few things will waste your
afternoon if you don't know them. They're baked into the scripts and written up
in **[docs/OPERATIONS.md](docs/OPERATIONS.md)**:

- **TCP by default.** RDMA over Thunderbolt is faster but wedges after a dirty
  client teardown (worker stuck at 100% CPU until reboot) and deadlocks on
  multi-hop topologies. TCP + a star topology is the reliable default.
- **Never concatenate multi-shard GGUFs.** Point at shard 1
  (`...00001-of-000NN.gguf`); llama.cpp finds the siblings. Concatenating loads a
  garbage header and every later error looks like a bogus network failure.
- **macOS silently denies Local Network to detached processes** — no prompt, no
  log. Run from an SSH-held session, or ship a `.app` bundle with
  `NSLocalNetworkUsageDescription`.
- **Verify it's actually serving**, not just running: `healthcheck.sh` accepts
  only HTTP 200 + `status:ok`.

## Layout

```
scripts/
  build-llama.sh      build llama.cpp w/ RPC + Metal (run on every node)
  start-worker.sh     run ggml-rpc-server on a worker
  start-server.sh     run llama-server on the head node
  tunnel-worker.sh    optional SSH port-forward for a worker's RPC port
  healthcheck.sh      probe the API (200 + status:ok only)
systemd/launchd/      launchd templates to run at boot
docs/                 SETUP.md, OPERATIONS.md
.env.example          all configuration (copy to .env)
```

## Requirements

Apple Silicon Macs, Thunderbolt (or any IP path between them), Xcode CLT +
`cmake`, and a GGUF model.

## License

MIT — see [LICENSE](LICENSE). Do whatever you want with it.
