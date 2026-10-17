# Performance, accuracy, and privacy thresholds (E2-S10)

**Status: Proposed — awaiting product-owner approval.** Epic 2 cannot close
until a product owner approves these numbers (set `status` to `Approved` and
`approvedBy` in `performance-thresholds.json`, and record it below).

The machine-readable limits live in `performance-thresholds.json`;
`scripts/check-performance-thresholds.py` fails the release check when any
report in `build/benchmarks/` is beyond them.

## How the numbers are produced

| Script | What it runs | Engines |
|---|---|---|
| `scripts/run-e2e-benchmark.sh` | Debug app in benchmark mode (`-LemmeTypeBenchmark`), under the network monitor | every ready engine (Apple Speech, Whisper) |
| `scripts/run-recognition-benchmark.sh` | `RecognitionBenchmarkTests` in the test runner | Whisper only (a test runner can't get Speech Recognition authorization) |

Both use `DictationBenchmark` (TestSupport, Debug only) and the versioned
corpus `benchmark-corpus.json` (v2): 16 licence-free sentences in
conversational, technical, numeric, and long categories, synthesised with
`say` for four accents (US, UK, Australian, Indian English) plus a noisy copy
(white noise at 10 dB SNR, fixed seed) of the US voice. Every engine gets the
same audio. Each recording goes through the real `TranscriptionPipeline`
(recognition → Clean Writing → delivery to a discarding target).

Reports contain metrics only. Transcripts are compared with the reference in
memory and dropped; synthesised audio is deleted as each session completes;
`make privacy-check` and `scripts/check-release-artifact.sh` verify nothing is
left behind or shipped.

## Metrics

| Metric | Meaning |
|---|---|
| `stopToDeliverySeconds` | Capture stop → text delivered (what the user waits for). In real use the same value is the `processingSeconds` attribute of `session.delivered` diagnostics. |
| `inferenceSeconds` | Recognition alone (`recognitionSeconds` in diagnostics). |
| `warmUpSeconds` | First `prepare()` (model load). |
| `realTimeFactor` | Inference ÷ audio duration. |
| `audioSeconds` | Duration of each recording. |
| `peakMemoryIncreaseMB` | Growth of the process's peak resident memory during the run. |
| `wordErrorRate` | Mean WER over clean audio; also per category and per accent. |
| `noisyWordErrorRate` | Mean WER over the noisy copies. |
| `failedSessions` | Sessions that did not deliver text. |

## Proposed thresholds

Minimum hardware: Apple silicon, 8 GB (M1). Recommended: M2 or later, 16 GB.
Thresholds apply on the **minimum** hardware.

| Metric | All engines | Apple Speech | Whisper |
|---|---|---|---|
| Capture stop → delivered, p95 | ≤ 2.5 s | | ≤ 3.0 s |
| Capture stop → delivered, mean | ≤ 1.5 s | | |
| Inference, p95 | ≤ 2.0 s | | |
| Real-time factor, mean | ≤ 0.5 | | |
| Warm-up | ≤ 3.0 s | ≤ 1.0 s | |
| Peak memory increase | ≤ 600 MB | ≤ 250 MB | |
| WER, clean audio | ≤ 12 % | | |
| WER, noisy audio | ≤ 25 % | | |
| Failed sessions | 0 | | |

Network: **zero** sockets opened by LemmeType during capture, recognition,
cleanup, and delivery (`scripts/check-network-silence.sh`; MA-31).

## Recorded runs

| Date | Mac (model, memory) | macOS | Engine | Report summary | Within thresholds |
|---|---|---|---|---|---|
| — | — | — | — | Not yet run on minimum or recommended hardware | — |

## Approval

| Approved by | Date | Notes |
|---|---|---|
| — | — | Pending |
