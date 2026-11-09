# Readiness review — Epic 12 English writing on iPhone

Verdict: **Ready with notes** for E12-S1, E12-S2, and E12-S3. **E12-S4 is blocked by outside
input** (Sarvam's written answer, recordings, and a physical iPhone).

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | Covers the three things the maintainer asked for on iPhone. |
| 2 | Size | Pass | 8, 5, 5, and 3 points; each fits one PR. |
| 3 | Dependencies | Concern | E12-S1 needs E11-S1 merged, and E12-S2 needs E11-S2. E12-S3 can start at any time. |
| 4 | Acceptance criteria | Pass | Each is observable. |
| 5 | Testability on CI | Pass | Fakes cover the network and the model. Real speech and leaving the app mid-upload on hardware are manual. |
| 6 | Privacy | Concern | Audio leaves the phone for the first time. Sarvam's terms conflict (ADR 0031), so Release stays off. |
| 7 | Permissions | Pass | Microphone only. The usage text must change. |
| 8 | iOS feasibility | Concern | The Keychain needs no entitlement. A foreground upload can be interrupted when the app leaves the screen, and that behaviour needs a real-device check. |
| 9 | Out of scope | Pass | Explicit. |
| 10 | Open decisions | Concern | Listed below with defaults. |

## What the code review found

| Finding | Where | Handled in |
|---|---|---|
| Release builds are English only | `IOSComposition.languageScope` | S1 and S4 |
| A Neutral + Plain text + Original style means no rewrite, so grammar needs its own option | `StyleOptions` | S3 |
| Readiness is judged per engine, and the matrix defaults to Whisper | `LanguageSupportMatrix.row` | S1 |
| Several iPhone strings promise the device only | `MobileSettingsView`, `QuickDictationView`, `LemmeTypeiOS.xcconfig` | S1 |
| iPhone recordings can reach five minutes, past one 30-second request | `RecordingLimits.handheld` | S2, through E11-S2 |
| Translate Again uploads and bills again | The existing retry path | S2 warns first |

## Decisions to record (proposed defaults)

| Decision | Proposed default |
|---|---|
| Where the stories live | A new epic, so the `platform:iOS` label applies and Epic 8 is left alone |
| How language is chosen | Two modes: Telugu to English (Cloud) for Telugu and mixed speech, and Proper English for English |
| One mode for everything | Not now. Sarvam documents `translate` for Indic languages; how it treats pure English is unmeasured |
| Grammar after a translation | None: a second model pass risks changing the meaning |
| Grammar provider | Apple's on-device model: no cost, nothing leaves the phone, but it needs Apple Intelligence |
| API keys | The user's own key (ADR 0031) |

## Suggested story edits

None outstanding.

## AC → verification map

| Story | Acceptance criterion | Verification |
|---|---|---|
| S1 | No request without consent and key; provider id | Unit tests with `FakeCloudSpeechTransport` |
| S1 | Key only in the Keychain; removal | Canary and store tests |
| S1 | Indicator, consent flow | UI tests with fakes |
| S1 | Leaving the app mid-upload | Unit test for the outcome; manual on hardware |
| S1 | Release has no cloud path | Release build check |
| S2 | Translate, review, Copy, parts | `HandheldEndToEndTests` additions |
| S2 | Failures and not-ready mode | Unit tests |
| S3 | Off means no call; old modes load | Existing tests; decoding test |
| S3 | Rejected rewrites, no Apple Intelligence | Tests with `FakeTextRewriter` |
| S3 | Real grammar samples | Opt-in real-model test |
| S4 | Real device, human review, gates | Manual checklist; ADR 0031 evidence |
