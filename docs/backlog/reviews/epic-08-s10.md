# Readiness review — E8-S10 Guide first-run setup with animated steps

Verdict: Ready with notes

| # | Check | Result | Notes |
|---|---|---|---|
| 1 | Value | Pass | Today setup is spread over an alert, Settings › Models, the Cloud section, and a text guide. New users have to find each one. |
| 2 | Size | Pass | 5 points. One PR: a model, a flow view, a reusable card view, Settings reuse, composition wiring, tests. |
| 3 | Dependencies | Pass | E8-S5 (models), E8-S7 (shortcut guide), E13-S4 (paywall) are on `main`. Every action reuses an existing model: `PermissionsModel`-style microphone closures from `QuickDictationModel`, `ModelsSettingsModel.offerDownload/confirmDownload`, `CloudSpeechSettingsModel.requestTurnOn/acceptConsent`, `SubscriptionModel.showPaywall`. |
| 4 | Acceptance criteria | Pass | Each criterion names a model test, a UI test, or a manual step. "Animated" has no threshold, so motion is checked by the Reduce Motion rule and a manual look, not a metric. |
| 5 | Testability on CI | Concern | The system microphone and Speech Recognition prompts, VoiceOver, and the look of the animations need a device or Simulator session: covered by fakes (`FakePermissionRequester`, fake speech authorizer) plus a manual `MA-` step. |
| 6 | Privacy | Pass | No new data. The flow stores one flag (`hasCompletedOnboarding`, already in `AppPreferences`). Cloud speech still needs the existing consent and subscription; nothing is sent from the flow. |
| 7 | Permissions | Pass | Microphone and Speech Recognition only, each behind an explanation whose only button is Continue (Guideline 5.1.1). |
| 8 | Feasibility | Pass | iOS 26: `symbolEffect`, `phaseAnimator`, `keyframeAnimator`, `accessibilityReduceMotion` all exist. There is no supported URL to the Action Button, Back Tap, or Keyboards screens, so the cards show the path; `PublicLinks.newShortcut` already opens Shortcuts. |
| 9 | Out of scope | Pass | Mac onboarding, Action Button detection, deep links into system Settings, designer assets. |
| 10 | Open decisions | Concern | See below. |

## Decisions to record (proposed defaults)

- **Recommended model:** `ModelsSettingsModel.suggestedModel` = first id in `plan.whisperModelOrder` whose row fits as `.recommended`, else the first that can run, else none (the option is then hidden). Same catalog filter as Settings (`LanguageScope.lists`).
- **Who sees the flow:** shown when `hasCompletedOnboarding` is false **and** the microphone was never requested. Otherwise the flag is set silently at launch, so people upgrading from 1.0 do not see it.
- **Close (×) and Back:** available on every step and mark the flow done (×), except on the microphone step before iOS has asked: there the only control is Continue, as with today's "Before You Dictate" alert (Guideline 5.1.1). Once iOS has asked, × and Back come back.
- **Paywall:** `SubscriptionModel` gets `holdOneTimeOffer()` / `releaseOneTimeOffer()`: while the flow is up the one-time offer waits; when the flow ends it shows if it would have.
- **Cloud without a subscription:** the Cloud choice shows the paywall; after a purchase, the user taps Cloud again to see the consent sheet. Cloud never turns on from the flow without Agree.
- **iPad:** skips "Dictate in any app" (`DeviceClass.iPad`).
- **UI tests:** `-LemmeTypeUITesting` marks the flow done unless the scenario argument `-LemmeTypeSetupGuide` is passed.
- **No ADR:** the flow is UI over existing decisions (ADR 0027, 0031, 0032, 0034); record it in `CLAUDE.md`.

## Suggested story edits

None.

## AC → verification map

| Acceptance criterion | Verification |
|---|---|
| Fresh install shows the flow; upgrade is marked done | `SetupGuideModelTests.aFreshInstallShowsTheGuideFromWelcome`, `.someoneWhoAlreadyUsedTheMicrophoneSkipsIt` |
| Microphone: Continue only before the prompt, then allowed/denied | `SetupGuideModelTests.theMicrophoneStepAsksOnlyAfterContinue`, `.aDeniedMicrophoneOffersSettings`; UI tests `SetupGuideUITests.testAFreshInstallWalksTheGuideToDictate`, `.testADeniedMicrophoneStillLetsTheGuideGoOn` |
| "On this device" offers the recommended model, downloads after confirmation | `SetupGuideModelTests.onThisDeviceOffersTheSuggestedModelAndWaitsForConfirmation`, `ModelsSettingsModelTests.theSuggestedModelIsTheFirstInThePlanThatFitsWell`; UI test `SetupGuideUITests.testChoosingTheModelShowsTheDownloadConfirmation` |
| Cloud only when offered; paywall without subscription; Agree needed | `SetupGuideModelTests.cloudIsOfferedOnlyWhenTheBuildHasIt`, `.cloudWithoutASubscriptionShowsThePaywallAndStaysOff`, `.cloudWithASubscriptionTurnsOnOnlyAfterAgree` |
| iPad skips Dictate in any app | `SetupGuideModelTests.anIPadSkipsTheAnyAppStep` |
| Paywall waits for the flow | `SetupGuideModelTests.theOneTimePaywallWaitsForTheGuideAndThenAppearsOnce`, `SubscriptionModelTests.theOneTimeOfferWaitsWhileHeld`, `.openingThePaywallWhileHeldCountsAsTheOneTime` |
| Show Setup Guide reopens from Welcome, changes nothing | `SetupGuideModelTests.replayStartsAtWelcomeAndChangesNothing`, UI test `SetupGuideUITests.testSettingsCanShowTheGuideAgain` |
| Reduce Motion / VoiceOver | Manual MA-80 |
| Existing UI tests start past the flow; one UI test walks it | `make test-ui-ios` |
| l10n, lint, unit, iOS tests | `make l10n-check`, `make lint`, `make test-unit`, `make test-ios` |
