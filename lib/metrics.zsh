#!/bin/zsh

# Shared, dependency-free metric collectors for Apple silicon Macs.

mh_float_lt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'; }
mh_float_gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }

mh_elapsed_ms() {
  local start="$1" end="$2"
  awk -v start="$start" -v end="$end" 'BEGIN { printf "%.1f", (end-start)*1000 }'
}

mh_json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  print -nr -- "$value"
}

mh_json_string() { print -nr -- "\"$(mh_json_escape "${1:-}")\""; }

mh_json_number() {
  local value="${1:-}"
  if [[ "$value" =~ '^-?[0-9]+([.][0-9]+)?$' ]]; then
    print -nr -- "$value"
  else
    print -nr -- "null"
  fi
}

mh_json_bool() {
  case "${1:-}" in
    true|Yes|yes|1) print -nr -- "true" ;;
    false|No|no|0) print -nr -- "false" ;;
    *) print -nr -- "null" ;;
  esac
}

mh_plutil_raw() {
  local file="$1" key="$2" fallback="${3:-unknown}" value
  value="$(plutil -extract "$key" raw -o - "$file" 2>/dev/null || true)"
  print -r -- "${value:-$fallback}"
}

mh_cpu_sample() {
  local top_output cpu_line load
  top_output="$(top -l 2 -n 0 2>/dev/null)"
  cpu_line="$(print -r -- "$top_output" | awk '/^CPU usage:/ { line=$0 } END { print line }')"
  MH_CPU_USER="$(print -r -- "$cpu_line" | sed -E 's/.*CPU usage: ([0-9.]+)% user.*/\1/')"
  MH_CPU_SYS="$(print -r -- "$cpu_line" | sed -E 's/.*user, ([0-9.]+)% sys.*/\1/')"
  MH_CPU_IDLE="$(print -r -- "$cpu_line" | sed -E 's/.*sys, ([0-9.]+)% idle.*/\1/')"
  MH_CPU_USER="${MH_CPU_USER:-0}"
  MH_CPU_SYS="${MH_CPU_SYS:-0}"
  MH_CPU_IDLE="${MH_CPU_IDLE:-100}"
  MH_CPU_BUSY="$(awk -v idle="$MH_CPU_IDLE" 'BEGIN { printf "%.1f", 100-idle }')"

  load="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}')"
  MH_LOAD_1="$(print -r -- "$load" | awk '{print $1}')"
  MH_LOAD_5="$(print -r -- "$load" | awk '{print $2}')"
  MH_LOAD_15="$(print -r -- "$load" | awk '{print $3}')"
  MH_LOGICAL_CORES="$(sysctl -n hw.logicalcpu 2>/dev/null || print 0)"
  MH_PHYSICAL_CORES="$(sysctl -n hw.physicalcpu 2>/dev/null || print 0)"
  MH_LOAD_PER_CORE="$(awk -v load="${MH_LOAD_1:-0}" -v cores="${MH_LOGICAL_CORES:-1}" 'BEGIN { if (cores < 1) cores=1; printf "%.2f", load/cores }')"
  MH_PROCESS_LINE="$(print -r -- "$top_output" | awk '/^Processes:/ { line=$0 } END { print line }')"
  MH_STUCK_PROCESSES="$(print -r -- "$MH_PROCESS_LINE" | sed -nE 's/.* ([0-9]+) stuck.*/\1/p')"
  MH_STUCK_PROCESSES="${MH_STUCK_PROCESSES:-0}"
}

mh_memory_sample() {
  local pressure swap vm mem_bytes compressed_pages
  pressure="$(memory_pressure -Q 2>/dev/null)"
  MH_MEMORY_FREE_PCT="$(print -r -- "$pressure" | awk -F': ' '/System-wide memory free percentage:/ {gsub(/%/,"",$2); print $2}')"
  MH_MEMORY_FREE_PCT="${MH_MEMORY_FREE_PCT:-0}"
  swap="$(sysctl vm.swapusage 2>/dev/null)"
  MH_SWAP_TOTAL_MB="$(print -r -- "$swap" | sed -nE 's/.*total = ([0-9.]+)M.*/\1/p')"
  MH_SWAP_USED_MB="$(print -r -- "$swap" | sed -nE 's/.*used = ([0-9.]+)M.*/\1/p')"
  MH_SWAP_TOTAL_MB="${MH_SWAP_TOTAL_MB:-0}"
  MH_SWAP_USED_MB="${MH_SWAP_USED_MB:-0}"

  vm="$(vm_stat 2>/dev/null)"
  MH_PAGE_SIZE="$(print -r -- "$vm" | awk 'NR==1 {gsub(/[^0-9]/,"",$8); print $8}')"
  MH_PAGE_SIZE="${MH_PAGE_SIZE:-4096}"
  MH_PAGEINS="$(print -r -- "$vm" | awk -F': ' '/Pageins:/ {gsub(/[^0-9]/,"",$2); print $2}')"
  MH_PAGEOUTS="$(print -r -- "$vm" | awk -F': ' '/Pageouts:/ {gsub(/[^0-9]/,"",$2); print $2}')"
  MH_SWAPINS="$(print -r -- "$vm" | awk -F': ' '/Swapins:/ {gsub(/[^0-9]/,"",$2); print $2}')"
  MH_SWAPOUTS="$(print -r -- "$vm" | awk -F': ' '/Swapouts:/ {gsub(/[^0-9]/,"",$2); print $2}')"
  MH_PAGEINS="${MH_PAGEINS:-0}"
  MH_PAGEOUTS="${MH_PAGEOUTS:-0}"
  MH_SWAPINS="${MH_SWAPINS:-0}"
  MH_SWAPOUTS="${MH_SWAPOUTS:-0}"
  compressed_pages="$(print -r -- "$vm" | awk -F': ' '/Pages occupied by compressor:/ {gsub(/[^0-9]/,"",$2); print $2}')"
  compressed_pages="${compressed_pages:-0}"
  MH_MEMORY_COMPRESSED_MB="$(awk -v pages="$compressed_pages" -v size="$MH_PAGE_SIZE" 'BEGIN { printf "%.0f", pages*size/1048576 }')"
  mem_bytes="$(sysctl -n hw.memsize 2>/dev/null || print 0)"
  MH_MEMORY_TOTAL_GB="$(awk -v bytes="$mem_bytes" 'BEGIN { printf "%.0f", bytes/1073741824 }')"
}

