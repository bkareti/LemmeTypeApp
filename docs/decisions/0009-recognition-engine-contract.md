# 0009 — Recognition-engine contract

- Status: Accepted
- Date: 2026-10-16
- Story: E2-S1

## Context

Epic 2 adds Apple Speech and a downloadable model, and later epics may add
more. Recording, session, and UI code must not depend on any of them.

## Decision

- `SpeechRecognitionEngine` (Domain) is the only way to recognise speech. It
  exposes a provider-neutral `EngineDescriptor` (id, processing location,
  languages, asset requirement, capabilities), `availability()`, `prepare()`,
  `recognize(_:updates:)`, and `unload()`. No provider types cross it.
- **Batch input**: an engine receives the finished `RecordedAudio` file. Partial
  text and progress flow back through `RecognitionUpdate`. Streaming input can
  be added later as a separate capability without changing callers.
- **Availability** is one of `ready`, `assetsMissing`, `unsupported(reason)`,
  `permissionUnavailable`, `failed(error)`. Each maps to the error
  `recognize` must throw when not ready.
- **Cancellation** is Swift task cancellation. Engines must stop promptly and
  throw `RecognitionError.cancelled`. `RecognitionRunner` wraps every call and
  guarantees that after cancellation no update is forwarded and no transcript
  is returned, even from a misbehaving engine.
- **Local only**: engines must not initiate network requests while preparing
  or recognising. Downloads are a separate, user-confirmed step (ADR 0011).
- **Privacy**: `Transcript` holds dictated text in memory only.
  `Transcript.metrics` is the diagnostics view (engine, durations, counts).
- **Contract tests**: `RecognitionEngineContract.verify` (TestSupport) returns
  violations as strings so every engine's test target can reuse it without
  linking a test framework into the app.

## Consequences

- New engines need only an implementation, a descriptor, and a test calling
  `RecognitionEngineContract.verify`.
- Errors carry numeric framework codes only, never framework messages.
