#!/usr/bin/env bash
# Network monitor for Local mode (E2-S10): fails if a LemmeType process has any
# internet socket open while it captures, recognises, cleans up, or delivers.
#
#   scripts/check-network-silence.sh -- <command…>   launch and watch a process
#   scripts/check-network-silence.sh --attach [seconds]
#                                                   watch the running app while
#                                                   you dictate (default 120 s)
#
# Uses `lsof -i` on the process (no root needed for your own processes) and
# samples every 0.1 s. Short-lived connections between samples can be missed,
# so the manual check (MA-19, MA-31) still uses Little Snitch, LuLu, or nettop.
set -euo pipefail

sample() {
  # Prints one line per internet socket owned by $1 (header removed).
  lsof -nP -a -p "$1" -i 2>/dev/null | tail -n +2 || true
}

watch_pid() {
  local pid="$1" deadline="$2" found=""
  while kill -0 "$pid" 2>/dev/null; do
    found="$(sample "$pid")"
    if [[ -n "$found" ]]; then
      echo "error: LemmeType (pid $pid) opened a network socket:" >&2
      echo "$found" >&2
      return 1
    fi
    if [[ -n "$deadline" && "$(date +%s)" -ge "$deadline" ]]; then break; fi
    sleep 0.1
  done
  return 0
}

case "${1:-}" in
  --attach)
    seconds="${2:-120}"
    pid="$(pgrep -x LemmeType | head -n 1 || true)"
    [[ -n "$pid" ]] || { echo "error: LemmeType is not running" >&2; exit 2; }
    echo "Watching LemmeType (pid $pid) for ${seconds}s. Dictate now…"
    watch_pid "$pid" "$(( $(date +%s) + seconds ))"
    echo "No network socket was opened."
    ;;
  --)
    shift
    "$@" &
    pid=$!
    status=0
    watch_pid "$pid" "" || status=$?
    if [[ $status -ne 0 ]]; then
      kill "$pid" 2>/dev/null || true
      exit "$status"
    fi
    wait "$pid"
    echo "No network socket was opened."
    ;;
  *)
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