mh_battery_sample() {
  local batt power raw_temp adapter_line
  batt="$(ioreg -r -c AppleSmartBattery -d 1 2>/dev/null)"
  power="$(pmset -g batt 2>/dev/null)"
  MH_BATTERY_PCT="$(print -r -- "$power" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')"
  MH_BATTERY_PCT="${MH_BATTERY_PCT:-unknown}"
  MH_BATTERY_STATE="$(print -r -- "$power" | awk -F';' 'NR==2 {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
  MH_BATTERY_STATE="${MH_BATTERY_STATE:-unknown}"
  raw_temp="$(print -r -- "$batt" | awk -F'= ' '/^[[:space:]]+"Temperature" =/ {print $2; exit}')"
  if [[ -n "$raw_temp" ]]; then
    MH_BATTERY_TEMP_C="$(awk -v raw="$raw_temp" 'BEGIN {printf "%.1f", raw/100}')"
    MH_BATTERY_TEMP_F="$(awk -v c="$MH_BATTERY_TEMP_C" 'BEGIN {printf "%.0f", c*9/5+32}')"
  else
    MH_BATTERY_TEMP_C="unknown"
    MH_BATTERY_TEMP_F="unknown"
  fi
  MH_CYCLE_COUNT="$(print -r -- "$batt" | awk -F'= ' '/^[[:space:]]+"CycleCount" =/ {print $2; exit}')"
  MH_CYCLE_COUNT="${MH_CYCLE_COUNT:-unknown}"
  MH_CHARGING="$(print -r -- "$batt" | awk -F'= ' '/^[[:space:]]+"IsCharging" =/ {print $2; exit}')"
  MH_EXTERNAL_POWER="$(print -r -- "$batt" | awk -F'= ' '/^[[:space:]]+"ExternalConnected" =/ {print $2; exit}')"
  MH_BATTERY_VOLTAGE_MV="$(print -r -- "$batt" | awk -F'= ' '/^[[:space:]]+"Voltage" =/ {print $2; exit}')"
  MH_BATTERY_CURRENT_MA="$(print -r -- "$batt" | awk -F'= ' '/^[[:space:]]+"InstantAmperage" =/ {print $2; exit}')"
  MH_BATTERY_VOLTAGE_MV="${MH_BATTERY_VOLTAGE_MV:-unknown}"
  MH_BATTERY_CURRENT_MA="${MH_BATTERY_CURRENT_MA:-unknown}"
  if [[ "$MH_BATTERY_VOLTAGE_MV" == <-> ]] && [[ "$MH_BATTERY_CURRENT_MA" == -<-> || "$MH_BATTERY_CURRENT_MA" == <-> ]]; then
    MH_BATTERY_WATTS="$(awk -v v="$MH_BATTERY_VOLTAGE_MV" -v a="$MH_BATTERY_CURRENT_MA" 'BEGIN { printf "%.1f", v*a/1000000 }')"
  else
    MH_BATTERY_WATTS="unknown"
  fi
  adapter_line="$(print -r -- "$batt" | grep -m1 '"AdapterDetails"' || true)"
  MH_ADAPTER_WATTS="$(print -r -- "$adapter_line" | sed -nE 's/.*"Watts"=([0-9]+).*/\1/p')"
  MH_ADAPTER_WATTS="${MH_ADAPTER_WATTS:-unknown}"
}

mh_thermal_sample() {
  MH_THERMAL_TEXT="$(pmset -g therm 2>/dev/null)"
  if print -r -- "$MH_THERMAL_TEXT" | grep -q 'No thermal warning level'; then MH_THERMAL_STATE="clear"; else MH_THERMAL_STATE="warning"; fi
  if print -r -- "$MH_THERMAL_TEXT" | grep -q 'No performance warning level'; then MH_PERFORMANCE_STATE="clear"; else MH_PERFORMANCE_STATE="warning"; fi
  MH_LOW_POWER_MODE="$(pmset -g custom 2>/dev/null | awk '/lowpowermode/ {print $2; exit}')"
  MH_LOW_POWER_MODE="${MH_LOW_POWER_MODE:-0}"
}

