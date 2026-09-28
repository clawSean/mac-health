#!/bin/zsh

set -eu

ROOT="${0:A:h:h}"
snapshot="$($ROOT/bin/mac-health)"

for needle in \
  'Mac health snapshot' \
  'CPU' \
  'Memory' \
  'Swap' \
  'Battery' \
  'Thermals' \
  'Assessment' \
  'Top CPU processes'; do
  if [[ "$snapshot" != *"$needle"* ]]; then
    print -u2 -- "missing expected output: $needle"
    exit 1
  fi
done

watch_output="$($ROOT/bin/mac-health-watch --interval 1 --samples 2)"
[[ "$watch_output" == *'Watch summary'* ]]
if [[ "$watch_output" != *'[OK]'* && "$watch_output" != *'[INFO]'* && "$watch_output" != *'[WARN]'* ]]; then
  print -u2 -- "watch output did not contain a terminal assessment"
  exit 1
fi

print -- "smoke: PASS"
