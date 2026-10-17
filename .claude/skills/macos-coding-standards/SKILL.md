---
name: macos-coding-standards
description: LemmeType Swift/SwiftUI coding standards for the macOS app — module boundaries, Swift 6 concurrency, dependency injection, privacy-safe logging, errors, accessibility, and testing rules. Load before writing or reviewing any Swift code, Package.swift, project.yml, or xcconfig in this repository.
---

# LemmeType macOS coding standards

These rules apply to every Swift change. `make lint` enforces the mechanical
parts (swift-format + SwiftLint); the rest is enforced in review (see the
`pr-review` skill). When a rule must be broken, say why in a code comment and
in the PR description.

## Toolchain and baseline

- Baseline is recorded in `docs/decisions/0001-platform-baseline.md`. Do not
  change deployment target, architecture, Swift language mode, or Xcode version
  without a new ADR.
- Swift 6 language mode with complete strict concurrency. Warnings are errors
  in the app target (`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES`); keep it that way.
- `project.yml` (XcodeGen) is the source of truth for the Xcode project. Never
  hand-edit or commit `LemmeType.xcodeproj`; run `make generate`.
- Build settings live in `Config/*.xcconfig`, not in `project.yml` `settings:`
  blocks, except for per-target identity (bundle id, Info.plist path).

## Architecture and module boundaries

Code lives in the local package `Packages/LemmeTypeKit` plus a thin app target:

| Module | Contains | May import |
|---|---|---|
| `Domain` | Pure models, state machines, service protocols, typed errors | Foundation only |
| `Support` | Logging, redaction, preferences storage, small utilities | Domain, Foundation, `os` |
| `Audio` | AVFoundation/Core Audio implementations of Domain protocols | Domain, Support |
| `Permissions` | TCC/AX permission implementations | Domain, Support |
| `Shortcuts` | Global shortcut registration and target capture | Domain, Support |
| `Lifecycle` | Login item, single instance, app-lifecycle OS integration | Domain, Support |
| `Recognition` | Speech-recognition engines (Speech framework, local models) | Domain, Support |
| `ModelAssets` | Model download, verification, removal — the only network code (ADR 0011) | Domain, Support |
| `Delivery` | Accessibility insertion and clipboard fallback (ADR 0015) | Domain, Support |
| `Editing` | On-device text rewriting with Apple Foundation Models (ADR 0018) | Domain, Support |
| `UI` | SwiftUI views and view models | Domain, Support |
| App target `LemmeType` | `@main`, `AppComposition` (the only composition root) | everything |

Rules:
- `Domain` never imports AppKit, SwiftUI, AVFoundation, or any OS-service
  framework. Every OS capability is a protocol in `Domain` with a concrete
  implementation in a platform module and a fake in tests.
- `UI` depends on protocols and view models, never on `Audio`, `Permissions`,
  `Shortcuts`, `Lifecycle`, or `Recognition` directly.
- Concrete services are constructed only in `AppComposition`. No singletons, no
  `static let shared`, no service locators. Pass dependencies through
  initializers.
- A new module, or a new edge in the table above, needs an ADR.
- No third-party dependencies without an ADR that names the product benefit,
  license, maintenance status, and privacy/network behavior.

## Concurrency

- UI types, view models, and anything touching AppKit/SwiftUI are `@MainActor`.
- Service protocols are `Sendable`. Long-lived mutable services are `actor`s or
  `@MainActor` classes; do not use `@unchecked Sendable` or `nonisolated(unsafe)`
  without a comment proving safety.
- Prefer `async`/`await` and `AsyncStream` over callbacks, Combine, and
  `DispatchQueue`. Real-time audio callbacks are the exception: keep them
  allocation-free and hand data off without locks that can block.
- Every `Task {}` that outlives its scope is stored and cancelled on teardown.
- Inject time (`Clock`) and randomness so tests are deterministic.

## Errors and state

- Model failures as typed enums conforming to `LemmeTypeError`, each with a
  stable `identifier` (e.g. `"audio.device-unavailable"`) that never changes
  once shipped, plus user-facing message and recovery actions.
- State machines (recorder, permissions) are value types in `Domain` with an
  explicit transition function that rejects invalid transitions. UI reads state;
  it never mutates it directly.
- No `fatalError`, `try!`, force unwraps, or `as!` in production code, except
  for programmer errors that are impossible at runtime (with a comment).

## Privacy (non-negotiable)

- Never log, persist, or include in errors: audio samples or levels, transcripts,
  text from other apps, clipboard contents, or file contents. User vocabulary,
  replacements, and snippets are persisted only by the personalization store
  (ADR 0020) and are never logged or put in diagnostics or errors.
- Log only through `Support.Log` (wraps `os.Logger`). Interpolated values are
  `.private` unless they are enums, identifiers, counts, or durations.
- No `print`, `NSLog`, or `debugPrint` in production code.
- No network APIs (`URLSession`, sockets) outside a module approved by ADR.
  Local mode must stay network-silent.
- Temporary audio goes in the app's protected temporary directory and is deleted
  on cancel, completion, and next launch.

## SwiftUI and AppKit

- Prefer SwiftUI; use AppKit (`NSPanel`, `NSStatusItem`, `NSWorkspace`) only
  where SwiftUI cannot do the job, wrapped behind a small type.
- Windows and panels that appear during dictation must be non-activating and
  must never take focus from the user's target app.
- Every interactive control has an accessibility label; state changes that
  matter (recording started/stopped/failed) are announced for VoiceOver.
- Respect Reduce Motion: no state may be communicated only through animation.
- User-facing strings go through `String(localized:)` / `LocalizedStringKey`.

## Naming and style

- Formatting is whatever `make format` produces; do not fight the formatter.
- Types `UpperCamelCase`, members `lowerCamelCase`, no Hungarian or `LT` prefixes
  inside modules.
- Protocols describe capability (`AudioCapturing`, `PermissionChecking`);
  concrete OS implementations are prefixed with the framework or role
  (`AVAudioCaptureService`); fakes are prefixed `Fake` and live in test targets
  or a `*TestSupport` target.
- One primary type per file, file named after it.
- Comments explain *why*, not *what*. Public API in `Domain` gets a `///` doc
  comment.

## Testing

- Unit tests use Swift Testing (`import Testing`, `@Test`, `#expect`). UI tests
  use XCTest/XCUIAutomation in `LemmeTypeUITests`.
- Every Domain type and state-machine transition has tests, including rejected
  transitions. Platform implementations are tested through their protocol with
  fakes; tests never touch the real microphone, TCC, or global event taps.
- Every story's Given/When/Then acceptance criteria map to a named test or a
  line in a manual checklist under `docs/testing/`.
- Privacy tests use canary strings and assert they never reach logs/diagnostics.
