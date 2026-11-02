# LemmeType

**Speak naturally. Write instantly.**

LemmeType is a privacy-first macOS voice-writing application. A user places the
cursor in any editable field, activates a global shortcut, speaks naturally,
and receives polished text at the cursor. Speech recognition, cleanup, and
context processing are local-first and designed to work without an account or
continuous internet connection.

## Product principles

- Local-first: audio and text stay on the user's Mac by default.
- Explicit: users can distinguish exact transcription from rewritten text.
- System-wide: the core workflow works across common macOS applications.
- Fast: starting, stopping, and inserting a short dictation should feel immediate.
- Respectful: sensitive context is never captured silently or retained by default.

## Repository status

Epics 1 to 5, 9, and 10 are complete: the menu-bar app, local transcription and text
delivery, context-aware writing and voice editing, personalization and modes, model
management, multilingual dictation, and tone and style rewriting. Epics 6 (privacy,
security, and data controls) and 7 (quality, packaging, and release readiness) add the
opt-in history, the Privacy pane, the CI guardrails, the verified release pipeline, the
update check, crash recovery, and the support tools. Epic 8 (iPhone and iPad) has not
started. There is no public release yet; see the [changelog](CHANGELOG.md).

## Building and testing

Requirements: an Apple Silicon Mac on macOS 26 or later, Xcode 27.0, and
Homebrew `xcodegen` and `swiftlint` (`brew install xcodegen swiftlint`).

```bash
make bootstrap   # check the toolchain
make build       # generate LemmeType.xcodeproj and build the Debug app
make test        # package unit tests, app unit tests, and UI tests
make test-unit   # fast package-only unit tests
make lint        # swift-format + SwiftLint
make run         # build and launch
make quality-gate  # every automated check, one summary
```

`LemmeType.xcodeproj` is generated from `project.yml` and is not committed;
open it after `make generate`. To keep macOS permission grants across rebuilds,
copy `Config/Signing.local.xcconfig.example` to `Config/Signing.local.xcconfig`
and set your team.

Platform and structure decisions: [ADR 0001](docs/decisions/0001-platform-baseline.md),
[ADR 0002](docs/decisions/0002-project-structure.md).

## Planning documents

- [Product brief](docs/product-brief.md)
- [Product roadmap and epics](docs/roadmap.md)
- [Epic 1 — macOS foundation and audio capture](docs/backlog/epic-01-macos-foundation.md)
- [Epic 2 — local dictation and text delivery](docs/backlog/epic-02-local-dictation.md)
- [Epic 6 — privacy, security, and data controls](docs/backlog/epic-06-privacy-security.md)
- [Epic 7 — quality, packaging, and release readiness](docs/backlog/epic-07-quality-release.md)

## Privacy, security, and releases

- [Privacy threat model](docs/security/threat-model.md) and [release checklist](docs/security/privacy-release-checklist.md)
- [Release runbook](docs/release/runbook.md), [beta program](docs/release/beta-program.md), [rollback](docs/release/rollback.md)
- [Compatibility matrix and quality gate](docs/testing/compatibility-matrix.md)

## Initial delivery sequence

1. Prove global activation, audio recording, and a stable menu-bar lifecycle.
2. Prove local transcription and reliable insertion into the previously focused app.
3. Add context-aware writing and selected-text voice editing.
4. Add personalization, model management, privacy controls, and release hardening.

## License

No license has been selected yet. All rights are reserved until a license is
added explicitly.
