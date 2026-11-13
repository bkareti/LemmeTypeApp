# E13-S8 — Do the policy, the app, the store text, and the code say the same thing?

Date: 2026-11-13. First pass by the author (Claude); **an independent reviewer still has to confirm it**
(the story asks for a reviewer). Each row is a claim about data, where it is made, and what proves it.
"Gateway" means the separate `speech-gateway` repository.

Result of the author's pass: **claims agree with the code, except the rows marked Open**, which wait on
the maintainer (Sarvam's answer, the production gateway). No sentence says nothing leaves the phone without
saying "Local".

| # | Claim | Said in | Proof | Result |
|---|---|---|---|---|
| 1 | Local mode sends nothing; it works in Airplane Mode | Policy (table), listing text, review notes, in-app Privacy | `NetworkSilenceTests`, `make network-check`, MA-54, MA-70 | Agrees |
| 2 | Cloud speech is off until the person turns it on and agrees | Policy, listing text, review notes, Settings footer | `CloudSpeechSettingsModelTests`, `CloudSpeechEngineTests`, `IOSCompositionTests.aDebugBuildOffersCloudSpeechButItStartsOff` | Agrees |
| 3 | A Cloud dictation sends the recording only: not vocabulary, other modes, or history | Policy, consent screen | `CloudSpeechEngineTests`, `GatewaySpeechProviderTests` (the request is audio plus language and task) | Agrees |
| 4 | The recording goes to LemmeType's server on Google Cloud in Mumbai, then to Sarvam AI in India | Policy, consent screen, review notes | Gateway `apps.yaml` and `docs/deploy-setup.md` (region `asia-south1`); `SarvamProvider`; ADR 0031, 0033 | Agrees; **Sarvam's retention is Open** (launch gate 1) |
| 5 | The server stores no audio or text and logs none | Policy, consent screen, listing text | Gateway `tests/privacy.test.ts` (canary and read-only directory tests), gateway `docs/privacy.md` | Agrees (tests live in the gateway repository) |
| 6 | The server keeps a one-way subscription code with plan, status, end date, and seconds used for 35 days after the period ends | Policy, consent screen, App Privacy rows | Gateway `docs/privacy.md`, Firestore TTL policy (set in `deploy-setup.md` step 10); `GatewayServiceTests` (token holds no identifier) | Agrees; the TTL policy on **production** is Open with gate 5 |
| 7 | The access token lasts 15 minutes, holds only the code, plan, and period, and is kept in memory | Policy | `GatewayServiceTests`, gateway token tests | Agrees |
| 8 | No key or token is written to disk; an old pasted key is erased | Threat model T-26 | `IOSCompositionTests.anOldApiKeyInTheKeychainIsRemoved`, `GatewayServiceTests` | Agrees |
| 9 | Apple takes the payment; LemmeType never sees card or Apple Account details | Policy, listing text | `StoreKitSubscriptionService` is the only StoreKit user and reads only verified transactions; ADR 0034 | Agrees |
| 10 | The subscription check works offline from records on the device; the keyboard gets only a kind and end date | Policy | `EntitlementPolicyTests`, `EntitlementSummaryTests` (no identifiers), MA-75 | Agrees; real-device offline behaviour is MA-75 step 4 (not yet run) |
| 11 | The keyboard has no Full Access, no network, no microphone, and inserts text from a dictation the person started | Policy, review notes, review-risk row 4.4.1 | `make security-check` (`RequestsOpenAccess` false), ADR 0032, MA-68 | Agrees |
| 12 | Delete All Local Data turns Cloud speech off and removes the agreement | Policy | `CloudSpeechSettingsModelTests` (`eraseAll`), `PrivacyOverviewModelTests` | Agrees |
| 13 | Copied text stays on the device and expires | Policy, in-app Privacy | `CopiedTextTests`, `HandheldEndToEndTests`, MA-67 | Agrees (unchanged) |
| 14 | The only network hosts are: the gateway (Cloud and session), Apple (StoreKit), huggingface.co (model, after confirmation), github.com (Mac updates, links) | Policy table | `docs/security/network-allowlist.txt`, `make network-check`, `URLSessionCloudSpeechTransportTests` | Agrees |
| 15 | App Privacy: Audio Data (not linked), Purchases and Other Usage Data (linked); tracking No | App Store Connect answers, manifest | `App/LemmeTypeiOS/PrivacyInfo.xcprivacy`, `make security-check`, `scripts/verify-ios-appstore.sh` | Agrees; entering the answers in App Store Connect is the maintainer's |
| 16 | The microphone text is true for Local and Cloud | Info.plist, review notes | `Config/LemmeTypeiOS.xcconfig`, `verify-ios-appstore.sh` ("names Cloud speech") | Agrees |
| 17 | The price and trial shown are StoreKit's | Listing text, screenshots | `Config/LemmeType.storekit`, `FakeSubscriptionService.sampleProduct` now uses the same values, `AppStoreScreenshotsUITests.testCaptureThePaywall` | Agrees (screenshot test not run in this pass) |
| 18 | Telugu is available through Cloud only; no Hindi, no Automatic, no translation | Listing text | `LanguageScopeTests`, `DictationSettingsLanguageTests` | Agrees |

## Still Open (maintainer)

Gates 1, 2, 4, and 5 in `docs/release/app-store.md` section 9; entering the App Privacy answers in App Store
Connect and attaching a screenshot of the final answers; the clean-install pass on a physical iPhone (MA-76); and
a reviewer's confirmation of this table.
