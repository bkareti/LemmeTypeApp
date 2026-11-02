#!/usr/bin/env bash
# Tests for scripts/quality-gate.sh (E7-S8): the summary names every failure, the
# exit code follows, skipped is never passed, and CI runs the same steps.
set -uo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
gate="$repo/scripts/quality-gate.sh"
failures=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; failures=$((failures + 1)); }

out="$(QUALITY_GATE_STEPS=$'first|true\nsecond|true' "$gate" 2>&1)"; code=$?
[[ $code -eq 0 && "$out" == *"All 2 steps passed"* ]] && ok "all green exits 0" || bad "all green exits 0 ($code)"

out="$(QUALITY_GATE_STEPS=$'first|true\nbroken step|false\nthird|true\nalso broken|exit 3' "$gate" 2>&1)"; code=$?
[[ $code -eq 1 ]] && ok "any failure exits 1" || bad "any failure exits 1 ($code)"
[[ "$out" == *"broken step"*"FAILED"* && "$out" == *"also broken"*"FAILED"* && "$out" == *"2 step(s) FAILED"* ]] \
  && ok "the summary names every failed step" || bad "the summary names every failed step"
[[ "$out" == *"third"*"passed"* ]] && ok "steps after a failure still run" || bad "steps after a failure still run"

out="$(QUALITY_GATE_STEPS='noisy|echo detail; false' "$gate" 2>&1)"
[[ "$out" == *"detail"* ]] && ok "a failed step shows its output" || bad "a failed step shows its output"

# Without the override, UI tests are listed as skipped (checked on the step list only).
grep -q 'SKIPPED (pass --ui' "$gate" && ok "UI tests are reported as SKIPPED, never passed" || bad "UI tests are reported as SKIPPED"

# CI runs the same steps as the gate.
steps="$(sed -n '/^default_steps=/,/^steps=/p' "$gate" | grep -o '|make [a-z0-9-]*' | sed 's/|make //')"
workflow="$repo/.github/workflows/ci.yml"
for target in $steps; do
  if grep -Eq "run: make $target\$" "$workflow"; then ok "CI runs make $target"; else bad "CI does not run make $target"; fi
done
grep -Eq 'run: make test-ui$' "$workflow" && ok "CI runs make test-ui (non-blocking job)" || bad "CI does not run make test-ui"
for target in $steps test-ui; do
  grep -Eq "^$target:" "$repo/Makefile" && ok "Makefile has $target" || bad "Makefile has no $target"
done

[[ $failures -eq 0 ]] && echo "All quality-gate checks passed." || { echo "$failures failure(s)."; exit 1; }
