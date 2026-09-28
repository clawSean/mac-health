# mac-health

![macOS](https://img.shields.io/badge/macOS-Apple_Silicon-000000?logo=apple)
![Zsh](https://img.shields.io/badge/shell-zsh-1A2C34?logo=gnu-bash)
![License](https://img.shields.io/badge/license-MIT-blue)

Native macOS health and throttling diagnostics for Apple silicon—no Homebrew
packages, agents, daemons, or background services required.

## What it checks

- CPU utilization, load averages, core-normalized scheduling pressure, and top processes
- macOS thermal and performance warnings (the strongest non-root throttling signal)
- Memory-pressure percentage, swap use, and swapout growth
- Battery temperature, charge state, and cycle count
- Startup-disk headroom, Low Power Mode, stuck-process counts, and uptime
- Optional privileged CPU/GPU frequency, power-limit, power, and thermal-pressure telemetry

## Run it

```bash
./bin/mac-health
```

For CPU/GPU frequency, power limits, and a second thermal-pressure view, request a
one-second privileged sample:

```bash
./bin/mac-health --privileged
```

Watch for sustained pressure for about one minute:

```bash
./bin/mac-health-watch
```

Or choose the interval/sample count and save a CSV:

```bash
./bin/mac-health-watch --interval 10 --samples 30 --csv health.csv
```

## Reading the result

- **Thermal/performance warning:** direct evidence macOS has entered a constrained state.
- **High CPU or load:** the machine is busy; it does not by itself prove thermal throttling.
- **Low Power Mode:** intentional performance limiting, not heat-driven throttling.
- **Swap use:** historical swap is normal; rising swapouts during a watch window are more useful.
- **Battery temperature:** under `35°C` is comfortable, `40–45°C` deserves attention if sustained,
  and above `45°C` is flagged critical by this tool.

The current macOS built-in tools do not expose exact CPU/GPU die temperatures on this
machine. The script reports the exact battery sensor temperature and macOS thermal state;
the privileged path adds clock, power-limit, power, and thermal-pressure telemetry. Those
signals and performance behavior over time are more diagnostic than one temperature.

## Requirements

- macOS on Apple silicon
- `/bin/zsh` and built-in macOS tools (`top`, `pmset`, `ioreg`, `memory_pressure`,
  `vm_stat`, `sysctl`, and optionally `powermetrics`)

## Test

```bash
./tests/smoke.zsh
```

## Safety

The default path is read-only and unprivileged. `--privileged` uses `sudo` only for a
single `powermetrics` sample and does not change configuration.

## License

MIT
