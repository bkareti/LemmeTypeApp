# LemmeType for Android

Native Kotlin ([ADR 0035](../docs/decisions/0035-android-app.md), [plan](../docs/android/android-plan.md)).
Nothing here is built by `make ci`; the Apple apps do not depend on this folder.

## What exists today

Only the pure-Kotlin core, which needs a JDK and no Android SDK:

| Module | What it holds | Swift counterpart | Story |
|---|---|---|---|
| `core-writing` | `TextCleaner` (Exact, Clean, the six rules, protected spans), `RepetitionLoop` | `Domain` cleanup types, `RepetitionLoop` | E14-S9 |
| `core-domain` | `RecorderStateMachine`, `DictationIssue` (beta subset), `RecognitionError`, `SpeechEngine`, `RecognitionRunner`, `ModelCatalog`, `LanguageScope`, `RecordingLimits`, diagnostics values | `Domain` | E14-S8 |
| `core-testing` | `FakeSpeechEngine`, `SpeechEngineContract`, `SharedFixtures` loader | `TestSupport` | E14-S7/S8 |

The Android app, platform adapters, and the Android lint stack come with E14-S6, once the
Android SDK and NDK are installed (they are not needed for anything here).

## Commands

```bash
make android-core-test   # from the repository root: compile (warnings are errors), tests, import rule
```

Requires JDK 21 (`brew install openjdk@21`; the Makefile finds it, or set `JAVA_HOME`).
Gradle comes from the wrapper (`gradlew`, version and SHA-256 pinned).

## Rules

- `core-*` modules are plain Kotlin/JVM. `checkCoreImports` fails on `android.*`, `androidx.*`,
  `java.net.*`, or `javax.swing.*` in their main code.
- Behaviour shared with Swift is tested against `shared/fixtures/` (see its README). Change
  the Swift rule and the fixture first; both test suites must stay green.
- `toString()` of anything that can hold dictated text prints lengths and counts, never the text.

## Differences from Swift (deliberate)

- **Cancellation** surfaces as Kotlin's `CancellationException` (structured concurrency)
  rather than `RecognitionError.cancelled`; an engine may still throw `Cancelled` itself.
- **Errors** travel as `RecognitionFailure(error)`, because Kotlin has no typed `throws`.
- **Diagnostics** live in `core-domain`, as in Swift `Domain` (the plan's separate
  `core-diagnostics` module was folded in; split it only if it grows).
- **Characters**: Swift compares grapheme clusters, Kotlin UTF-16 units. The rules work on
  code points where it matters (numbers, letters, case); a `\r\n` pair is split as two
  characters in Kotlin and kept as one in Swift. Dictated text does not contain `\r\n`.