mh_disk_sample() {
  local disk disk_info
  disk="$(df -k / 2>/dev/null | tail -1)"
  MH_DISK_FREE_GB="$(print -r -- "$disk" | awk '{printf "%.1f", $4/1048576}')"
  MH_DISK_USED_PCT="$(print -r -- "$disk" | awk '{gsub(/%/,"",$5); print $5}')"
  MH_DISK_FREE_PCT="$(awk -v used="${MH_DISK_USED_PCT:-100}" 'BEGIN {printf "%.0f", 100-used}')"
  disk_info="$(diskutil info / 2>/dev/null || true)"
  MH_DISK_SMART="$(print -r -- "$disk_info" | awk -F': ' '/SMART Status:/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}')"
  MH_DISK_SMART="${MH_DISK_SMART:-unavailable}"
  MH_DISK_SOLID_STATE="$(print -r -- "$disk_info" | awk -F': ' '/Solid State:/ {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2; exit}')"
  MH_DISK_SOLID_STATE="${MH_DISK_SOLID_STATE:-unknown}"
}

mh_disk_counter_sample() {
  local output row
  output="$(iostat -Id -c 1 2>/dev/null || true)"
  MH_DISK_DEVICE="$(print -r -- "$output" | awk 'NF==1 && $1 ~ /^disk/ {print $1; exit}')"
  row="$(print -r -- "$output" | awk 'NF==3 && $1 ~ /^[0-9.]+$/ {line=$0} END {print line}')"
  MH_DISK_TOTAL_XFERS="$(print -r -- "$row" | awk '{print $2}')"
  MH_DISK_TOTAL_MB="$(print -r -- "$row" | awk '{print $3}')"
  MH_DISK_DEVICE="${MH_DISK_DEVICE:-unknown}"
  MH_DISK_TOTAL_XFERS="${MH_DISK_TOTAL_XFERS:-0}"
  MH_DISK_TOTAL_MB="${MH_DISK_TOTAL_MB:-0}"
}

mh_disk_io_sample() {
  local output row
  output="$(iostat -Id -c 2 -w 1 2>/dev/null || true)"
  MH_DISK_IO_DEVICE="$(print -r -- "$output" | awk 'NF==1 && $1 ~ /^disk/ {print $1; exit}')"
  row="$(print -r -- "$output" | awk 'NF==3 && $1 ~ /^[0-9.]+$/ {line=$0} END {print line}')"
  MH_DISK_KB_PER_TRANSFER="$(print -r -- "$row" | awk '{print $1}')"
  MH_DISK_TRANSFERS_PER_SEC="$(print -r -- "$row" | awk '{print $2}')"
  MH_DISK_MB_PER_SEC="$(print -r -- "$row" | awk '{print $3}')"
  MH_DISK_IO_DEVICE="${MH_DISK_IO_DEVICE:-unknown}"
  MH_DISK_KB_PER_TRANSFER="${MH_DISK_KB_PER_TRANSFER:-unknown}"
  MH_DISK_TRANSFERS_PER_SEC="${MH_DISK_TRANSFERS_PER_SEC:-unknown}"
  MH_DISK_MB_PER_SEC="${MH_DISK_MB_PER_SEC:-unknown}"
  MH_DISK_LATENCY_MS="unavailable"
}

mh_gpu_sample() {
  local gpu_line gpu_bytes
  gpu_line="$(ioreg -l -w 0 2>/dev/null | grep -m1 '"PerformanceStatistics"' || true)"
  MH_GPU_DEVICE_UTIL_PCT="$(print -r -- "$gpu_line" | sed -nE 's/.*"Device Utilization %"=([0-9]+).*/\1/p')"
  MH_GPU_RENDERER_UTIL_PCT="$(print -r -- "$gpu_line" | sed -nE 's/.*"Renderer Utilization %"=([0-9]+).*/\1/p')"
  MH_GPU_TILER_UTIL_PCT="$(print -r -- "$gpu_line" | sed -nE 's/.*"Tiler Utilization %"=([0-9]+).*/\1/p')"
  gpu_bytes="$(print -r -- "$gpu_line" | sed -nE 's/.*"In use system memory"=([0-9]+).*/\1/p')"
  MH_GPU_MEMORY_MB="$(awk -v bytes="${gpu_bytes:-0}" 'BEGIN {printf "%.0f", bytes/1048576}')"
  MH_GPU_DEVICE_UTIL_PCT="${MH_GPU_DEVICE_UTIL_PCT:-unknown}"
  MH_GPU_RENDERER_UTIL_PCT="${MH_GPU_RENDERER_UTIL_PCT:-unknown}"
  MH_GPU_TILER_UTIL_PCT="${MH_GPU_TILER_UTIL_PCT:-unknown}"
}

mh_sensor_defaults() {
  MH_SENSOR_SOURCE="unavailable"
  MH_CPU_TEMP_C="unknown"
  MH_GPU_TEMP_C="unknown"
  MH_FAN0_RPM="unknown"
  MH_FAN0_MAX_RPM="unknown"
  MH_FAN1_RPM="unknown"
  MH_FAN1_MAX_RPM="unknown"
  MH_CPU_POWER_W="unknown"
  MH_GPU_POWER_W="unknown"
  MH_ANE_POWER_W="unknown"
  MH_SOC_POWER_W="unknown"
  MH_SYSTEM_POWER_W="unknown"
  MH_ECPU_FREQ_MHZ="unknown"
  MH_PCPU_FREQ_MHZ="unknown"
  MH_GPU_FREQ_MHZ="unknown"
  MH_CPU_ACTIVE_PCT="unknown"
  MH_GPU_ACTIVE_PCT="unknown"
  MH_SENSOR_TEMP_FILE=""
  MH_SENSOR_PID=""
}

