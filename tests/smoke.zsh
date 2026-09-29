#!/bin/zsh

set -eu

ROOT="${0:A:h:h}"
zsh -n "$ROOT/lib/metrics.zsh" "$ROOT/bin/mac-health" "$ROOT/bin/mac-health-watch" "$ROOT/bin/mac-health-fault-history"

validate_json() {
  local json_path="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$json_path" >/dev/null
  elif command -v node >/dev/null 2>&1; then
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$json_path"
  else
    plutil -extract schemaVersion raw -o - "$json_path" >/dev/null
  fi
}

snapshot="$($ROOT/bin/mac-health)"

for needle in \
  'Mac health snapshot' \
  'CPU' \
  'Memory' \
  'Swap' \
  'Battery' \
  'Thermals' \
  'Sensors' \
  'Power/clocks' \
  'GPU' \
  'Network' \
  'OpenClaw' \
  'Assessment' \
  'Top CPU processes'; do
  if [[ "$snapshot" != *"$needle"* ]]; then
    print -u2 -- "missing expected output: $needle"
    exit 1
  fi
done

json_file="$(mktemp "${TMPDIR:-/tmp}/mac-health-json.XXXXXX")"
csv_file="$(mktemp "${TMPDIR:-/tmp}/mac-health-csv.XXXXXX")"
trap 'rm -f -- "$json_file" "$csv_file"' EXIT

$ROOT/bin/mac-health --json > "$json_file"
validate_json "$json_file"
[[ "$(plutil -extract schemaVersion raw -o - "$json_file")" == "1" ]]
[[ "$(plutil -extract extended raw -o - "$json_file")" == "false" ]]
plutil -extract openclaw.gateway.fileDescriptors raw -o - "$json_file" >/dev/null
plutil -extract thermal.cpuTemperatureC raw -o - "$json_file" >/dev/null
plutil -extract sensors.powerWatts.gpu raw -o - "$json_file" >/dev/null

$ROOT/bin/mac-health --extended --json > "$json_file"
validate_json "$json_file"
[[ "$(plutil -extract extended raw -o - "$json_file")" == "true" ]]
plutil -extract disk.sample.transfersPerSec raw -o - "$json_file" >/dev/null
plutil -extract openclaw.sqlite.queryOk raw -o - "$json_file" >/dev/null
[[ "$(plutil -extract recentFaults.unifiedLogStatus raw -o - "$json_file")" == "not-requested" ]]

fault_help="$($ROOT/bin/mac-health-fault-history --help)"
[[ "$fault_help" == *'Forensic-only'* ]]
[[ "$fault_help" == *'never called by mac-health'* ]]

watch_output="$($ROOT/bin/mac-health-watch --interval 1 --samples 2 --csv "$csv_file")"
[[ "$watch_output" == *'Watch summary'* ]]
if [[ "$watch_output" != *'[OK]'* && "$watch_output" != *'[INFO]'* && "$watch_output" != *'[WARN]'* ]]; then
  print -u2 -- "watch output did not contain a terminal assessment"
  exit 1
fi
[[ "$(wc -l < "$csv_file" | tr -d ' ')" == "3" ]]
[[ "$(awk -F, 'NR==1 {print NF}' "$csv_file")" == "21" ]]
[[ "$(awk -F, 'NR==2 {print NF}' "$csv_file")" == "21" ]]

print -- "smoke: PASS"
