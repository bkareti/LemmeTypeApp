# 0010 — Apple Speech engine

- Status: Accepted
- Date: 2026-10-16
- Story: E2-S2

## Decision

- **API**: `SFSpeechRecognizer` with `SFSpeechURLRecognitionRequest` on the
  finished session recording, `requiresOnDeviceRecognition = true`,
  `addsPunctuation = true`, task hint `.dictation`, partial results on.
  `SpeechAnalyzer` (macOS 26) is a candidate replacement once it has been
  evaluated on the supported hardware; it fits the same engine contract.
- **Never off-device**: if `supportsOnDeviceRecognition` is false for the
  language the engine reports `unsupported(.onDeviceRecognitionUnavailable)`
  and is not offered; there is no code path that allows server recognition.
- **Authorization** is a separate TCC permission (Speech Recognition) modelled by
  `SpeechRecognitionAuthorizing`, not `PermissionKind`, because only this
  optional engine needs it. Without it the engine reports
  `permissionUnavailable`; the session keeps the recording until the user
  chooses Allow/Retry or discards it (E2-S5). It is never requested during
  onboarding. `NSSpeechRecognitionUsageDescription` is set in
  `Config/LemmeType.xcconfig`.
- **Empty and silent audio** (shorter than 0.2 s, or no 50 ms window above
  −50 dBFS) fail with `noSpeechDetected` before the framework is called.
- **Errors** are mapped from `(domain, code)` only; framework messages are
  never kept or logged.
- **Languages**: English locales only for the MVP (`AppleSpeechEngine.languages`),
  default `en-US` (`AppPreferences.dictationLanguage`).
- **Module**: engines live in the new `Recognition` module (Domain + Support),
  constructed only in `AppComposition`.

## Consequences

- Real recognition, authorization prompts, and network silence are verified on
  a Mac (manual checks MA-19 to MA-21); CI runs the engine against a fake
  Speech backend plus the shared contract.
