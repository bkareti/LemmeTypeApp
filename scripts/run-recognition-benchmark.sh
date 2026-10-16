#!/bin/sh
# Runs the opt-in recognition benchmark (needs macOS, `say`, and an installed
# Whisper model or LEMMETYPE_WHISPER_MODEL). Reports land in build/benchmarks/.
# Only metrics are written; synthesized audio is deleted as it is used.
set -eu
cd "$(dirname "$0")/.."
LEMMETYPE_BENCHMARK=1 swift test --package-path Packages/LemmeTypeKit --filter RecognitionBenchmarkTests "$@"
cat build/benchmarks/*.md