mh_sensor_start() {
  mh_sensor_defaults
  local macmon_bin
  macmon_bin="$(command -v macmon 2>/dev/null || true)"
  if [[ -x "$macmon_bin" ]]; then
    MH_SENSOR_TEMP_FILE="$(mktemp "${TMPDIR:-/tmp}/mac-health-sensors.XXXXXX")"
    "$macmon_bin" pipe --samples 1 --interval 100 >"$MH_SENSOR_TEMP_FILE" 2>/dev/null &
    MH_SENSOR_PID=$!
  fi
}

mh_sensor_finish() {
  [[ -n "$MH_SENSOR_PID" && -n "$MH_SENSOR_TEMP_FILE" ]] || return 0
  if wait "$MH_SENSOR_PID" 2>/dev/null && [[ -s "$MH_SENSOR_TEMP_FILE" ]]; then
    MH_SENSOR_SOURCE="macmon"
    MH_CPU_TEMP_C="$(awk -v v="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" temp.cpu_temp_avg unknown)" 'BEGIN {if(v=="unknown")print v; else printf "%.1f",v}')"
    MH_GPU_TEMP_C="$(awk -v v="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" temp.gpu_temp_avg unknown)" 'BEGIN {if(v=="unknown")print v; else printf "%.1f",v}')"
    MH_FAN0_RPM="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" fans.0.rpm unknown)"
    MH_FAN0_MAX_RPM="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" fans.0.max_rpm unknown)"
    MH_FAN1_RPM="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" fans.1.rpm unknown)"
    MH_FAN1_MAX_RPM="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" fans.1.max_rpm unknown)"
    MH_CPU_POWER_W="$(awk -v v="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" cpu_power unknown)" 'BEGIN {if(v=="unknown")print v; else printf "%.1f",v}')"
    MH_GPU_POWER_W="$(awk -v v="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" gpu_power unknown)" 'BEGIN {if(v=="unknown")print v; else printf "%.1f",v}')"
    MH_ANE_POWER_W="$(awk -v v="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" ane_power unknown)" 'BEGIN {if(v=="unknown")print v; else printf "%.1f",v}')"
    MH_SOC_POWER_W="$(awk -v v="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" all_power unknown)" 'BEGIN {if(v=="unknown")print v; else printf "%.1f",v}')"
    MH_SYSTEM_POWER_W="$(awk -v v="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" sys_power unknown)" 'BEGIN {if(v=="unknown")print v; else printf "%.1f",v}')"
    MH_ECPU_FREQ_MHZ="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" ecpu_freq_mhz unknown)"
    MH_PCPU_FREQ_MHZ="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" pcpu_freq_mhz unknown)"
    MH_GPU_FREQ_MHZ="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" gpu_freq_mhz unknown)"
    MH_CPU_ACTIVE_PCT="$(awk -v v="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" cpu_active_ratio unknown)" 'BEGIN {if(v=="unknown")print v; else printf "%.1f",v*100}')"
    MH_GPU_ACTIVE_PCT="$(awk -v v="$(mh_plutil_raw "$MH_SENSOR_TEMP_FILE" gpu_active_ratio unknown)" 'BEGIN {if(v=="unknown")print v; else printf "%.1f",v*100}')"
  fi
  rm -f -- "$MH_SENSOR_TEMP_FILE"
  MH_SENSOR_TEMP_FILE=""
  MH_SENSOR_PID=""
}

mh_network_counter_sample() {
  local route row
  route="$(route -n get default 2>/dev/null || true)"
  MH_NETWORK_INTERFACE="$(print -r -- "$route" | awk '/interface:/ {print $2; exit}')"
  MH_LAN_GATEWAY="$(print -r -- "$route" | awk '/gateway:/ {print $2; exit}')"
  MH_NETWORK_INTERFACE="${MH_NETWORK_INTERFACE:-unknown}"
  MH_LAN_GATEWAY="${MH_LAN_GATEWAY:-unknown}"
  if [[ "$MH_NETWORK_INTERFACE" != "unknown" ]]; then
    row="$(netstat -ibdn 2>/dev/null | awk -v iface="$MH_NETWORK_INTERFACE" '$1==iface && $3 ~ /^<Link#/ {print; exit}')"
  else
    row=""
  fi
  MH_NETWORK_RX_PACKETS="$(print -r -- "$row" | awk '{print $5}')"
  MH_NETWORK_RX_ERRORS="$(print -r -- "$row" | awk '{print $6}')"
  MH_NETWORK_RX_BYTES="$(print -r -- "$row" | awk '{print $7}')"
  MH_NETWORK_TX_PACKETS="$(print -r -- "$row" | awk '{print $8}')"
  MH_NETWORK_TX_ERRORS="$(print -r -- "$row" | awk '{print $9}')"
  MH_NETWORK_TX_BYTES="$(print -r -- "$row" | awk '{print $10}')"
  MH_NETWORK_DROPS="$(print -r -- "$row" | awk '{print $12}')"
  MH_NETWORK_RX_PACKETS="${MH_NETWORK_RX_PACKETS:-0}"
  MH_NETWORK_RX_ERRORS="${MH_NETWORK_RX_ERRORS:-0}"
  MH_NETWORK_RX_BYTES="${MH_NETWORK_RX_BYTES:-0}"
  MH_NETWORK_TX_PACKETS="${MH_NETWORK_TX_PACKETS:-0}"
  MH_NETWORK_TX_ERRORS="${MH_NETWORK_TX_ERRORS:-0}"
  MH_NETWORK_TX_BYTES="${MH_NETWORK_TX_BYTES:-0}"
  MH_NETWORK_DROPS="${MH_NETWORK_DROPS:-0}"
}

