# Transport: TCP vs RDMA

This cluster's inter-node RPC can run over **either** transport. Neither is "the
real one" — they are two supported configurations with different performance and
reliability profiles. Pick based on your physical topology and uptime needs.

TL;DR:

| | **TCP** | **RDMA (over Thunderbolt)** |
|---|---|---|
| Setup difficulty | Low — works over any IP path, incl. SSH tunnels | High — needs direct TB links + correct interfaces |
| Latency per RPC | Higher (kernel stack + copies) | Lower (kernel-bypass, zero-copy) |
| Host CPU cost | Higher (packet processing) | Lower (offloaded to the fabric) |
| Tolerates routed / tunneled / multi-hop paths | **Yes** | **No** — direct links only |
| Failure mode | Recovers cleanly on teardown | Can wedge a worker at 100% CPU until reboot |
| Best for | Always-on serving, imperfect cabling, remote workers | Benchmarked max throughput on a clean direct-link star |

**How much does the transport actually matter?** For large-model sharded
inference the answer is usually "less than you'd think." Weights stay resident on
each node; only per-layer **activation tensors** cross the wire each token. The
dominant cost is the GPU doing matmuls against the resident weights, which is
identical under either transport. On a memory-bandwidth-bound workload the
measured TCP→RDMA gain is often low single-digit percent on tokens/sec. RDMA
helps most when the interconnect is genuinely the bottleneck (very fast GPUs,
small models, high concurrency, or many shard boundaries per token).

Measure your own workload before optimizing the transport — see
[Benchmarking](#benchmarking) below.

---

## TCP (default)

The safe, portable default. Set `USE_RDMA=0` in `.env` (this exports
`GGML_RPC_NO_RDMA=1` for the worker/server processes).

- Works over **any IP path**: direct Ethernet/Thunderbolt-IP, your LAN, a mesh
  VPN (e.g. Tailscale), or **SSH tunnels** (see `scripts/tunnel-worker.sh`).
- Survives an unclean head-node teardown — workers don't wedge; just restart the
  head node.
- Tolerates routed and multi-hop paths, so workers don't all need a direct cable
  to the head node.

`--rpc` on the head node points at whatever address reaches each worker's RPC
port. With tunnels that's a set of loopback ports:

```
WORKER_ENDPOINTS="127.0.0.1:50052 127.0.0.1:50053"
```

With direct IP addressing it's the workers' interface IPs:

```
WORKER_ENDPOINTS="10.0.0.2:50052 10.0.0.3:50052"
```

This is the correct choice for a permanently-running service, for clusters whose
Thunderbolt cabling isn't a clean direct star, or when a worker is only reachable
over a VPN. **You cannot run RDMA over an SSH tunnel or a routed/VPN path** — if
any worker is reached that way, that worker must use TCP.

## RDMA (over Thunderbolt)

Lower latency and lower host-CPU cost, at the price of a strict physical
requirement and a nastier failure mode. Set `USE_RDMA=1` in `.env` and set
`RDMA_DEVICE` to the Thunderbolt interface on multi-port workers.

**Hard requirements — all of them:**

1. **Direct-link star topology.** Every worker has its **own** Thunderbolt cable
   running **directly to the head node**. No daisy-chaining workers behind other
   workers, no going through a hub, no IP router in the path. RDMA deadlocks on
   multi-hop paths — a worker two links away blocks in `recv()` waiting for ACKs
   that never arrive.
2. **The head node must have a Thunderbolt interface per worker.** On Apple
   Silicon this means enough physical TB ports on the head node to give each
   worker a dedicated direct cable. A head node with no TB-IP interface cannot
   originate RDMA.
3. **`--rpc` points at the real RDMA-capable interface addresses**, not loopback
   tunnel ports. Assign each direct TB link its own point-to-point IP (e.g.
   `169.254.x.y` link-local or a static `/30` per link) and target those.
4. **No SSH tunnels, no VPN, no NAT** anywhere in the RPC path.

**Failure mode to plan for:** after an abrupt head-node teardown, an RDMA worker
can peg one CPU core at 100% (0 memory movement) and stay stuck **until the
machine is rebooted**. Always restart/reboot workers after any unclean shutdown.
For an unattended service this is the single biggest argument for TCP.

**Verifying the topology before you trust it:** an "active" Thunderbolt interface
does **not** prove it links the two hosts you think it does — a live cable can
connect a different machine. Compare peer domain UUIDs against each host's own
local domain UUIDs:

```bash
system_profiler SPThunderboltDataType -json    # inspect Domain UUID + peer Device Name on each host
```

Only when host A's peer UUID matches host B's local UUID (and vice-versa) is that
cable a genuine A↔B direct link. Stale static IPs on an interface tell you nothing
about the current physical wiring.

---

## Benchmarking

Get a real number for your hardware instead of guessing. The head-node server
reports per-request timings; hit it and read `timings.predicted_per_second`
(generation tokens/sec) and `timings.prompt_per_second` (prefill):

```bash
curl -sS http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"YOUR_ALIAS","messages":[{"role":"user","content":"Write ~400 words about anything."}],"max_tokens":512,"stream":false}' \
  | python3 -c 'import sys,json; t=json.load(sys.stdin)["timings"]; print("gen %.2f tok/s (%.1f ms/tok) | prefill %.2f tok/s" % (t["predicted_per_second"], t["predicted_per_token_ms"], t["prompt_per_second"]))'
```

Method:

1. Warm the model first (one throwaway completion) so weights are resident.
2. Run 3–5 completions at a fixed `max_tokens` and average — a single sample is
   noise.
3. Switch transport (`USE_RDMA`), restart workers **and** the head node, cold-start
   the model, warm again, repeat.
4. Compare generation tok/s and, if you care about interactivity, ms/token.

Because a large sharded model cold-starts in minutes and an RDMA misconfig can
wedge a worker, treat an RDMA benchmark as a **maintenance-window operation** on a
cluster you can physically reach, not a live production toggle.
