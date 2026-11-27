# Readiness review — E12-S7 Offer more Indian languages through Cloud speech

Verdict: Ready with notes

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | Hindi, Tamil, Kannada, and Malayalam speakers get the same Cloud path Telugu speakers have; it is the product's main selling point in India. |
| 2 | Size | Pass | 5 points. Two PRs because the gateway is a separate repository: the app change here, and a small gateway change (language codes, tests, runbook). |
| 3 | Dependencies | Pass | E12-S1, E12-S6, E13-S1, E13-S3 are merged on `main`. `/v1/capabilities` already returns `languages`; the app ignores it today (`GatewayService.capabilities()`). |
| 4 | Acceptance criteria | Pass | Each criterion names a unit test, a gateway test, or a make target. Real-speech quality is out of scope and gated per language. |
| 5 | Testability on CI | Pass | Fakes cover capabilities (`FakeGatewayAccess`), preferences, and the transport. Real dictation per language is manual and happens before a route is added in production. |
| 6 | Privacy | Concern | No new data leaves the device; the capabilities call already exists and carries no user data. The stored list is language codes only. The privacy policy and App Store text name Telugu and must be updated in the release that turns on another language, not before. The consent version does not change: same provider, same country, same terms (ADR 0031, `apps.yaml` `consentVersion`). |
| 7 | Permissions | Pass | None new. |
| 8 | Feasibility | Pass | Sarvam `saaras:v4` serves `hi-IN`, `ta-IN`, `kn-IN`, `ml-IN` with `codemix` and `translate` (to be confirmed by the gateway's real-provider test). |
| 9 | Out of scope | Pass | Production switch-on, other languages, detection, local Whisper, and the Mac app are listed as out. |
| 10 | Open decisions | Concern | See below. A parallel session (`check-any-language-to-en`) may change `GatewaySpeechProvider` for automatic language; merge order matters. |

## Decisions to record (proposed defaults)

- **Source of truth for live languages:** the gateway's `apps.yaml` routes, read through `/v1/capabilities`. Recorded as an ADR 0031 addendum.
- **Before the first answer:** Telugu only (what 1.0 ships), so a fresh install never offers a language the gateway might refuse.
- **Where the list is kept:** `UserDefaults` key `cloudSpeechLanguages` (codes only), written whenever capabilities are fetched. Delete All Local Data leaves it: it is the gateway's configuration, not the user's data.
- **A language that disappears:** stays visible where it is already chosen and reports "not available" through the existing readiness text; no automatic switch to another engine (ADR 0016).
- **Task per language:** a language is offered when the gateway lists `transcribe`; translation is offered when it also lists `translate`. Today every route has both.
- **Names:** English name plus own-script name, as for Telugu (हिन्दी, தமிழ், ಕನ್ನಡ, മലയാളം).

## Suggested story edits

None beyond what is written. Epic 12's "Languages other than Telugu and English" out-of-scope line now points to this story.

## AC → verification map

| Acceptance criterion | Verification |
|---|---|
| Capabilities with `te`, `hi` → menu offers English, Telugu, Hindi only | `DictationSettingsLanguageTests.theCloudScopeOffersWhatTheGatewayListsAndNothingElse`, `GatewayLanguagesTests.theEngineOffersWhatTheGatewayLastListed` |
| A dropped language stays visible, reports not available, never switches engine | `DictationSettingsLanguageTests.aLanguageTheGatewayDroppedStaysVisibleAndIsNotReady`, MA-79 step 5 |
| List survives relaunch; Telugu only before any answer | `GatewayLanguagesTests` (`beforeTheGatewayHasAnsweredOnlyTeluguIsOffered`, `theLastAnswerSurvivesARelaunch`) |
| Hindi Cloud dictation sends `language=hi` and the task | `GatewayLanguagesTests.aListedLanguageIsSentWithItsTask` |
| Unlisted language refused before sending | `GatewayLanguagesTests.aLanguageTheGatewayDidNotListIsRefusedBeforeAnythingIsSent` |
| Whisper candidates and model languages unchanged | `GatewayLanguagesTests.onDeviceDetectionAndModelLanguagesAreUnchanged`, `LanguageSupportMatrixTests` |
| Cloud section names the live languages; l10n | `CloudSpeechLanguageTests`, `make l10n-check` (paywall keeps "Telugu and more") |
| Gateway maps the four codes; capabilities list only routed languages | `speech-gateway/tests/providers.test.ts`, `tests/api.test.ts` |
| Tests and lint pass | `make test-unit`, `make lint`, `npm test` in `speech-gateway` |