mh_network_probe_sample() {
  zmodload zsh/datetime
  local start end dns_output ping_output ts_output online_count self_online
  start="$EPOCHREALTIME"
  dns_output="$(dscacheutil -q host -a name github.com 2>/dev/null || true)"
  end="$EPOCHREALTIME"
  MH_DNS_LATENCY_MS="$(mh_elapsed_ms "$start" "$end")"
  [[ -n "$dns_output" ]] && MH_DNS_OK="true" || MH_DNS_OK="false"
  if [[ "$MH_LAN_GATEWAY" != "unknown" ]]; then
    ping_output="$(ping -c 1 -W 1000 "$MH_LAN_GATEWAY" 2>/dev/null || true)"
    MH_LAN_GATEWAY_RTT_MS="$(print -r -- "$ping_output" | sed -nE 's/.*time[=<]([0-9.]+) ms.*/\1/p' | head -1)"
  else
    MH_LAN_GATEWAY_RTT_MS="unknown"
  fi
  MH_LAN_GATEWAY_RTT_MS="${MH_LAN_GATEWAY_RTT_MS:-unreachable}"
  if command -v tailscale >/dev/null 2>&1; then
    ts_output="$(tailscale status --json 2>/dev/null || true)"
    MH_TAILSCALE_BACKEND="$(print -r -- "$ts_output" | sed -nE 's/.*"BackendState"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)"
    online_count="$(print -r -- "$ts_output" | grep -c '"Online"[[:space:]]*:[[:space:]]*true' || true)"
    self_online="$(print -r -- "$ts_output" | awk '/"Self"[[:space:]]*:/ {inside=1} inside && /"Online"[[:space:]]*:[[:space:]]*true/ {print 1; exit}')"
    if [[ "$online_count" == <-> ]]; then
      (( ${self_online:-0} > 0 && online_count > 0 )) && (( online_count-- ))
      MH_TAILSCALE_ONLINE_PEERS="$online_count"
    else
      MH_TAILSCALE_ONLINE_PEERS="unknown"
    fi
    MH_TAILSCALE_BACKEND="${MH_TAILSCALE_BACKEND:-unknown}"
  else
    MH_TAILSCALE_BACKEND="not-installed"
    MH_TAILSCALE_ONLINE_PEERS="unknown"
  fi
}

mh_openclaw_process_sample() {
  local port="${MH_OPENCLAW_PORT:-18789}" pid log_dir rss_kb
  MH_OC_AVAILABLE="false"
  MH_OC_GATEWAY_PID="unknown"
  MH_OC_GATEWAY_CPU_PCT="unknown"
  MH_OC_GATEWAY_CPU_CORES="unknown"
  MH_OC_GATEWAY_MEMORY_PCT="unknown"
  MH_OC_GATEWAY_RSS_MB="unknown"
  MH_OC_GATEWAY_THREADS="unknown"
  MH_OC_GATEWAY_FDS="unknown"
  MH_OC_GATEWAY_UPTIME="unknown"
  command -v openclaw >/dev/null 2>&1 && MH_OC_AVAILABLE="true"
  pid="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1)"
  if [[ "$pid" == <-> ]]; then
    MH_OC_GATEWAY_PID="$pid"
    MH_OC_GATEWAY_CPU_PCT="$(ps -p "$pid" -o pcpu= 2>/dev/null | tr -d ' ')"
    MH_OC_GATEWAY_CPU_CORES="$(awk -v pct="${MH_OC_GATEWAY_CPU_PCT:-0}" 'BEGIN {printf "%.2f", pct/100}')"
    MH_OC_GATEWAY_MEMORY_PCT="$(ps -p "$pid" -o pmem= 2>/dev/null | tr -d ' ')"
    rss_kb="$(ps -p "$pid" -o rss= 2>/dev/null | tr -d ' ')"
    MH_OC_GATEWAY_RSS_MB="$(awk -v kb="${rss_kb:-0}" 'BEGIN {printf "%.0f", kb/1024}')"
    MH_OC_GATEWAY_THREADS="$(ps -M -p "$pid" -o pid= 2>/dev/null | wc -l | tr -d ' ')"
    MH_OC_GATEWAY_FDS="$(lsof -nP -p "$pid" 2>/dev/null | awk 'NR>1 {count++} END {print count+0}')"
    MH_OC_GATEWAY_UPTIME="$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ')"
  fi
  log_dir="${MH_OPENCLAW_HOME:-$HOME/.openclaw}/logs"
  if [[ -d "$log_dir" ]]; then MH_OC_LOG_KB="$(du -sk "$log_dir" 2>/dev/null | awk '{print $1}')"; else MH_OC_LOG_KB="unknown"; fi
}

