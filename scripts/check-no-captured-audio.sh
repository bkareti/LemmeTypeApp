#!/usr/bin/env bash
# Fails if any captured audio is left behind by the app or its tests.
# Run after tests locally (`make privacy-check`) and in CI. Session audio must
# always be deleted on stop, cancel, failure, or by the consumer (ADR 0006).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
tmp_root="${TMPDIR:-/tmp}"

leftovers="$(
  {
    find "$tmp_root" -maxdepth 1 -name 'LemmeType*' -print0 2>/dev/null \
      | xargs -0 -I{} find {} -type f \( -name '*.caf' -o -name '*.wav' -o -name '*.m4a' \) 2>/dev/null
    find "$repo_root" -path "$repo_root/.git" -prune -o -type f \( -name '*.caf' -o -name '*.wav' -o -name '*.m4a' \) -print
  } | sort -u
)"

if [[ -n "$leftovers" ]]; then
  echo "error: captured audio was left behind:" >&2
  echo "$leftovers" >&2
  exit 1
fi
echo "No captured audio left behind."
