# Readiness review — Epic 2 (local transcription, cleanup, and text delivery)

Reviewed 2026-10-16 with the `story-review` skill against
`docs/backlog/epic-02-local-dictation.md`, the Epic 1 code on `main`, and ADRs 0001–0008.

## Summary

| Story | Verdict | Main points |
|---|---|---|
| E2-S1 Engine contract | Ready | Cancellation guarantee enforced centrally by a runner, not per engine. |
| E2-S2 Apple Speech | Ready with notes | Speech authorization is a separate TCC permission; real recognition is manual-only on CI. |
| E2-S3 Downloadable model | Ready with notes | 13 points; benchmark numbers need real hardware. First third-party dependency → ADR. |
| E2-S4 Model assets | Ready with notes | First network code in the app → ADR and a lint exception limited to one file. |
| E2-S5 Pipeline | Ready with notes | Recorder needs a terminal "needs attention" state for retry/copy/discard. |
| E2-S6 Exact/Clean | Ready | Pure Domain; fully testable on CI. |
| E2-S7 AX insertion | Ready with notes | 13 points; the app matrix is a manual activity. |
| E2-S8 Clipboard | Ready with notes | Paste keystroke needs Accessibility (already granted for insertion), not Input Monitoring. |
| E2-S9 Settings | Ready | — |
| E2-S10 Validation | Ready with notes | Threshold approval is a product-owner action outside the code. |

No blockers. Size concerns for the two 13-point stories are handled by
keeping their CI-verifiable core in one PR and moving per-app/per-hardware
evidence to the manual checklist (see story notes).

## Cross-cutting decisions (proposed defaults)

1. **Contract** — `SpeechRecognitionEngine` in Domain; `RecognitionRunner`
   enforces "not ready → never called" and "cancelled → never succeeds" for
   every engine; `RecognitionEngineContract` (TestSupport) is the reusable
   contract check. ADR 0009.
2. **Apple Speech** — `SFSpeechRecognizer` with
   `requiresOnDeviceRecognition = true`; if `supportsOnDeviceRecognition` is
   false the engine is *Unavailable*, never network-backed. Speech-recognition
   authorization is modelled inside the engine's availability
   (`permissionUnavailable`) and requested only when the user chooses Apple
   Speech or retries, so onboarding keeps its two core permissions. ADR 0010.
3. **Downloadable model** — whisper.cpp (MIT) as a pinned binary XCFramework
   (v1.9.2, checksum in `Package.swift`) with the English `base.en` ggml model
   (MIT, 142 MiB). Recognition engines live in a new `Recognition` module.
   ADR 0012.
4. **Downloads** — a new `ModelAssets` module is the only code allowed to use
   `URLSession`; it only contacts URLs from the version-controlled catalog,
   only after explicit confirmation, never during dictation; every file is
   verified against its SHA-256 before activation. ADR 0011.
5. **Pipeline** — `DictationPipeline` replaces `DiscardingRecordingConsumer`;
   each recording gets one `TranscriptionSession` with its own ID; results
   from an older session are ignored. The recorder gains a terminal
   `needsAttention` state that carries the recovery choices. ADR 0013.
6. **Cleanup** — `TextCleaner` (Domain, pure) with individually switchable
   rules; every transformation records the rule that made it. ADR 0014.
7. **Delivery** — a new `Delivery` module: Accessibility insertion
   (`kAXSelectedTextAttribute`) first, then clipboard fallback with snapshot
   and change-count-guarded restore. The paste keystroke is posted with
   `CGEvent`, which needs Accessibility only. ADR 0015.
8. **Privacy** — transcripts, partial text, and clipboard contents are never
   logged or written to diagnostics; diagnostics get durations, counts,
   engine IDs, and error identifiers only. Canary-string tests per story.

## Story notes