mh_openclaw_extended_sample() {
  zmodload zsh/datetime
  local tmp_base health_file status_file start end failed_json db_file
  tmp_base="${TMPDIR:-/tmp}"
  health_file="$(mktemp "$tmp_base/mac-health-health.XXXXXX")"
  status_file="$(mktemp "$tmp_base/mac-health-status.XXXXXX")"
  MH_OC_HEALTH_OK="unknown"
  MH_OC_HEALTH_DURATION_MS="unknown"
  MH_OC_HEALTH_CLI_MS="unknown"
  MH_OC_DELIVERY_FAILURES="unknown"
  MH_OC_TASKS_ACTIVE="unknown"
  MH_OC_TASKS_QUEUED="unknown"
  MH_OC_TASKS_RUNNING="unknown"
  MH_OC_TASK_FAILURES_TOTAL="unknown"
  MH_OC_SQLITE_WAL_WARNING="unknown"
  MH_OC_SQLITE_WAL_BYTES="unknown"
  MH_OC_SQLITE_BLOCKED="unknown"
  MH_OC_SQLITE_QUERY_MS="unknown"
  MH_OC_SQLITE_QUERY_OK="unknown"
  if [[ "$MH_OC_AVAILABLE" == "true" ]]; then
    start="$EPOCHREALTIME"
    if openclaw health --json >"$health_file" 2>/dev/null; then
      end="$EPOCHREALTIME"
      MH_OC_HEALTH_CLI_MS="$(mh_elapsed_ms "$start" "$end")"
      MH_OC_HEALTH_OK="$(mh_plutil_raw "$health_file" ok unknown)"
      MH_OC_HEALTH_DURATION_MS="$(mh_plutil_raw "$health_file" durationMs unknown)"
      failed_json="$(plutil -extract deliveryQueues.failed json -o - "$health_file" 2>/dev/null || true)"
      MH_OC_DELIVERY_FAILURES="$(print -r -- "$failed_json" | grep -Eo '"count"[[:space:]]*:[[:space:]]*[0-9]+' | awk -F: '{gsub(/[[:space:]]/,"",$2); sum+=$2} END {print sum+0}')"
    fi
    if openclaw status --json >"$status_file" 2>/dev/null; then
      MH_OC_TASKS_ACTIVE="$(mh_plutil_raw "$status_file" tasks.active unknown)"
      MH_OC_TASKS_QUEUED="$(mh_plutil_raw "$status_file" tasks.byStatus.queued unknown)"
      MH_OC_TASKS_RUNNING="$(mh_plutil_raw "$status_file" tasks.byStatus.running unknown)"
      MH_OC_TASK_FAILURES_TOTAL="$(mh_plutil_raw "$status_file" tasks.failures unknown)"
      MH_OC_SQLITE_WAL_WARNING="$(mh_plutil_raw "$status_file" sqliteWal.warning unknown)"
      MH_OC_SQLITE_WAL_BYTES="$(mh_plutil_raw "$status_file" sqliteWal.walBytes unknown)"
      MH_OC_SQLITE_BLOCKED="$(mh_plutil_raw "$status_file" sqliteWal.consecutiveBlocked unknown)"
    fi
  fi
  db_file="${MH_OPENCLAW_HOME:-$HOME/.openclaw}/state/openclaw.sqlite"
  if [[ -f "$db_file" ]] && command -v sqlite3 >/dev/null 2>&1; then
    start="$EPOCHREALTIME"
    if sqlite3 -readonly "$db_file" 'PRAGMA query_only=ON; SELECT 1;' >/dev/null 2>&1; then MH_OC_SQLITE_QUERY_OK="true"; else MH_OC_SQLITE_QUERY_OK="false"; fi
    end="$EPOCHREALTIME"
    MH_OC_SQLITE_QUERY_MS="$(mh_elapsed_ms "$start" "$end")"
  fi
  rm -f -- "$health_file" "$status_file"
}

mh_fault_sample() {
  local cutoff report_file power_log report_dir
  cutoff="$(date -v-7d '+%Y-%m-%d' 2>/dev/null || date '+%Y-%m-%d')"
  report_file="$(mktemp "${TMPDIR:-/tmp}/mac-health-reports.XXXXXX")"
  : >"$report_file"
  for report_dir in /Library/Logs/DiagnosticReports "$HOME/Library/Logs/DiagnosticReports"; do
    [[ -d "$report_dir" ]] && find "$report_dir" -maxdepth 1 -type f -mtime -7 -print 2>/dev/null >>"$report_file"
  done
  MH_PANIC_REPORTS_7D="$(grep -Eic '/[^/]*(panic|shutdown_stall|forced_reboot)[^/]*$' "$report_file" || true)"
  MH_HANG_REPORTS_7D="$(grep -Eic '/[^/]*(hang|spin)[^/]*$' "$report_file" || true)"
  power_log="$(pmset -g log 2>/dev/null | awk -v cutoff="$cutoff" 'substr($0,1,10) >= cutoff')"
  MH_SLEEP_WAKE_FAILURES_7D="$(print -r -- "$power_log" | grep -Eic 'sleep.*fail|wake.*fail|darkwake.*fail' || true)"
  MH_THERMAL_SHUTDOWNS_7D="$(print -r -- "$power_log" | grep -Eic 'thermal.*shutdown|shutdown.*thermal' || true)"
  MH_FORCED_REBOOTS_7D="$(print -r -- "$power_log" | grep -Eic 'forced.*(restart|reboot|shutdown)|unexpected.*shutdown' || true)"
  MH_STORAGE_IO_ERRORS_24H="unknown"
  MH_UNIFIED_LOG_STATUS="not-requested"
  rm -f -- "$report_file"
}

