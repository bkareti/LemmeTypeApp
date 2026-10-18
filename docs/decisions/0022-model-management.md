# 0022 — Model catalog, verification before use, and performance plans

- Status: Accepted
- Date: 2026-10-18
- Stories: E5-S1 … E5-S6

## Context

Epic 2 shipped one downloadable model (Whisper Base) that stayed loaded until
the user freed it. Epic 5 adds smaller and larger models, checks files before
use, and adapts memory and CPU use to the Mac's state.

## Decision

- **Catalog** — Whisper Tiny, Base, and Small (English, MIT) from the same
  allowlisted host and repository as ADR 0011, each pinned by size and SHA-256
  (the repository's LFS object ids are SHA-256). Each entry adds a
  `ModelTier`, approximate `runtimeMemoryBytes` (whisper.cpp's published
  figures), and a recommended memory; `HardwareRequirement.fit(for:)` gives
  `recommended`, `supported`, or `unsupported(reason)`. Base keeps its id and
  version folder, so existing installs need no download.
- **One engine, chosen model** — the `whisper` engine id is unchanged. It runs
  `WhisperModelChoice`: `automatic` (default) takes the first installed model
  in the performance plan's order; `specific` never falls back to another model
  (availability is `assetsMissing`). The descriptor still advertises Base as
  the default download.
- **Verify before use** — `ModelAssetManaging.verifiedFile(for:named:)`
  re-checks size and SHA-256 before a model is loaded for the first time in a
  launch, or when its size or modification date changed. A mismatch deletes the
  active copy and reports `model.digest-mismatch` until a fresh install;
  availability checks use the cheap `installedFile`.
- **Recovery** — transient network failures (timed out, connection lost, not
  connected, DNS) retry twice (2 s, 5 s) from the resume data; quitting pauses
  active downloads so their resume data is saved.
- **Performance plan** — pure `PerformancePlan.make(profile:conditions:idleUnload:)`:

  | Plan | Whisper order | Threads | GPU | Warm-up | Idle unload |
  |---|---|---|---|---|---|
  | Balanced | Base, Small, Tiny | cores − 2 (≤ 8) | on | on | setting |
  | Low Power | Tiny, Base, Small | 2 | off | off | ≤ 1 min |
  | Best Accuracy | Small, Base, Tiny | cores − 2 (≤ 8) | on | on | setting |

  Automatic is Low Power in macOS Low Power Mode, otherwise Balanced. Serious
  or critical thermal state lowers every profile to Low Power. A GPU change
  reloads the model on next use.
- **Residency** — `ModelResidencyController` (Domain actor, injected
  `Clock`): the recorder marks a session busy from recording start through
  processing and idle when it ends (calls queued in order). Busy cancels the
  idle timer and, when the plan allows, warms up the preferred (or first
  ready) engine while the user speaks. After the plan's idle period every
  engine is unloaded. Memory pressure unloads at once, or right after a busy
  session. Nothing loads at launch.
- **System conditions** — `SystemConditionsMonitor` (`Lifecycle`):
  `DispatchSource` memory-pressure events plus `ProcessInfo` thermal and
  power-state notifications; no permission. `AppController` forwards
  memory-pressure warnings to residency and shows reductions in Settings.
- **Low storage** — recording refuses to start with less than 100 MB free on
  the temporary-audio volume (`audio.insufficient-storage`).
- **UI** — Settings › Dictation › Models (the window has no room for a new
  tab). The Engine section links there instead of duplicating model controls.

## Consequences

- Small needs about 850 MB while loaded; it is "supported, more memory
  recommended" below 16 GB and never chosen automatically except by Best Accuracy.
- Verification costs about a second for Small on first use per launch.
