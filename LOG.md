# Log

## 2026-09-28

- Created the project floor and native zsh implementation.
- Added one-shot health reporting, sustained pressure sampling, CSV output, optional
  privileged `powermetrics`, thresholded findings, and a live smoke test.
- Corrected the privileged path for macOS 26's supported `thermal`, `cpu_power`, and
  `gpu_power` samplers; current built-in tools do not expose exact CPU/GPU die temperatures.
- Passed zsh syntax checks, live snapshot/watch checks, the two-sample smoke test, and
  three-row CSV proof on an M3 Max running macOS 26.6.1.
