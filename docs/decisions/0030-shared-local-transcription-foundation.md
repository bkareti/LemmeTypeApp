# 0030 — A shared local transcription foundation for LemmeType and MeetQyl

- Status: **Proposed** (needs the maintainer's go-ahead before any code moves)
- Date: 2026-11-04
- Same proposal in MeetQyl: `docs/adr/0033-shared-local-transcription-foundation.md`
  (`bkareti/LocalMeetTranscript`)

## Context

LemmeType (dictation, macOS and iPhone) and MeetQyl (meetings, macOS) both turn
English speech into text on the device. They were built separately and solve
several of the same problems twice:

| Concern | LemmeType | MeetQyl |
|---|---|---|
| Engine | whisper.cpp 1.9.2 XCFramework (`WhisperEngine`) + Apple Speech | WhisperKit 1.1.1 (Core ML) + SpeakerKit |
| Engine contract | `SpeechRecognitionEngine`, `RecognitionRunner`, `RecognitionEngineContract` | `Transcriber`, `TranscriptionQueue` |
| Pinned models | `ModelCatalog` (URL, size, SHA-256), `ModelAssetStore` | `ModelCatalog`, `ModelManager` (Hugging Face tree checksums) |
| Device fit | `HardwareProfile`, `ModelFit`, `PerformancePlan` | recommended model by memory |
| Silence / loop safety | `NoSpeechGate`, `RepetitionLoop` (ADR 0028) | `CoverageChecker`, `TranscriptQuality` (hallucination, repetition) |
| Scoring | `TranscriptScore`, `NumberNormalizer`, corpus manifests | `WordErrorRate` (NFKC), benchmark |
| Diagnostics | counts and identifiers only | counts and identifiers only |

The engines differ on purpose: whisper.cpp is small, starts fast, and runs on
iPhone without a Core ML compile; WhisperKit brings SpeakerKit for meetings.
Forcing one engine on both apps now would put the friends beta at risk for no
user-visible gain.

## Proposal

A separate Swift package, **`LocalSpeechKit`**, in its own repository
(`bkareti/LocalSpeechKit`), Foundation only, macOS 15+ / iOS 18+ (the lower of
the two apps' baselines). Each app depends on it with an **exact** version pin,
like every other dependency in both repositories.

| Product | What it holds | What it never holds |
|---|---|---|
| `SpeechEvaluation` (phase 1) | Text normalization, WER/CER, repetition-loop and no-speech rules, the corpus manifest and report schemas, golden fixtures | Audio, corpus files, any engine |
| `SpeechCore` (phase 2) | The engine contract (request, progress, cancellation, typed errors), pinned model descriptor and SHA-256 verification, device-capability and model-fit rules, the 16 kHz mono Float32 audio contract and resampler, privacy-safe diagnostics *event types* | Recording, sessions, storage, delivery, UI, permissions, logging sinks |
| `LanguagePacks` (future) | A language's models, support status, and the measurement that validated it | Any language before it is measured |

Engine adapters stay in each app (whisper.cpp in LemmeType, WhisperKit in
MeetQyl) and implement the shared contract. Product behavior (dictation cleanup,
cursor delivery, meeting chunking, echo removal, speaker separation, retention)
stays in each app.

### Versioning

- Semantic versions, tags `X.Y.Z`. A change to a public type or a scoring rule is
  a major version, because it changes both apps' reported accuracy.
- The package's CI runs `swift test` on macOS and the iOS Simulator; both apps'
  CI keep running their own contract tests against it.
- Each app records the dependency where it already records dependencies:
  LemmeType `docs/security/dependencies-allowlist.txt` and `THIRD_PARTY_NOTICES.md`;
  MeetQyl `docs/dependencies.md`, `THIRD_PARTY_NOTICES.md`, the module-rules table,
  `Scripts/check-module-rules.sh`, and ADR-009.

### Order

1. **Not before the friends beta.** The beta ships with today's code.
2. Phase 1: move the scoring rules. Both apps' existing evaluation fixtures must
   give identical numbers before and after (golden tests), so no accuracy claim
   silently changes.
3. Phase 2: move the engine contract and model pinning, one app at a time, with
   each app's engine contract tests unchanged.
4. Language packs only after a language is validated (LemmeType ADR 0029).

## Alternatives considered

| Option | Why not now |
|---|---|
| Copy code between the repositories | Drifts immediately; the two scoring rules already differ. |
| A monorepo | Two release cadences, two privacy models (MeetQyl has opt-in cloud AI; LemmeType has none); merging histories is a large move for a beta. |
| One engine for both apps | Loses SpeakerKit (MeetQyl) or the small iPhone footprint (LemmeType). |
| A git submodule | Harder to pin and review than an SPM exact version. |

## What the maintainer decides

- Create `bkareti/LocalSpeechKit` (public or private) and approve phase 1.
- Or keep the apps separate and close this proposal.
