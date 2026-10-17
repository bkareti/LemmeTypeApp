# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

LemmeType is a privacy-first macOS menu-bar voice-writing app (global shortcut →
record → local transcription → optional cleanup → insert text at the cursor of
the previously focused app). Epics 1–3 (foundation, local transcription and delivery, context-aware
writing and voice editing) are complete; Epics 4 (personalization and modes)
and 5 (model management and performance) are in progress.

## Project skills — use them

Skills in `.claude/skills/` define how work is done here:

- `story-review` — readiness review of a story before any code is written.
- `macos-development` — the end-to-end workflow for implementing a story.
- `macos-coding-standards` — load before writing or reviewing Swift.
- `pr-review` — review a PR or branch against its story and the standards.
- `release-management` — versioning, archive, notarize, publish, rollback.

## Commands

```bash
make bootstrap   # check Xcode 27 + Homebrew xcodegen/swiftlint
make generate    # regenerate LemmeType.xcodeproj from project.yml
make build       # Debug build
make test        # everything: package tests, LemmeTypeTests, LemmeTypeUITests
make test-unit   # fast: swift test on Packages/LemmeTypeKit
make lint        # swift-format lint --strict + swiftlint --strict
make ci          # what the required CI job runs
make privacy-check  # fail if captured audio was left behind
make benchmark   # end-to-end benchmark on this Mac + threshold check (not CI)
make release-check APP=<app|zip>  # thresholds + release-artifact scan
make format      # apply swift-format
make run         # build and launch
```

Single tests:

```bash
swift test --package-path Packages/LemmeTypeKit --filter StatusViewModelTests
xcodebuild -project LemmeType.xcodeproj -scheme LemmeType -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData test -only-testing:LemmeTypeTests/AppCompositionTests
```

## Architecture

- `project.yml` (XcodeGen) is the source of truth; `LemmeType.xcodeproj` is
  generated and gitignored. Run `make generate` after adding files to `App/`.
  Build settings live in `Config/*.xcconfig`; version only in `Config/Version.xcconfig`.
- Feature code lives in the local package `Packages/LemmeTypeKit`, one target per
  module: `Domain` (models, protocols, state, no OS frameworks), `Support`
  (`Log`, `BuildInfo`, `UserDefaultsPreferences`; depends on Domain), platform modules `Audio` / `Permissions` / `Shortcuts` /
  `Lifecycle` / `Recognition` / `ModelAssets` / `Delivery` / `Editing` (depend on Domain + Support), `UI` (SwiftUI, depends on Domain + Support only),
  and `TestSupport` (fakes, plus the Debug-only `DictationBenchmark`).
  `EndToEndTests` drives recorder → pipeline → cleaner → delivery (and, for
  Epic 3, shortcut → context reader → formatter/rewriter → delivery) with
  fakes only at the OS edges.
- The app target (`App/LemmeType`) holds only `LemmeTypeApp` and
  `AppComposition`, the single composition root where concrete OS services are
  created, plus `AppDelegate` (single instance) and `AppController` (menu
  actions). The app is an agent (`LSUIElement`) whose only scene is a
  `MenuBarExtra`; Settings is an AppKit window owned by `SettingsWindowController`.
- One `PermissionsModel` (UI module) is shared by onboarding, Settings, and the
  menu; it polls while visible because Accessibility has no change notification.
- Dictation activation: `CarbonHotKeyRegistrar` → `ActivationController`
  (Shortcuts) → `ActivationInterpreter` (Domain, pure: repeats/bounce/modes) →
  `ActivationCommand` (start with captured target / stop / cancel) delivered to
  `AppController.handle(_:)`. UI talks to it via `DictationShortcutControlling`.
  Escape is a hot key only during a session.
- Audio: `AudioSource` (Domain; `AVAudioEngineSource` real, `FakeAudioSource`
  in tests and UI tests) → `AudioCaptureService` actor (permission check,
  resample to 16 kHz mono Float32, level meter, 0600 temp CAF, typed failures)
  → `AsyncStream<AudioCaptureEvent>`. Session files are purged at launch.
- Recording: `RecordingCoordinator` (UI, the only `AudioCapturing` caller)
  serialises commands through `RecorderStateMachine` (Domain, pure transition
  table). Each finished recording becomes a `DictationSession` processed by a
  `DictationProcessing` (`TranscriptionPipeline`, Domain: engine selection →
  recognition → writing mode → `TextDelivering`) in its own task; stale
  results are ignored. Failures that need a decision put the recorder in
  `needsAttention(DictationIssue)` with actions (retry, other engine, copy,
  save audio, discard) and keep the audio until then. The overlay is a
  non-activating `NSPanel` that cannot become key.
