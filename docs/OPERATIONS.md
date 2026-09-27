# Operations & Troubleshooting

Hard-won lessons from running a sharded llama.cpp cluster on Apple Silicon.

## Transport: TCP vs RDMA

The scripts default to **TCP** (`GGML_RPC_NO_RDMA=1`). It is slower than RDMA but
does not fall over.

RDMA over Thunderbolt is faster but has two failure modes worth knowing before
you enable `USE_RDMA=1`:

- **Wedges after a dirty client teardown.** If the head node dies mid-request,
  workers can peg one CPU core at 100% with 0 memory movement and stay stuck
  until rebooted. Restart (or reboot) workers after any unclean shutdown.
- **Deadlocks on multi-hop topologies.** Only direct links between each worker
  and the head node work. Keep the star topology.

If you enable RDMA, use a direct-link star, set `RDMA_DEVICE` to the Thunderbolt
interface on multi-port workers, and be ready to reboot after crashes.

## Multi-shard models

Point `-m` / `MODEL_PATH` at shard **1** (`...00001-of-000NN.gguf`). Never
concatenate shards. If the model won't load and you see confusing connection
errors, check this first — a wrong header masquerades as a network problem.

## The model is a running process but the API is down

Diagnose before restarting anything:

1. `./scripts/healthcheck.sh` — HTTP 503 / "loading" is not ready; a bare TCP
   listener is not ready. Only 200 + `status:ok` counts.
2. Head-node log (default `/tmp/llama_server.log`). An abort with
   `Failed to connect to 127.0.0.1:PORT` points at a dead worker tunnel, not the
   weights.
3. Confirm each worker is actually **listening**, from the worker itself:
   ```bash
   lsof -a -c ggml-rpc-server -iTCP:50052 -sTCP:LISTEN
   ```
   Prefer this over opening a dummy RPC client — a worker busy with a live client
   can have a full listen backlog and make external probes lie.
4. A running SSH PID is **not** proof of a live tunnel. Check the local forwarded
   port has a listener and that the path is bidirectionally reachable.

## macOS Local Network permission (silent failures)

macOS can silently deny "Local Network" access to *detached* background
processes — no prompt, no log — while the same binary launched inside an SSH
session connects fine. Two fixes:

- **Interim:** run the server from an SSH-held session (or a launchd job that has
  been granted the permission).
- **Clean:** wrap the binary in a `.app` bundle with `NSLocalNetworkUsageDescription`
  so macOS shows the one-time approval dialog.

## Cold-start / keep-warm

`llama-server` keeps weights resident for its whole process life (no idle
unload). The only cold window is the few minutes after a (re)start. If that
matters, add a small scheduled job that fires one tiny completion
(`max_tokens: 8`) after a restart. Make it idempotent — detect the server's
process start time and skip if the instance is unchanged. Do not build restart
or crash-loop logic into it; a warmer should never bounce the server.

## Deployment gotchas (shell)

- Deploy scripts/binaries with `scp`/`tar`-over-ssh, **not** nested heredocs over
  `ssh` — remote-shell quoting mangles them.
- In loops, use `ssh -n` so ssh doesn't steal stdin.
- Use `scp -o BatchMode=yes` so a missing key fails loudly instead of hanging on
  an invisible password prompt.

## Health monitoring

`scripts/healthcheck.sh` exits 0 only on 200 + `status:ok`. Wire it into cron /
launchd and alert on a *new* outage — dedupe so a long outage doesn't spam you,
and treat "loading" and repeated failures distinctly from recovery.
