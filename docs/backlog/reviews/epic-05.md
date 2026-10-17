# Readiness review — Epic 5 (model management and performance)

Reviewed 2026-10-18 with the `story-review` skill against
`docs/backlog/epic-05-model-management.md`, the Epic 3 code on `main`,
ADRs 0009–0016, and the whisper.cpp v1.9.2 API.

## Summary

| Story | Verdict | Main points |
|---|---|---|
| E5-S1 Catalog and fit | Ready | Tiny/Small pinned from the same host and repository as Base. |
| E5-S2 Models pane | Ready | Model controls move from Dictation to a new pane. |
| E5-S3 Verification and recovery | Ready with notes | Hashing 488 MB takes ~1 s on M-series; runs off the main actor, once per launch. |
| E5-S4 Lazy load and idle unload | Ready | Injected clock makes timing testable. |
| E5-S5 Profiles | Ready with notes | GPU switch needs a reload; done lazily on next use. |
| E5-S6 System conditions | Ready with notes | Real memory/thermal events are manual; logic tested with a fake monitor. |
| E5-S7 Validation | Ready with notes | Threshold approval is a product-owner action. |

No blockers.

## Cross-cutting decisions (proposed defaults)

1. **Catalog** — add `ggml-tiny.en.bin` (77.7 MB) and `ggml-small.en.bin`
   (487.6 MB) from `huggingface.co/ggerganov/whisper.cpp`, pinned by size and
   SHA-256 (the repository's LFS object ids, which are SHA-256). Same allowlisted
   host as ADR 0011; no new network code. Minimum memory 8 GB for all three;
   recommended 8 / 8 / 16 GB.
2. **One Whisper engine** — still one `.whisper` engine id; it runs the
   resolved model. `WhisperModelChoice` is `automatic` (default) or a
   specific asset. Automatic asks the performance plan for its model order and
   takes the first installed one. The engine descriptor keeps
   `.downloadable(.whisperBaseEnglish)` as its default download. ADR 0022.
3. **Verification** — `ModelAssetManaging.verifiedFile(for:named:)` hashes the
   active file once per launch (cache keyed by size + modification date) before
   any load. Mismatch → active copy deleted, `model.digest-mismatch`.
4. **Retries** — 2 automatic retries for transient `URLError` codes (timed out,
   connection lost, not connected) with 2 s and 5 s back-off; resume data is
   used for each retry.
5. **Residency** — `ModelResidencyController` (Domain actor, injected `Clock`):
   `sessionStarted()` cancels the idle timer and optionally warms up;
   `sessionEnded()` starts it; `unloadNow(reason:)` for memory pressure. The
   recorder reports session start/end. Default idle period 5 minutes.
6. **Profiles** — pure `PerformancePlan.plan(for:conditions:)`:

   | Profile | Whisper order | Threads | GPU | Warm-up | Idle unload |
   |---|---|---|---|---|---|
   | Balanced | Base, Small, Tiny | cores − 2 (≤ 8) | on | on | setting |
   | Low Power | Tiny, Base, Small | 2 | off | off | ≤ 1 min |
   | Best Accuracy | Small, Base, Tiny | cores − 2 (≤ 8) | on | on | setting |

   Automatic = Low Power when Low Power Mode is on or thermal state is serious
   or critical, otherwise Balanced. An explicit profile is also lowered to Low
   Power at serious/critical thermal state.
7. **System conditions** — `SystemConditionsMonitor` in `Lifecycle`
   (`DispatchSource.makeMemoryPressureSource`, `ProcessInfo` thermal and power
   notifications). No new permission.
8. **Low storage** — `AudioCaptureError.insufficientStorage` when the temporary
   directory's volume has < 100 MB available for important usage.

## AC → verification map

| Acceptance criterion | Verification |
|---|---|
| S1 catalog fields and fit | `ModelCatalogTests`, `ModelFitTests` |
| S1 chosen model not installed / Base keeps working | `WhisperEngineTests` |
| S2 pane | `ModelsSettingsModelTests` + manual MA-50 |
| S3 tampered file never loaded, once per launch | `ModelAssetStoreTests`, `WhisperEngineTests` |
| S3 quit keeps progress, retries | `ModelAssetStoreTests` + manual MA-51 |
| S4 lazy, warm-up, idle unload | `ModelResidencyControllerTests`, `RecordingCoordinatorTests` |
| S5 plans, Automatic, model order, reload | `PerformancePlanTests`, `WhisperEngineTests` |
| S6 memory, thermal, storage | `ModelResidencyControllerTests`, `PerformancePlanTests`, `AudioCaptureServiceTests` + manual MA-52 |
| S7 end-to-end, benchmark, thresholds | `PerformanceEndToEndTests`, `scripts/run-recognition-benchmark.sh`, `performance-thresholds.md` |
