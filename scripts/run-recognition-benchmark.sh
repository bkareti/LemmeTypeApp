#!/bin/sh
# Runs the opt-in Whisper benchmark in the test runner (needs macOS, `say`, and
# an installed Whisper model or LEMMETYPE_WHISPER_MODEL). Reports land in
# build/benchmarks/. Only metrics are written; synthesized audio is deleted as
# it is used. For Apple Speech and capture-stop-to-delivery latency across all
# engines, use scripts/run-e2e-benchmark.sh.
set -eu
cd "$(dirname "$0")/.."
LEMMETYPE_BENCHMARK=1 swift test --package-path Packages/LemmeTypeKit --filter RecognitionBenchmarkTests "$@"
cat build/benchmarks/*.md
python3 scripts/check-performance-thresholds.py build/benchmarks
