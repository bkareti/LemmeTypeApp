# 0012 — Downloadable local speech model: whisper.cpp `base.en`

- Status: Accepted (on-device benchmark numbers pending, see "Evidence")
- Date: 2026-10-16
- Story: E2-S3

## Context

LemmeType needs one predictable, fully offline engine for Macs or locales
where Apple's on-device recognition is missing or unsuitable. It is the app's
first third-party runtime dependency, so it needs a licence, maintenance,
privacy, and size review.

## Options considered

| Criterion | whisper.cpp + ggml `base.en` | whisper.cpp `small.en` | whisper.cpp `tiny.en` | WhisperKit (Core ML) |
|---|---|---|---|---|
| Licence | MIT (code and weights) | MIT | MIT | MIT, plus Core ML model conversions |
| Download | 142 MiB | 466 MiB | 75 MiB | 150–500 MB per model |
| Memory (upstream figure) | ~390 MB | ~850 MB | ~270 MB | similar per size |
| English accuracy (upstream LibriSpeech figures) | good | best of the three | noticeably worse on names/numbers | comparable per size |
| Latency on Apple silicon (Metal) | well under real time | ~2–3× slower than base | fastest | comparable; first-run compile cost |
| Integration | One pinned binary XCFramework, C API, no transitive deps | same | same | Swift package with several transitive dependencies and its own model-download code |
| Network behaviour | None at runtime | None | None | Built-in Hugging Face downloader to disable/avoid |
| Maintenance | Very active; tagged releases with prebuilt XCFrameworks | same | same | Active, single vendor |

## Decision

- **Runtime**: whisper.cpp **v1.9.2**, as the official prebuilt
  `whisper-v1.9.2-xcframework.zip`, a SwiftPM `binaryTarget` pinned by URL and
  checksum. Only the `Recognition` module links it. Metal is used when
  available; its own logging is silenced.
- **Model**: `ggml-base.en.bin` (English only), the best balance of download
  size, memory, and accuracy for an MVP dictation engine; downloaded via
  ADR 0011 and pinned by size and SHA-256.
- **Hardware gate** (checked before the download is offered): Apple silicon and
  ≥ 8 GB physical memory; otherwise the engine is `unsupported(.hardware)` or
  `unsupported(.insufficientMemory)` and the UI explains why.
- **Lifecycle**: `prepare()` loads the model (warm-up); `recognize` runs greedy
  decoding off the actor with an abort flag polled by whisper.cpp, so
  cancellation stops inference promptly; `unload()` frees the context. A
  cancelled warm-up returns immediately and the model is freed as soon as the
  (uninterruptible) load finishes. Samples exist only during `recognize`; the
  transcript is returned and not retained.
- **Notices**: `THIRD_PARTY_NOTICES.md` and the app's About › Credits
  (`App/LemmeType/Credits.rtf`) carry the whisper.cpp and OpenAI Whisper MIT
  notices.

## Evidence and reproducible benchmark

- **Inputs**: `docs/testing/benchmark-corpus.json` (versioned sentences in
  conversational, technical, numeric, and long-form categories) synthesised
  with four macOS voices by `say`, so every run uses identical audio without
  licensing concerns; real-speech runs read the same sentences.
- **Harness**: `scripts/run-recognition-benchmark.sh` runs
  `RecognitionBenchmarkTests` (opt-in, `LEMMETYPE_BENCHMARK=1`) and writes
  warm-up time, mean/p95 inference time, real-time factor, peak memory, and
  word error rate per category to `build/benchmarks/` — metrics only, no text.
- **Status**: the table above uses upstream-published sizes and relative
  figures. Measured numbers on the minimum (8 GB M1) and recommended (16 GB
  M-series) Macs are recorded with E2-S10 in
  `docs/testing/performance-thresholds.md`; if `base.en` misses the approved
  thresholds there, `tiny.en`/`small.en` are drop-in catalog changes.

## Consequences

- Package resolution downloads the ~50 MB XCFramework zip once (cached).
- Upgrading whisper.cpp means a new URL + checksum and re-running the benchmark.
