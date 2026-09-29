# mac-health

![macOS](https://img.shields.io/badge/macOS-Apple_Silicon-000000?logo=apple)
![Zsh](https://img.shields.io/badge/shell-zsh-1A2C34?logo=gnu-bash)
![License](https://img.shields.io/badge/license-MIT-blue)

Native macOS health and throttling diagnostics for Apple silicon. The core path
uses built-in tools; optional `macmon` sensors add exact temperatures without a
background service.

## What it checks

- CPU utilization, load averages, core-normalized scheduling pressure, and top processes
- macOS thermal and performance warnings plus optional CPU/GPU temperatures,
  fans, clocks, utilization, and power from `macmon`
- Memory pressure, compression, pageouts, swap use, and swapout growth
- Battery temperature, power flow, adapter wattage, charge state, and cycle count
- Startup-disk headroom/SMART status, current I/O throughput, and transfer rate
- GPU utilization/memory plus optional privileged GPU/ANE power telemetry
- Active-interface counters, DNS/LAN/Tailscale health, and throughput trends
- OpenClaw Gateway CPU/RAM/threads/file descriptors, task queues, health latency,
  delivery failures, log growth, and SQLite/WAL health
- Recent panic/reboot reports, hangs, sleep/wake failures, thermal shutdowns,
  and storage-I/O log evidence when macOS grants log access
- Low Power Mode, stuck-process counts, uptime, and top CPU processes

## Run it

```bash
./bin/mac-health
```

Add the slower one-second disk sample, network path checks, OpenClaw internals,
and recent fault history:

```bash
./bin/mac-health --extended
```

Emit stable schema-versioned JSON for WatchCatfish or other automation:

```bash
./bin/mac-health --extended --json
```

For CPU/GPU/ANE power, frequency, power limits, per-process I/O, and a second
thermal-pressure view, request a one-second privileged sample:

```bash
./bin/mac-health --privileged
```

Watch for sustained pressure for about one minute. The trend includes disk and
network throughput, GPU pressure, OpenClaw Gateway load/log growth, pageouts,
swapouts, and packet-error growth:

```bash
./bin/mac-health-watch
```

Or choose the interval/sample count and save a CSV:

```bash
./bin/mac-health-watch --interval 10 --samples 30 --csv health.csv
```

## Optional sensors

Install [`macmon`](https://github.com/vladkens/macmon) to add average CPU/GPU
temperatures, fan RPM, clocks, activity, and power. `mac-health` discovers it on
`PATH` and remains fully usable when it is absent. It does not install a daemon
or run in the background.

## Reading the result

- **Thermal/performance warning:** direct evidence macOS has entered a constrained state.
- **High CPU or load:** the machine is busy; it does not by itself prove thermal throttling.
- **Low Power Mode:** intentional performance limiting, not heat-driven throttling.
- **Swap use:** historical swap is normal; rising swapouts during a watch window are more useful.
- **Disk I/O:** throughput and transfer rate reveal active pressure. Apple's native
  unprivileged `iostat` does not expose latency or per-process attribution.
- **OpenClaw:** active/queued work and SQLite/WAL state are current signals;
  delivery/task failure totals are historical counters and do not alone mean it is unhealthy now.
- **Gateway CPU:** process CPU may exceed `100%` because macOS reports `100%` per busy core.
- **Battery temperature:** under `35°C` is comfortable, `40–45°C` deserves attention if sustained,
  and above `45°C` is flagged critical by this tool.

The built-in tools do not expose exact CPU/GPU die temperatures on this machine.
When `macmon` is available, the script adds its average CPU/GPU sensor readings;
the authoritative macOS thermal state remains the primary throttling signal.

Recent unified-log searches may report `permission-denied` when the calling shell
lacks sufficient access. That is reported as unavailable—not silently converted
to zero events. No background log scanner is installed.

## Requirements

- macOS on Apple silicon
- `/bin/zsh` and built-in macOS tools (`top`, `pmset`, `ioreg`, `iostat`, `netstat`,
  `memory_pressure`, `vm_stat`, `sysctl`, and optionally `powermetrics`)
- OpenClaw and Tailscale checks automatically degrade to unavailable when those
  programs are not installed
- Optional sensor telemetry: `macmon` on `PATH`

## Test

```bash
./tests/smoke.zsh
```

## Safety

The default and `--extended` paths are read-only and unprivileged. `--privileged`
uses `sudo` only for one `powermetrics` sample and does not change configuration.
Automation should use the noninteractive `--json` path; `--json --privileged` is
intentionally rejected.

## License

MIT
