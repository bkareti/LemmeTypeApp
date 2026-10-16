# 0002 — Project structure, tooling, and tests

- Status: Accepted
- Date: 2026-10-16
- Story: E1-S1

## Decision

- **XcodeGen** generates `LemmeType.xcodeproj` from `project.yml`; the project
  file is gitignored. Build settings live in `Config/*.xcconfig`.
- Feature code lives in the local Swift package `Packages/LemmeTypeKit`, one
  target per module: `Domain`, `Support`, `Audio`, `Permissions`, `Shortcuts`,
  `Lifecycle` (added in ADR 0003), `Recognition` (added in ADR 0010), `ModelAssets` (ADR 0011), `UI`, plus `TestSupport` for fakes. The app target `LemmeType` holds only the
  entry point and `AppComposition`, the single composition root.
- Dependency rules: `Domain` and `Support` depend on nothing internal; platform
  modules depend on `Domain` + `Support`; `UI` depends on `Domain` + `Support`
  only; the app target composes everything.
- **Tests**: Swift Testing for unit tests (package test targets and
  `LemmeTypeTests`), XCTest UI automation for `LemmeTypeUITests`. The `LemmeType`
  scheme runs all of them.
- **Fakes**: `TestSupport` fakes are linked into the app but compiled into the
  composition only in Debug, behind the `-LemmeTypeUITesting` launch argument,
  so UI tests never touch real permissions or audio hardware.
- **Formatting and lint**: Xcode's bundled `swift-format` owns layout;
  SwiftLint adds correctness and privacy rules (no `print`/`NSLog`, no shared
  singletons, no network APIs).
- **No third-party runtime dependencies.** Homebrew tools (`xcodegen`,
  `swiftlint`) are development-only.

## Rationale

A local package gives fast `swift test` runs without launching the app,
compiler-enforced module boundaries, and merge-friendly target definitions.
Generating the Xcode project avoids `.pbxproj` conflicts.

## Consequences

- After adding files to the app or test targets, run `make generate`.
- `LemmeTypeTests` must not link package products: they come from the host app,
  and a second copy breaks type identity. Debug disables dead-code stripping so
  those symbols stay available to the test bundle.
- Developers need Homebrew `xcodegen` and `swiftlint` (`make bootstrap` checks).
