#!/usr/bin/env bash
# Release check (E2-S10): fails if a built app, zip, or dmg contains recordings,
# benchmark output, transcripts, or test fixtures.
#
#   scripts/check-release-artifact.sh build/Release/LemmeType.app
#   scripts/check-release-artifact.sh LemmeType-1.0.0.zip
set -euo pipefail
target="${1:?usage: $0 <LemmeType.app | .zip | .dmg>}"
work=""
cleanup() { [[ -n "$work" ]] && rm -rf "$work"; [[ -n "${mounted:-}" ]] && hdiutil detach -quiet "$mounted" || true; }
trap cleanup EXIT

case "$target" in
  *.zip)
    work="$(mktemp -d)"; ditto -x -k "$target" "$work"; root="$work" ;;
  *.dmg)
    mounted="$(mktemp -d)"; hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mounted" "$target"; root="$mounted" ;;
  *)
    root="$target" ;;
esac

found="$(find "$root" -type f \( \
    -iname '*.caf' -o -iname '*.wav' -o -iname '*.m4a' -o -iname '*.aiff' -o -iname '*.mp3' \
    -o -iname '*transcript*' -o -iname 'benchmark-corpus.json' -o -path '*/benchmarks/*' \
    -o -iname '*.xctest' -o -path '*LemmeTypeTests-*' \) -print)"
if [[ -n "$found" ]]; then
  echo "error: the release artifact contains test recordings, transcripts, or benchmark output:" >&2
  echo "$found" >&2
  exit 1
fi
echo "Release artifact contains no recordings, transcripts, or benchmark output."
