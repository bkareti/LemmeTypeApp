# Readiness review — Epic 11 opt-in cloud speech

Verdict: **Ready with notes** for E11-S1, E11-S2, and E11-S3. **E11-S4 is blocked by outside
input** (Sarvam's written answer and the maintainer's recordings), not by code.

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | Telugu speakers go from 93 % to about 5 % character errors on the measured clips; S1 also delivers replaceability. |
| 2 | Size | Pass | 8, 3, 8, and 5 points; each fits one PR. S1 and S3 are at the limit. |
| 3 | Dependencies | Pass | The engine contract, modes, and context policy are merged. S4 depends on two things outside the repository. |
| 4 | Acceptance criteria | Pass | Each is observable; timings and retries have numbers. |
| 5 | Testability on CI | Pass | The network sits behind `CloudSpeechTransport`. The real API is opt-in. Real speech and a signed build are manual. |
| 6 | Privacy | Concern | Audio leaves the Mac for the first time. Consent, indicator, refusal, and deletion are specified, but Sarvam's training and retention terms conflict. The Release off-switch contains this until S4. |
| 7 | Permissions | Pass | Microphone only. No new TCC permission. |
| 8 | macOS feasibility | Concern | The app has no App Sandbox (ADR 0001), so no network entitlement is needed. Keychain use is new to this codebase: confirm login-Keychain access is stable across ad hoc and Developer ID builds. |
| 9 | Out of scope | Pass | Other languages, relay, streaming, iOS, and a provider picker are excluded. |
| 10 | Open decisions | Concern | Listed below with defaults. |

## What the code review found

| Finding | Where | Handled in |
|---|---|---|
| `ProcessingLocation` has only `.onDevice` | `RecognitionEngine.swift` | S1 |
| Automatic and fallback take the first ready engine, so a cloud engine could be picked silently | `EngineSelector.swift` | S1, with tests |
| No error type for offline, bad key, or used-up credits | `RecognitionError.swift` | S1 |
| Hints are documented as never leaving the Mac, though Sarvam offers `keyterms` | `RecognitionRequest` | S1: not sent |
| Settings says every engine runs on this Mac | `DictationSettingsView.swift` | S3 |
| No Keychain code exists yet | Support | S3 |

## Decisions to record (proposed defaults)

| Decision | Proposed default |
|---|---|
| Where the code lives | In `Recognition/Cloud/`: no new module and no new dependency edges |
| How the user selects it | Offer a custom **Telugu (Cloud)** mode, so English modes stay local |
| API keys | The user's own key, for the friends beta only (ADR 0031) |
| Release control | One compile-time off-switch, turned on only in S4 |
| Time limit per attempt | 20 seconds; measured p95 was 0.91 s |
| Support status | Telugu on Cloud stays `evaluation` until a product owner approves a measurement |

## Suggested story edits

None outstanding. These were folded in while writing the stories.

## AC → verification map

| Story | Acceptance criterion | Verification |
|---|---|---|
| S1 | Contracts, second provider | `RecognitionEngineContract`, `CloudSpeechProviderContract` |
| S1 | Sarvam request shape, error mapping, retries | `SarvamProviderTests`, `CloudSpeechEngineTests` with `ManualClock` |
| S1 | Cloud chosen only when preferred | `EngineSelectorTests` |
| S1 | Host and redirect refusal | `URLSessionCloudSpeechTransportTests` |
| S1 | Canary | Diagnostics canary test |
| S2 | Splitting, no lost audio, failure, cancel | `CloudSpeechEngineTests` with generated audio |
| S3 | No request without consent, key, and mode | Unit tests with `FakeCloudSpeechTransport` |
| S3 | Key only in the Keychain; removal | Canary and store tests |
| S3 | Indicator, refusals, consent flow | Unit tests; UI tests with fakes |
| S3 | Release has no cloud path | Release build check |
| S4 | Gates, real speech, signed build | ADR 0031 evidence; `scripts/cloud-speech-eval.py`; manual checklist |
| S4 | Local mode stays silent | `NetworkSilenceTests` |
