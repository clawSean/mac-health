#!/bin/zsh

# Shared, dependency-free metric collectors for Apple silicon Macs.

mh_num() {
  local value="${1:-0}"
  value="${value//[^0-9.]/}"
  print -r -- "${value:-0}"
}

mh_float_lt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a < b) }'; }
mh_float_gt() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }

mh_cpu_sample() {
  local top_output cpu_line
  top_output="$(top -l 2 -n 0 2>/dev/null)"
  cpu_line="$(print -r -- "$top_output" | awk '/^CPU usage:/ { line=$0 } END { print line }')"

  MH_CPU_USER="$(print -r -- "$cpu_line" | sed -E 's/.*CPU usage: ([0-9.]+)% user.*/\1/')"
  MH_CPU_SYS="$(print -r -- "$cpu_line" | sed -E 's/.*user, ([0-9.]+)% sys.*/\1/')"
  MH_CPU_IDLE="$(print -r -- "$cpu_line" | sed -E 's/.*sys, ([0-9.]+)% idle.*/\1/')"
  MH_CPU_BUSY="$(awk -v idle="${MH_CPU_IDLE:-100}" 'BEGIN { printf "%.1f", 100-idle }')"

  local load
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
  local pressure swap vm
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
  MH_PAGEOUTS="$(print -r -- "$vm" | awk -F': ' '/Pageouts:/ {gsub(/[^0-9]/,"",$2); print $2}')"
  MH_SWAPINS="$(print -r -- "$vm" | awk -F': ' '/Swapins:/ {gsub(/[^0-9]/,"",$2); print $2}')"
  MH_SWAPOUTS="$(print -r -- "$vm" | awk -F': ' '/Swapouts:/ {gsub(/[^0-9]/,"",$2); print $2}')"
  MH_PAGEOUTS="${MH_PAGEOUTS:-0}"
  MH_SWAPINS="${MH_SWAPINS:-0}"
  MH_SWAPOUTS="${MH_SWAPOUTS:-0}"

  local mem_bytes
  mem_bytes="$(sysctl -n hw.memsize 2>/dev/null || print 0)"
  MH_MEMORY_TOTAL_GB="$(awk -v bytes="$mem_bytes" 'BEGIN { printf "%.0f", bytes/1073741824 }')"
}

mh_battery_sample() {
  local batt power
  batt="$(ioreg -r -c AppleSmartBattery -d 1 2>/dev/null)"
  power="$(pmset -g batt 2>/dev/null)"

  MH_BATTERY_PCT="$(print -r -- "$power" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')"
  MH_BATTERY_PCT="${MH_BATTERY_PCT:-unknown}"
  MH_BATTERY_STATE="$(print -r -- "$power" | awk -F';' 'NR==2 {gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
  MH_BATTERY_STATE="${MH_BATTERY_STATE:-unknown}"

  local raw_temp
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
}

mh_thermal_sample() {
  MH_THERMAL_TEXT="$(pmset -g therm 2>/dev/null)"
  if print -r -- "$MH_THERMAL_TEXT" | grep -q 'No thermal warning level'; then
    MH_THERMAL_STATE="clear"
  else
    MH_THERMAL_STATE="warning"
  fi
  if print -r -- "$MH_THERMAL_TEXT" | grep -q 'No performance warning level'; then
    MH_PERFORMANCE_STATE="clear"
  else
    MH_PERFORMANCE_STATE="warning"
  fi

  MH_LOW_POWER_MODE="$(pmset -g custom 2>/dev/null | awk '/lowpowermode/ {print $2; exit}')"
  MH_LOW_POWER_MODE="${MH_LOW_POWER_MODE:-0}"
}

mh_disk_sample() {
  local disk
  disk="$(df -k / 2>/dev/null | tail -1)"
  MH_DISK_FREE_GB="$(print -r -- "$disk" | awk '{printf "%.1f", $4/1048576}')"
  MH_DISK_USED_PCT="$(print -r -- "$disk" | awk '{gsub(/%/,"",$5); print $5}')"
  MH_DISK_FREE_PCT="$(awk -v used="${MH_DISK_USED_PCT:-100}" 'BEGIN {printf "%.0f", 100-used}')"
}

mh_collect_all() {
  MH_TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"
  MH_MODEL="$(sysctl -n hw.model 2>/dev/null || uname -m)"
  MH_UPTIME="$(uptime | sed -E 's/.*up (.*), [0-9]+ users?.*/\1/' | sed -E 's/, load averages:.*//')"
  mh_cpu_sample
  mh_memory_sample
  mh_battery_sample
  mh_thermal_sample
  mh_disk_sample
}

mh_status_label() {
  local level="$1"
  case "$level" in
    ok) print -r -- "OK" ;;
    info) print -r -- "INFO" ;;
    warn) print -r -- "WARN" ;;
    critical) print -r -- "CRITICAL" ;;
  esac
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

  if mh_float_lt "$MH_DISK_FREE_PCT" 10; then
    MH_FINDINGS+=("WARN|Startup disk has only ${MH_DISK_FREE_PCT}% free; low space can hurt VM and update behavior.")
    [[ "$MH_WORST" == "ok" ]] && MH_WORST="warn"
  fi

  if (( MH_STUCK_PROCESSES > 0 )); then
    MH_FINDINGS+=("INFO|top reported ${MH_STUCK_PROCESSES} stuck process(es); persistent repeats matter more than one sample.")
  fi

  if [[ "$MH_LOW_POWER_MODE" == "1" ]]; then
    MH_FINDINGS+=("INFO|Low Power Mode is enabled; reduced peak performance is intentional, not thermal throttling.")
  fi

  if (( ${#MH_FINDINGS[@]} == 0 )); then
    MH_FINDINGS+=("OK|No pressure or throttling clues crossed the built-in thresholds.")
  fi
}