### E2-S1 — Engine contract — Ready
| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | Developer story enabling S2/S3/S5. |
| 2 | Size | Pass | 5 points. |
| 3 | Dependencies | Pass | E1-S5 merged (`RecordedAudio`). |
| 4 | Acceptance criteria | Pass | All observable in unit tests. |
| 5 | CI testability | Pass | Fake engine; no frameworks. |
| 6 | Privacy | Pass | `Transcript.metrics` is the only diagnostics view. |
| 7 | Permissions | Pass | None. |
| 8 | Feasibility | Pass | — |
| 9 | Out of scope | Pass | — |
| 10 | Open decisions | Concern | Streaming input: proposed batch-only (whole recording) for MVP; partial results still flow through `RecognitionUpdate`. |

### E2-S2 — Apple Speech — Ready with notes
- Needs `NSSpeechRecognitionUsageDescription`; requesting authorization in a
  process without it crashes, so package tests use fakes only.
- "No application-initiated network request" is guaranteed by
  `requiresOnDeviceRecognition`; verified manually with a network monitor (MA).
- Empty audio and silence are detected before the framework is called.

### E2-S3 — Downloadable model — Ready with notes
- 13 points: split proposal — (a) ADR + engine + notices + contract tests
  (this story's PR); (b) benchmark numbers on minimum/recommended hardware are
  recorded through E2-S10's benchmark script and manual checklist.
- Hardware gate: Apple silicon and ≥ 8 GB physical memory.

### E2-S4 — Model assets — Ready with notes
- Pausing is "where supported": cancel keeps `URLSession` resume data so the
  next attempt resumes; corrupt or unverifiable partials are deleted.
- Fallback after removal: dependent engine becomes *Assets missing*; Automatic
  selection falls back to Apple Speech when ready.

### E2-S5 — Pipeline — Ready with notes
- "Copy retained audio intentionally" = Save Audio… to a user-chosen location.
- Crash recovery: no session state is persisted, and recordings are purged at
  launch, so nothing can remain "recording" after a crash.

### E2-S6 — Exact/Clean — Ready
- Exact performs whitespace trimming and collapsing only.
- Protected spans (numbers, URLs, emails, identifiers, quotes) are masked
  before rules run.

### E2-S7 — AX insertion — Ready with notes
- 13 points: core insertion, validation, and typed outcomes ship with tests;
  the eight-app matrix is a manual run recorded in
  `docs/testing/insertion-matrix.md`.
- Verification after insertion reads only the character count
  (`kAXNumberOfCharactersAttribute`), never text; secure fields are detected by
  role/subrole and never read.

### E2-S8 — Clipboard — Ready with notes
- Restoration preserves every type of every item as raw data, which covers
  plain text, rich text, images, and file URLs.

### E2-S9 — Settings — Ready
- New **Dictation** settings pane; menu shows mode and "On this Mac".

### E2-S10 — Validation — Ready with notes
- Corpus audio is synthesised with macOS `say` from a versioned text corpus so
  it is licence-free and reproducible; real-speech accuracy runs are manual.
- Thresholds are proposed in `docs/testing/performance-thresholds.md` and
  marked *Proposed* until a product owner approves them.

## AC → verification map

| Story | Acceptance criterion | Verification |
|---|---|---|
| E2-S1 | Coordinator runs a fake engine without a recognition framework | `RecognitionRunnerTests` (Domain imports Foundation only) |
| E2-S1 | Availability distinguishes ready / assets missing / unsupported / permission / failed | `RecognitionEngineContractTests.availabilityDistinguishesEveryState` |
| E2-S1 | Cancellation cannot emit success afterwards | `RecognitionRunnerTests.cancelledSessionNeverReportsSuccessEvenIfTheEngineReturns`, `updatesStopAfterCancellation` |
| E2-S1 | Transcript model fields | `RecognitionEngineContractTests.transcriptCarriesTextSegmentsTimingEngineLanguageAndDuration` |
| E2-S1 | Reusable contract tests | `RecognitionEngineContract.verify` used by fake, Apple Speech, and Whisper tests |
| E2-S2..S10 | — | Listed in each story's PR and in `docs/testing/manual-acceptance.md` |
