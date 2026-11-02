#!/usr/bin/env bash
# One command, one summary (E7-S8): runs every automated check, keeps going after
# a failure so the summary names all of them, and exits non-zero if any failed.
#
#   scripts/quality-gate.sh [--ui]
#
# UI tests need a GUI session with UI Automation Mode, so they run only with
# --ui; otherwise they are listed as SKIPPED, never as passed. The step list is
# the same as the CI workflow's (scripts/tests/test-quality-gate.sh compares them).
# QUALITY_GATE_STEPS overrides the steps for tests: lines of "name|command".
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
with_ui=0
[[ "${1:-}" == "--ui" ]] && with_ui=1

default_steps="lint|make lint
build|make build
package tests|make test-unit
hosted app tests|make test-app
no leftover audio|make privacy-check
network allowlist|make network-check
security allowlists|make security-check
threat model and checklist|make privacy-docs-check
localization|make l10n-check
release and support docs|make docs-check
release scripts|make release-script-tests"
steps="${QUALITY_GATE_STEPS:-$default_steps}"

names=()
results=()
seconds=()
failed=0

run_step() { # run_step <name> <command>
  local name="$1" command="$2" start=$SECONDS log
  log="$(mktemp)"
  echo "==> $name: $command"
  if bash -c "$command" >"$log" 2>&1; then
    results+=("passed")
  else
    results+=("FAILED")
    failed=$((failed + 1))
    tail -n 15 "$log" | sed 's/^/    /'
  fi
  rm -f "$log"
  names+=("$name")
  seconds+=("$((SECONDS - start))")
}

while IFS='|' read -r name command; do
  [[ -n "$name" ]] && run_step "$name" "$command"
done <<<"$steps"

if [[ -z "${QUALITY_GATE_STEPS:-}" ]]; then
  if [[ $with_ui -eq 1 ]]; then
    run_step "UI tests" "make test-ui"
  else
    names+=("UI tests"); results+=("SKIPPED (pass --ui; needs a GUI session)"); seconds+=("0")
  fi
fi

echo
echo "Quality gate"
for index in "${!names[@]}"; do
  printf '  %-30s %-10s %4ss\n' "${names[$index]}" "${results[$index]}" "${seconds[$index]}"
done
echo
if [[ $failed -eq 0 ]]; then
  echo "All $((${#names[@]})) steps passed or were skipped on purpose."
else
  echo "$failed step(s) FAILED." >&2
  exit 1
fi
