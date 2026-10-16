# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

LemmeType is a privacy-first macOS menu-bar voice-writing app (global shortcut →
record → local transcription → optional cleanup → insert text at the cursor of
the previously focused app). Epic 1 (foundation) is in progress; E1-S1, the
project scaffold, is implemented.

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
  `Lifecycle` (depend on Domain + Support), `UI` (SwiftUI, depends on Domain + Support only),
  and `TestSupport` (fakes).
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
  table) and hands finished audio to a `RecordingConsumer` (Epic 1:
  `DiscardingRecordingConsumer`; Epic 2: transcription). The overlay is a
  non-activating `NSPanel` that cannot become key.
- Diagnostics: components take `any DiagnosticsRecording` (default
  `DiscardingDiagnostics`); the app shares one `DiagnosticsBuffer`. Event names
  and keys must be literals and values typed (`.id(...)` redacts anything that
  isn't a lowercase identifier) — never pass device/app names or text.
- Debug-only launch arguments: `-LemmeTypeUITesting` swaps in `TestSupport`
  fakes; `-LemmeTypeFreshInstall` (with it) starts with onboarding pending and
  nothing granted; `-LemmeTypeShowSettings` opens Settings at launch. XCUITest cannot
  click status-menu items, so UI tests check menu contents only and use these.
- `LemmeTypeTests` is hosted in the app and must not link package products
  (duplicate type copies break `is` checks); Debug disables dead-code stripping
  so the host app exports those symbols.
- Swift 6 language mode, complete strict concurrency, warnings are errors in
  both the app and the package. Unit tests use Swift Testing; UI tests use XCTest.
- Decisions are in `docs/decisions/` (0001 platform baseline: macOS 26, arm64,
  no App Sandbox because Accessibility insertion needs it; 0002 structure;
  0003 menu-bar lifecycle; 0004 permission model; 0005 global shortcut; 0006 audio capture; 0007 recorder and overlay; 0008 diagnostics).

## Planning documents

- `docs/product-brief.md`, `docs/roadmap.md` — scope, non-goals, epic exit criteria.
- `docs/backlog/epic-0{1,2}-*.md` — development-ready stories (source of truth
  for acceptance criteria). Readiness reviews go in `docs/backlog/reviews/`.
- `docs/testing/manual-acceptance.md` — checks that cannot run on CI.

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
- Adding/removing a story requires updating `STORY_AREA_LABELS` and the
  `verify()` counts (8 for Epic 1, 10 for Epic 2).

## Product constraints that shape implementation

- Local mode is network-silent: no audio, transcript, or cursor context leaves the Mac.
- Never log or persist audio, transcripts, clipboard, or other apps' text; log
  only via `Support.Log` with private interpolation.
- Retention defaults to off; temporary audio is deleted after processing.
- Recording always has visible state and stops on cancel, quit, sleep, or error.
- Exact Dictation never silently rewrites; insertion uses Accessibility first,
  clipboard fallback restores the previous clipboard; nothing is sent automatically.