mh_collect_all() {
  local extended="${1:-0}"
  MH_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"
  MH_TIMESTAMP_ISO="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  MH_MODEL="$(sysctl -n hw.model 2>/dev/null || uname -m)"
  MH_UPTIME="$(uptime | sed -E 's/.*up (.*), [0-9]+ users?.*/\1/' | sed -E 's/, load averages:.*//')"
  MH_EXTENDED="$extended"
  mh_sensor_start
  mh_cpu_sample
  mh_memory_sample
  mh_battery_sample
  mh_thermal_sample
  mh_disk_sample
  mh_gpu_sample
  mh_network_counter_sample
  mh_openclaw_process_sample
  mh_sensor_finish

  MH_DISK_IO_DEVICE="unknown"; MH_DISK_KB_PER_TRANSFER="unknown"; MH_DISK_TRANSFERS_PER_SEC="unknown"; MH_DISK_MB_PER_SEC="unknown"; MH_DISK_LATENCY_MS="unavailable"
  MH_DNS_OK="unknown"; MH_DNS_LATENCY_MS="unknown"; MH_LAN_GATEWAY_RTT_MS="unknown"; MH_TAILSCALE_BACKEND="unknown"; MH_TAILSCALE_ONLINE_PEERS="unknown"
  MH_OC_HEALTH_OK="unknown"; MH_OC_HEALTH_DURATION_MS="unknown"; MH_OC_HEALTH_CLI_MS="unknown"; MH_OC_DELIVERY_FAILURES="unknown"
  MH_OC_TASKS_ACTIVE="unknown"; MH_OC_TASKS_QUEUED="unknown"; MH_OC_TASKS_RUNNING="unknown"; MH_OC_TASK_FAILURES_TOTAL="unknown"
  MH_OC_SQLITE_WAL_WARNING="unknown"; MH_OC_SQLITE_WAL_BYTES="unknown"; MH_OC_SQLITE_BLOCKED="unknown"; MH_OC_SQLITE_QUERY_MS="unknown"; MH_OC_SQLITE_QUERY_OK="unknown"
  MH_PANIC_REPORTS_7D="unknown"; MH_HANG_REPORTS_7D="unknown"; MH_SLEEP_WAKE_FAILURES_7D="unknown"; MH_THERMAL_SHUTDOWNS_7D="unknown"; MH_FORCED_REBOOTS_7D="unknown"
  MH_STORAGE_IO_ERRORS_24H="unknown"; MH_UNIFIED_LOG_STATUS="not-requested"
  if (( extended )); then
    mh_disk_io_sample
    mh_network_probe_sample
    mh_openclaw_extended_sample
    mh_fault_sample
  fi
}