- Recognition: engines implement `SpeechRecognitionEngine` (Domain) and are
  always called through `RecognitionRunner`, which guarantees that a not-ready
  engine is never called and a cancelled session never succeeds.
  `FakeRecognitionEngine` and `RecognitionEngineContract` (TestSupport) are the
  fake and the reusable contract check every engine's tests must run.
  Concrete engines live in the `Recognition` module (`AppleSpeechEngine`:
  `SFSpeechRecognizer`, on-device only; Speech Recognition authorization via
  `SpeechRecognitionAuthorizing`, separate from `PermissionKind`;
  `WhisperEngine`: whisper.cpp v1.9.2 binary XCFramework + downloadable
  `base.en`, Apple silicon with ≥ 8 GB only). Third-party notices live in
  `THIRD_PARTY_NOTICES.md` and `App/LemmeType/Credits.rtf` — update both.
  `scripts/run-recognition-benchmark.sh` runs the opt-in benchmark.
- Models: `ModelCatalog` (Domain) pins every downloadable file by URL, size,
  and SHA-256. `ModelAssetStore` (ModelAssets) stages, verifies, activates,
  and removes them; `URLSessionModelDownloader` is the only network code in
  the app (lint exception in that file only) and needs a `ModelDownloadConsent`.
- Writing modes (ADR 0014): `TextCleaner` (Domain, pure) is the pipeline's
  `write` step. Exact only
  normalises whitespace; Clean runs ordered, individually switchable
  `CleanupRule`s over tokens, never touching protected spans (numbers, URLs,
  emails, identifiers, quotes). Every change is a `CleanupTransformation`
  naming its rule; `TextCleanerTests` holds the before/after corpus.
- Delivery (ADR 0015): `DictationTextDelivery` (Delivery) validates the
  captured target via `AccessibilityDriving` (Domain; `SystemAccessibilityDriver`
  real, `FakeAccessibilityDriver` in TestSupport), inserts once with
  `kAXSelectedText`, verifies by character count (never reads text), and
  only when insertion verifiably didn't happen uses the
  `ClipboardFallbackPolicy` (paste with change-count-guarded restore via
  `PasteboardAccessing`/`PasteKeystrokePosting`, copy only, or off).
  Changed targets, password fields, and secure input never receive text.
- Cursor context (ADR 0017): `CursorContextReader` (Domain, generic over
  `AccessibilityDriving`) reads ≤240 UTF-16 units before / ≤40 after the
  caret (and, for voice editing, the selection ≤4,000) only inside the
  shortcut handler via `TargetCapturing.captureTarget(purpose:)`. Checks run
  policy → trust → element → password field → secure input first.
  `ContextPolicy`: formatting context off by default, voice editing on,
  user exclusions, built-in sensitive apps. Result rides on
  `ActivationTarget.context` (redacted description); diagnostics get the
  outcome identifier only.
- Context formatting (E3-S3): `ContextFormatter` (Domain, pure) runs after
  the writing mode when the session has formatting context. Exact: spacing
  only; Clean: also continuation case (only `commonWords` are lower-cased),
  mid-sentence period, duplicate punctuation. Each change is a
  `ContextTransformation` naming its `ContextRule`.
- Rewriting (ADR 0018): `TextRewriting` (Domain) via `TextRewritingRunner`;
  `FoundationModelsRewriter` (`Editing`) uses on-device `SystemLanguageModel`
  only, a fresh session per request. `FakeTextRewriter` /
  `TextRewriterContract` in TestSupport; real-model test is opt-in with
  `LEMMETYPE_REAL_REWRITE=1`.
- Voice editing (ADR 0019): `ActivationController` has an optional second
  shortcut (default ⌥⇧Space) → `ActivationCommand.startEditing`;
  `DictationSession.purpose` `.editing` makes the pipeline rewrite the
  captured selection with the spoken instruction. `editingIssue(for:)` lets
  the recorder refuse (`preparing → needsAttention`) before recording;
  delivery refuses if the selection changed. Settings › Context
  (`ContextSettingsModel`) holds the switches, model status, and exclusions.
- Personalization (ADR 0020): `PersonalizationLibrary` (Domain; vocabulary,
  replacements, snippets; validated on every change) is stored by
  `FilePersonalizationStore` (Support; versioned JSON in Application Support,
  0600, unreadable files moved aside) and held by `PersonalizationModel` (UI).
  The recorder snapshots it into `DictationSession.personalization` at start.
  Pipeline order: hints → `SnippetMatcher` (whole utterance) → writing mode →
  `Personalizer` (whole words, longest first, one pass) → `ContextFormatter`.
- Engine/mode selection (ADR 0016): `DictationSettingsModel` (UI) backs
  Settings › Dictation and the status menu. Mode, language, and
  `EnginePreference` are captured when recording starts and stored in the
  session; a not-ready chosen engine is never swapped unless the user turned
  on `fallsBackToReadyEngine`.
