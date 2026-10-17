#!/usr/bin/env bash
# End-to-end benchmark (E2-S10, docs/testing/performance-thresholds.md).
# Builds the Debug app and runs the versioned corpus through every ready
# engine inside the app (so Apple Speech has its authorization), under the
# network monitor, then checks the thresholds. Only metrics are written, to
# build/benchmarks/; synthesized audio is deleted as each session completes.
#
# Needs: macOS `say` voices from the corpus, Speech Recognition allowed for a
# team-signed LemmeType (first run prompts), the Whisper model installed for
# the Whisper report. Quit any running LemmeType first.
set -euo pipefail
cd "$(dirname "$0")/.."

make build >/dev/null
app="build/DerivedData/Build/Products/Debug/LemmeType.app/Contents/MacOS/LemmeType"
output="$(pwd)/build/benchmarks"
mkdir -p "$output"

scripts/check-network-silence.sh -- \
  "$app" -LemmeTypeBenchmark "$(pwd)/docs/testing/benchmark-corpus.json" "$output"

cat "$output"/*.md
python3 scripts/check-performance-thresholds.py "$output"
scripts/check-no-captured-audio.sh
