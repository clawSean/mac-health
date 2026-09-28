# Log

## 2026-09-28

- Created the project floor and native zsh implementation.
- Added one-shot health reporting, sustained pressure sampling, CSV output, optional
  privileged `powermetrics`, thresholded findings, and a live smoke test.
- Corrected the privileged path for macOS 26's supported `thermal`, `cpu_power`, and
  `gpu_power` samplers; current built-in tools do not expose exact CPU/GPU die temperatures.
- Passed zsh syntax checks, live snapshot/watch checks, the two-sample smoke test, and
  three-row CSV proof on an M3 Max running macOS 26.6.1.
- Published the canonical project to `https://github.com/clawSean/mac-health`.
- Expanded the fast snapshot with compression/pageout, battery power/adapter,
  SMART, GPU, network-interface, and OpenClaw Gateway process telemetry.
- Added `--extended` disk I/O, DNS/LAN/Tailscale, OpenClaw health/task/SQLite,
  and recent panic/reboot/sleep/thermal/storage-event diagnostics.
- Added schema-versioned JSON for WatchCatfish, richer sustained trend/CSV output,
  and privileged GPU/ANE power plus per-process I/O sampling.
- Kept unavailable native signals honest: exact CPU/GPU die temperatures and
  unprivileged disk latency/per-process I/O remain explicitly unsupported.