mh_assess() {
  MH_FINDINGS=()
  MH_WORST="ok"
  if [[ "$MH_THERMAL_STATE" != "clear" || "$MH_PERFORMANCE_STATE" != "clear" ]]; then
    MH_FINDINGS+=("CRITICAL|macOS has recorded a thermal or performance warning; throttling is likely active or recently active.")
    MH_WORST="critical"
  fi
  if mh_float_lt "$MH_CPU_IDLE" 5; then
    MH_FINDINGS+=("WARN|CPU has less than 5% idle capacity in this sample (${MH_CPU_BUSY}% busy).")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  elif mh_float_lt "$MH_CPU_IDLE" 15; then
    MH_FINDINGS+=("INFO|CPU is heavily loaded in this sample (${MH_CPU_BUSY}% busy), but load alone does not prove throttling.")
  fi
  if mh_float_gt "$MH_LOAD_PER_CORE" 1.25; then
    MH_FINDINGS+=("WARN|1-minute load is ${MH_LOAD_PER_CORE}× logical-core count; work is queueing.")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  elif mh_float_gt "$MH_LOAD_PER_CORE" 0.85; then
    MH_FINDINGS+=("INFO|1-minute load is ${MH_LOAD_PER_CORE}× logical-core count; the machine is near full scheduling demand.")
  fi
  if mh_float_lt "$MH_MEMORY_FREE_PCT" 10; then
    MH_FINDINGS+=("CRITICAL|Memory-pressure free percentage is ${MH_MEMORY_FREE_PCT}%; memory pressure is severe.")
    MH_WORST="critical"
  elif mh_float_lt "$MH_MEMORY_FREE_PCT" 25; then
    MH_FINDINGS+=("WARN|Memory-pressure free percentage is ${MH_MEMORY_FREE_PCT}%; watch compression and swap growth.")
    [[ "$MH_WORST" != "critical" ]] && MH_WORST="warn"
  fi
  if mh_float_gt "$MH_SWAP_USED_MB" 1024; then
    MH_FINDINGS+=("WARN|Swap use is ${MH_SWAP_USED_MB} MB. Growth during the watch window matters more than the absolute value.")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  elif mh_float_gt "$MH_SWAP_USED_MB" 0; then
    MH_FINDINGS+=("INFO|Swap is in use (${MH_SWAP_USED_MB} MB); this is not automatically a problem unless it is growing or latency is visible.")
  fi
  if [[ "$MH_BATTERY_TEMP_C" != "unknown" ]]; then
    if mh_float_gt "$MH_BATTERY_TEMP_C" 45; then
      MH_FINDINGS+=("CRITICAL|Battery temperature is ${MH_BATTERY_TEMP_C}°C; reduce heat and charging load.")
      MH_WORST="critical"
    elif mh_float_gt "$MH_BATTERY_TEMP_C" 40; then
      MH_FINDINGS+=("WARN|Battery temperature is ${MH_BATTERY_TEMP_C}°C; warm enough to watch if sustained.")
      [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
    fi
  fi
  if [[ "$MH_CPU_TEMP_C" != "unknown" ]] && mh_float_gt "$MH_CPU_TEMP_C" 105; then
    MH_FINDINGS+=("WARN|CPU sensor average is ${MH_CPU_TEMP_C}°C; confirm macOS thermal pressure and sustained clocks.")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  elif [[ "$MH_CPU_TEMP_C" != "unknown" ]] && mh_float_gt "$MH_CPU_TEMP_C" 95; then
    MH_FINDINGS+=("INFO|CPU sensor average is ${MH_CPU_TEMP_C}°C under load; macOS still reports thermal state '$MH_THERMAL_STATE'.")
  fi
  if [[ "$MH_GPU_TEMP_C" != "unknown" ]] && mh_float_gt "$MH_GPU_TEMP_C" 95; then
    MH_FINDINGS+=("WARN|GPU sensor average is ${MH_GPU_TEMP_C}°C; watch for a macOS thermal-pressure warning if sustained.")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  elif [[ "$MH_GPU_TEMP_C" != "unknown" ]] && mh_float_gt "$MH_GPU_TEMP_C" 90; then
    MH_FINDINGS+=("INFO|GPU sensor average is ${MH_GPU_TEMP_C}°C under load; macOS still reports thermal state '$MH_THERMAL_STATE'.")
  fi
  if mh_float_lt "$MH_DISK_FREE_PCT" 10; then
    MH_FINDINGS+=("WARN|Startup disk has only ${MH_DISK_FREE_PCT}% free; low space can hurt VM and update behavior.")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  fi
  if [[ "$MH_DISK_SMART" != "unavailable" && "$MH_DISK_SMART" != "Verified" ]]; then
    MH_FINDINGS+=("WARN|Startup disk SMART state is '$MH_DISK_SMART'.")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  fi
  if [[ "$MH_DISK_TRANSFERS_PER_SEC" != "unknown" ]] && mh_float_gt "$MH_DISK_TRANSFERS_PER_SEC" 2500; then
    MH_FINDINGS+=("INFO|Disk is handling ${MH_DISK_TRANSFERS_PER_SEC} transfers/s; metadata-heavy scans may be contributing to latency.")
  fi
  if (( MH_STUCK_PROCESSES > 0 )); then MH_FINDINGS+=("INFO|top reported ${MH_STUCK_PROCESSES} stuck process(es); persistent repeats matter more than one sample."); fi
  if [[ "$MH_LOW_POWER_MODE" == "1" ]]; then MH_FINDINGS+=("INFO|Low Power Mode is enabled; reduced peak performance is intentional, not thermal throttling."); fi
  if [[ "$MH_NETWORK_RX_ERRORS" == <-> && "$MH_NETWORK_TX_ERRORS" == <-> ]] && (( MH_NETWORK_RX_ERRORS + MH_NETWORK_TX_ERRORS > 0 )); then
    MH_FINDINGS+=("INFO|The active network interface has cumulative packet errors; trend mode can show whether they are increasing.")
  fi
  if [[ "$MH_OC_GATEWAY_RSS_MB" != "unknown" ]] && mh_float_gt "$MH_OC_GATEWAY_RSS_MB" 16384; then
    MH_FINDINGS+=("WARN|OpenClaw Gateway RSS is ${MH_OC_GATEWAY_RSS_MB} MB.")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  fi
  if [[ "$MH_OC_GATEWAY_FDS" != "unknown" ]] && mh_float_gt "$MH_OC_GATEWAY_FDS" 4096; then
    MH_FINDINGS+=("WARN|OpenClaw Gateway has ${MH_OC_GATEWAY_FDS} open file descriptors.")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  fi
  if [[ "$MH_OC_HEALTH_OK" == "false" || "$MH_OC_SQLITE_WAL_WARNING" == "true" || "$MH_OC_SQLITE_QUERY_OK" == "false" ]]; then
    MH_FINDINGS+=("WARN|OpenClaw health or SQLite reported a problem; inspect the extended OpenClaw section.")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  fi
  if [[ "$MH_OC_SQLITE_BLOCKED" == <-> ]] && (( MH_OC_SQLITE_BLOCKED > 0 )); then
    MH_FINDINGS+=("WARN|OpenClaw SQLite WAL checkpointing has been blocked ${MH_OC_SQLITE_BLOCKED} consecutive time(s).")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  fi
  if [[ "$MH_PANIC_REPORTS_7D" == <-> ]] && (( MH_PANIC_REPORTS_7D > 0 )); then
    MH_FINDINGS+=("WARN|Found ${MH_PANIC_REPORTS_7D} recent panic/forced-reboot diagnostic report(s).")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  fi
  if [[ "$MH_STORAGE_IO_ERRORS_24H" == <-> ]] && (( MH_STORAGE_IO_ERRORS_24H > 0 )); then
    MH_FINDINGS+=("WARN|Unified logs contain ${MH_STORAGE_IO_ERRORS_24H} storage I/O or thermal-shutdown event(s) in 24 hours.")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  fi
  if (( ${#MH_FINDINGS[@]} == 0 )); then MH_FINDINGS+=("OK|No pressure or throttling clues crossed the built-in thresholds."); fi
}
