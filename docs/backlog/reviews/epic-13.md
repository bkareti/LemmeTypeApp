# Readiness review — Epic 13 paid public launch

Verdict: **Ready with notes** for E13-S1 to E13-S6 and E13-S8. **E13-S7 starts only after E13-S6 is
approved**, because the keyboard design is not yet proven on a device. E13-S8 closes with outside input
(Sarvam's written answer, App Store Connect setup).

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | Maps to the four requests of 2026-11-12: a gateway that can serve MeetQyl, a keyboard mic key, one $1.99 subscription with a 7-day trial for Local and Cloud, and StoreKit with updated privacy text and App Store information. |
| 2 | Size | Pass | 8, 8, 5, 8, 5, 5, 8, 5 points. Backend work is split into foundation and access control so each fits one PR. |
| 3 | Dependencies | Concern | S2's real-purchase check needs S4. S7 needs S6 (approved) and S5. S8 needs everything. External: Apple Developer Program and Paid Applications Agreement, Sarvam production key and written terms answer, hosting account and domain. |
| 4 | Acceptance criteria | Pass | Each criterion names a test, a fake, or a numbered manual check. Thresholds in S6 are proposals. |
| 5 | Testability on CI | Concern | StoreKit renewal, refunds, and expiry run in `StoreKitTest`. Apple notification payloads run from fixtures. Real purchases, Sandbox accounts, background microphone behaviour, and the keyboard on devices are manual (`MA-` numbers). |
| 6 | Privacy | Concern | Audio now passes through our server. Mitigations are in the stories: no audio or text stored (canary tests), a pseudonymous subscription code, consent per `consentVersion`, and S8's text and label changes. The App Store label moves from "Data Not Collected". |
| 7 | Permissions | Concern | Microphone as before. The keyboard may need Full Access (S6 decides). Notifications are not used. |
| 8 | iOS feasibility | Concern | A keyboard cannot open its app (rule 4.4.1) or use the microphone, so the mic key needs a session armed elsewhere. This is the largest unknown and the reason S6 comes first. |
| 9 | Out of scope | Pass | Mac subscription, accounts, MeetQyl changes, App Attest, other languages, and streaming are listed. |
| 10 | Open decisions | Concern | Listed below with defaults. |

## What the code and docs review found

| Finding | Where | Handled in |
|---|---|---|
| ADR 0031 says each user pastes a key, and a relay is "proposed for a public release" | ADR 0031 § Keys | S3 addendum |
| `KeychainCloudCredentialStore`, `ConsentedCloudCredentials`, and the key field exist for the own-key flow | `Support`, `CloudSpeechSettingsModel` | S3 removes the reachable key path |
| Consent is keyed to the provider id, so a vendor swap asks again; the gateway needs a way to swap without an app update | ADR 0031 | S3: `consentVersion` from the gateway |
| `scripts/check-security-config.py` fails if the keyboard requests Full Access | line 205 | S7 changes the rule and keeps a stronger one (no network, speech, or audio code in the keyboard) |
| App Store text and privacy answers say "no cloud", "no account", "Data Not Collected", and "no in-app purchases" | `docs/release/app-store.md` §3–4 | S8 |
| `NSMicrophoneUsageDescription` (Release) says speech is turned into text on the device | `Config/LemmeTypeiOS.xcconfig` | S8 |
| No StoreKit code, `.storekit` file, or terms of use exists | whole repo | S4 |
| The Mac app is Developer ID, so StoreKit cannot sell it | ADR 0026 | Out of scope; stated in the epic |
| Issue #142 (Firebase accounts) was closed as not planned on 2026-11-12 | GitHub | The epic uses StoreKit with the Apple ID and a pseudonymous code |
| Sarvam allows 60 requests a minute per account | ADR 0031 | S2 global limiter |
| Sarvam costs ~₹29 an hour; the subscription nets roughly 5 hours of cloud audio | ADR 0031, arithmetic in the epic | S2 caps |

## Decisions to record (proposed defaults)

| Decision | Proposed default | Where it is confirmed |
|---|---|---|
| Where the server code lives | New private repository, so MeetQyl does not depend on this one | New ADR in S1, before code |
| Language and hosting | TypeScript on Node 22, Google Cloud Run in `asia-south1`, Secret Manager | New ADR in S1 |
| Who is identified | The Apple subscription only; `sub` is an HMAC of the original transaction id | S2 |
| Cloud allowance | 120 minutes per billing period for the $1.99 plan (maintainer, 2026-11-12), 30 minutes during the trial, 15 minutes for Sandbox; set per product in `apps.yaml` so other plans can be added | S2 |
| Free trial | Apple's introductory offer (the user confirms in Apple's sheet; not charged for 7 days) | S4 |
| Product id | `com.lemmetype.LemmeType.iOS.pro.monthly`; cannot be reused once saved | S4, before the first App Store Connect save |
| What an expired user keeps | Settings, export, delete, privacy, subscription screens, typing keys, saved data | S5 |
| Offline rule | Trust a verified subscription to its expiry plus 3 days; clock-rollback guard | S5 |
| Keyboard design | Time-limited dictation session armed outside the keyboard, with Full Access only for the mic key | S6 decides, S7 builds |
| Session length | 15 minutes by default, user chooses 5, 15, or 30 | S7 |
| Vendor swap without an app update | Allowed inside an approved list with the same country and terms; otherwise raise `consentVersion` | S3 |
| App Attest | Deferred. Revisit if one subscription's usage shows sharing | Epic out of scope |