- Diagnostics: components take `any DiagnosticsRecording` (default
  `DiscardingDiagnostics`); the app shares one `DiagnosticsBuffer`. Event names
  and keys must be literals and values typed (`.id(...)` redacts anything that
  isn't a lowercase identifier) — never pass device/app names or text.
- Debug-only launch arguments: `-LemmeTypeUITesting` swaps in `TestSupport`
  fakes; `-LemmeTypeFreshInstall` (with it) starts with onboarding pending and
  nothing granted; `-LemmeTypeShowSettings` opens Settings at launch;
  `-LemmeTypeBenchmark <corpus> <dir>` runs the end-to-end benchmark in the
  live app and quits (`App/LemmeType/AppComposition+Benchmark.swift`). XCUITest cannot
  click status-menu items, so UI tests check menu contents only and use these.
- `LemmeTypeTests` is hosted in the app and must not link package products
  (duplicate type copies break `is` checks); Debug disables dead-code stripping
  so the host app exports those symbols.
- Swift 6 language mode, complete strict concurrency, warnings are errors in
  both the app and the package. Unit tests use Swift Testing; UI tests use XCTest.
- Decisions are in `docs/decisions/` (0001 platform baseline: macOS 26, arm64,
  no App Sandbox because Accessibility insertion needs it; 0002 structure;
  0003 menu-bar lifecycle; 0004 permission model; 0005 global shortcut; 0006 audio capture; 0007 recorder and overlay; 0008 diagnostics; 0009 recognition-engine contract; 0010 Apple Speech; 0011 model downloads; 0012 whisper.cpp model; 0013 dictation sessions; 0014 writing modes; 0015 text delivery; 0016 engine and mode selection; 0017 cursor context; 0018 on-device rewriting; 0019 voice editing; 0020 personalization data).

## Planning documents

- `docs/product-brief.md`, `docs/roadmap.md` — scope, non-goals, epic exit criteria.
- `docs/backlog/epic-0{1,2,3}-*.md` — development-ready stories (source of truth
  for acceptance criteria). Readiness reviews go in `docs/backlog/reviews/`.
- `docs/testing/manual-acceptance.md` — checks that cannot run on CI.
- `docs/testing/insertion-matrix.md` — per-app insertion results and failure evidence.
- `docs/testing/performance-thresholds.md` (+ `.json`) — benchmark metrics and
  the release thresholds (Proposed until a product owner approves).

### CI

`.github/workflows/ci.yml` runs `make ci` steps (lint, build, `test-unit`,
`test-app`, `privacy-check`) as the required job on every PR and push to
`main`, plus a non-blocking `ui-tests` job (`make test-ui`). It uses the
`xcode-27` runner image (public preview), because `macos-26`/`macos-latest` only
have Xcode 26. `make privacy-check` fails if any `.caf/.wav/.m4a` is left under
`$TMPDIR/LemmeType*` or the repo — test temp directories must use the
`LemmeTypeTests-` prefix. Never add artifact uploads that could capture logs or
test results containing user data.

UI tests need macOS UI Automation Mode. Locally it can require authentication
(`automationmodetool`); if XCUITest reports "Timed out while enabling automation
mode", re-enable it yourself. A failing UI assertion can stall for minutes while
XCTest symbolicates (it reads object files in `build/DerivedData`).

### Backlog sync to GitHub

`python3 .github/scripts/sync_backlog.py` creates labels, epic issues, and story
sub-issues on `bkareti/LemmeTypeApp` (needs authenticated `gh`).

- Idempotent by **exact issue title**: renaming a story heading creates a
  duplicate issue; existing issue bodies are never updated.
- The parser relies on structure: `## Epic N — Title` headings (em dash, exactly
  8) then `## Dependency order` in `roadmap.md`; backlog files need
  `## Epic issue body`, `## EN-SM — Title` stories separated by `---`, and a
  final `## Epic N story order` section.
- Refined epics are listed in `REFINED_EPICS` (backlog file, story phase
  label, story count: 8 for Epic 1, 10 for Epic 2, 7 for Epic 3). Adding or
  removing a story requires updating `STORY_AREA_LABELS` and that count.

## Product constraints that shape implementation

- Local mode is network-silent: no audio, transcript, or cursor context leaves the Mac.
- Never log or persist audio, transcripts, clipboard, or other apps' text; log
  only via `Support.Log` with private interpolation.
- Retention defaults to off; temporary audio is deleted after processing.
- Recording always has visible state and stops on cancel, quit, sleep, or error.
- Exact Dictation never silently rewrites; insertion uses Accessibility first,
  clipboard fallback restores the previous clipboard; nothing is sent automatically.
