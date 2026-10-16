# 0001 — Platform baseline

- Status: Accepted
- Date: 2026-10-16
- Story: E1-S1

## Context

LemmeType needs global activation, microphone capture, Accessibility-based text
insertion into other apps, and fully on-device speech recognition and text
processing. The baseline decides which macOS APIs are available without
availability branching, and which distribution channels remain possible.

## Decision

| Item | Choice |
|---|---|
| Minimum macOS | 26.0 |
| CPU architecture | Apple Silicon (arm64) only |
| Swift | Swift 6 language mode, complete strict concurrency, warnings as errors |
| Xcode | 27.0 (27A266a) with Swift 6.4 — the version used to build and test |
| Bundle identifier | `com.lemmetype.LemmeType` |
| App Sandbox | Off |
| Hardened Runtime | On for Release; off for Debug |
| Development signing | Ad-hoc (`-`) by default; team signing through `Config/Signing.local.xcconfig` |
| Release signing (assumed) | Developer ID + notarization, direct distribution |

## Rationale

- **macOS 26**: provides the on-device `SpeechAnalyzer`/`SpeechTranscriber`
  APIs (Epic 2) and the Foundation Models framework (Epic 3) without
  maintaining fallbacks for older systems.
- **arm64 only**: local speech and language models need the Neural Engine and
  unified memory; Intel Macs cannot meet the latency goals.
- **No App Sandbox**: a sandboxed app cannot use the Accessibility API to read
  the focused element of, or insert text into, another application, which is
  the core workflow (E1-S4 target capture, E2-S7 insertion). This makes the Mac
  App Store unlikely; Epic 7 owns the final distribution decision.
- **Hardened Runtime off in Debug**: hosted unit tests inject a test bundle into
  the app, which library validation blocks for ad-hoc–signed builds.

## Consequences

- Release builds need the `com.apple.security.device.audio-input` entitlement
  (present in `App/LemmeType/LemmeType.entitlements`) for microphone access
  under Hardened Runtime.
- Ad-hoc–signed builds get a new code identity on every build, so macOS
  forgets Microphone/Accessibility grants. Developers working on permission or
  insertion stories should use team signing.
- Changing the bundle identifier later resets every user's permission grants;
  settle it before the first external build.
- Raising the minimum macOS or Xcode version requires a new ADR.