## Suggested story edits

None outstanding. The maintainer should confirm the hosting default and the cloud allowance before S1 and S2 start.

## Not in the stories (for the maintainer)

- Whether the public price is $1.99 in every country or Apple's equivalent prices. The stories assume Apple's equivalents.
- Whether Cloud-only languages beyond Telugu are wanted at launch. The stories assume Telugu and English only.
- Refunds and customer support for subscriptions (a support email or form beyond the GitHub page).

## AC → verification map

| Story | Acceptance criterion | Verification |
|---|---|---|
| S1 | API contract and every error code | `openapi.yaml` validation; example replay tests |
| S1 | No audio or text stored or logged | Canary test; read-only working directory test |
| S1 | Provider swap by configuration; second app isolated | Fake providers; `testapp` isolation test |
| S1 | Staging deployed, runbook followed | CI deploy log; recorded runbook run |
| S2 | Apple signed-transaction checks | Test certificate chain tests, one per failure |
| S2 | Renewal, refund, and expiry notifications | Replayed Apple fixtures |
| S2 | Quotas, global limit, budget switch | Injected-clock and fake-provider tests |
| S2 | Token holds no identifier | Decode test |
| S2 | Real sandbox purchase accepted | Manual with S4 build |
| S3 | No request without consent or when Cloud is off | `FakeCloudSpeechTransport`; `NetworkSilenceTests` |
| S3 | New `consentVersion` asks again | Unit test |
| S3 | Error mapping, no silent engine switch | Unit tests |
| S3 | No key or token on disk | Canary tests |
| S3 | Real Telugu dictation against staging | Manual (`MA-`) |
| S4 | Trial, renewal, cancel, expiry, refund, billing retry | `SKTestSession` time travel |
| S4 | Prices from StoreKit only | Test that changes the `.storekit` price |
| S4 | Paywall meets 3.1.2 on small screens, Dynamic Type, VoiceOver | UI tests with fakes |
| S4 | Sandbox purchase, restore, cancel, expiry | Manual on a device (`MA-`) |
| S5 | Policy table, offline grace, clock guard | `EntitlementPolicy` table test with `ManualClock` |
| S5 | Every entry point blocked when expired | Fake-based tests per entry point |
| S5 | Expired user keeps data tools | UI test |
| S6 | Eight questions answered with numbers | `docs/testing/ios-feasibility.md`; new ADR |
| S6 | Thresholds | Manual on devices |
| S7 | Key state machine | Unit tests with fakes |
| S7 | No network, speech, or audio code in the keyboard | `check-security-config.py` build check |
| S7 | Mic never open without indicator | `FakeAudioSource` open/close test |
| S7 | Real-device behaviour | Manual (`MA-`) |
| S8 | Policy, app, and store text agree | Reviewer record; `make privacy-docs-check`, `make docs-check` |
| S8 | Launch gates | ADR 0031 table with evidence links |
| S8 | Release archive | `make ios-appstore-check` |
| S8 | Clean-install pass | Manual (`MA-`) |
