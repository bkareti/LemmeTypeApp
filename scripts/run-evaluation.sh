#!/bin/sh
# Runs the opt-in corpus evaluation with real Whisper models in the test runner, then
# writes the summary, JUnit XML, and HTML dashboard (docs/testing/evaluation-harness.md).
#
#   scripts/run-evaluation.sh [--baseline <report.json or folder>]
#
# Needs: the corpus fetched (scripts/corpus.py fetch) and a multilingual Whisper model
# installed in LemmeType (or LEMMETYPE_EVALUATION_MODEL naming an installed one).
# Environment: LEMMETYPE_CORPUS_ROOT (default: the pinned FLEURS folder in the cache),
# LEMMETYPE_EVALUATION_TASK, LEMMETYPE_EVALUATION_LANGUAGES. Only metrics are written,
# to build/evaluation/; a socket watch fails the run if any network socket opens.
set -eu
cd "$(dirname "$0")/.."
: "${LEMMETYPE_CORPUS_ROOT:=$HOME/Library/Caches/LemmeTypeCorpus/fleurs/70bb2e84b976b7e960aa89f1c648e09c59f894dd}"
export LEMMETYPE_CORPUS_ROOT
python3 -I scripts/corpus.py verify docs/testing/corpus/fleurs.json --root "$LEMMETYPE_CORPUS_ROOT"
LEMMETYPE_EVALUATION=1 swift test --package-path Packages/LemmeTypeKit --filter CorpusEvaluationTests
python3 -I scripts/evaluation-report.py build/evaluation --out build/evaluation/report "$@"
scripts/check-no-captured-audio.sh
