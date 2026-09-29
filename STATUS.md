# Status

- Phase: maintenance
- Owner: Sean / clawSean
- Started: 2026-09-28
- Current: fast/extended snapshots, schema-versioned JSON, sustained trend/CSV,
  OpenClaw internals, disk/network/GPU/power/fault telemetry, and optional macmon
  sensors are implemented; syntax, snapshot, JSON, watch, and CSV smoke tests pass
  on an M3 Max; public at
  `https://github.com/clawSean/mac-health`
- Routine checks never query unified logs; capped forensic queries live behind the
  separate root-only `mac-health-fault-history` command and are never scheduled.
- Next: wire the JSON contract into WatchCatfish's planned `/health system` surface;
  maintain thresholds and powermetrics parsing as macOS changes
