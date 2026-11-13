# App Store submission — LemmeType 1.0.0 for iPhone and iPad

Everything needed to put the iPhone and iPad app on the App Store, written so App
Review has no reason to come back with questions. The Mac app is released by
Developer ID download instead; see [Mac](#mac-why-not-the-mac-app-store-for-100).

## 1. One-time setup (needs you)

1. Join the **Apple Developer Program** (paid) with the account that will own the app.
2. In **Certificates, Identifiers & Profiles**, register the App ID
   `com.lemmetype.LemmeType.iOS` with the **App Groups** capability (`group.com.lemmetype.LemmeType`,
   shared with the keyboard) and **In-App Purchase**. The keyboard's App ID
   (`com.lemmetype.LemmeType.iOS.Keyboard`) needs the same App Group. There is no push; the only background
   mode is audio, for Action Button dictation (ADR 0032).
3. In **App Store Connect › Apps › +**, create the app: platform iOS, name **LemmeType**
   (if taken, use **LemmeType: Voice to Text**), primary language English (U.S.), bundle
   ID above, SKU `lemmetype-ios`.
4. On this Mac: sign in to Xcode (Settings › Accounts) and put your team id in
   `Config/Signing.local.xcconfig` (`DEVELOPMENT_TEAM = <team id>`; gitignored).

## 2. Build, check, upload

```bash
make ios-appstore-check            # unsigned Release archive + App Store checks (no account needed)
make ios-appstore UPLOAD=1         # signed archive, checks, upload to App Store Connect
scripts/make-app-store-screenshots.sh   # 6.9-inch iPhone and 13-inch iPad screenshots
```

`scripts/verify-ios-appstore.sh` checks what App Store processing rejects: bundle id,
version and build, usage strings, the encryption answer, no background modes, launch
screen, iPhone + iPad, icon, privacy manifest (no tracking; only audio, purchase, and usage data,
matching section 4), arm64, no XCTest or Swift Testing linked, embedded framework metadata
and minimum iOS, no recordings inside, the English-only build flag, and **the paid launch**: a
production gateway host (`LEMMETYPE_GATEWAY_HOST` in `Config/LemmeTypeiOS.xcconfig`, no staging
or placeholder host), a microphone text that names Cloud speech, and every launch gate in
section 9 Closed. A build made while a gate is Open fails the check on purpose.

Then, in App Store Connect: install the build from **TestFlight** on a real iPhone and
iPad first (section 7), then submit it for review.

## 3. App information (copy into App Store Connect)

| Field | Value |
|---|---|
| Name | LemmeType |
| Subtitle (≤ 30) | Private voice to text |
| Category | Productivity (secondary: Utilities) |
| Content rights | Contains third-party content: yes — open-source Whisper speech models (MIT licence), downloaded only when the user chooses; the licence permits it (Settings › About › Acknowledgements) |
| Age rating | Answer **None / No** to every question → **4+** |
| Price | Free to download. In-app purchase: LemmeType Pro, auto-renewing monthly subscription, US$1.99 with a 7-day free trial (section 3a). Apple sets the other countries' prices |
| In-App Purchases | Yes (the subscription) |
| Terms of Use URL (EULA) | https://github.com/bkareti/LemmeTypeApp/blob/main/docs/terms-of-use.md |
| Privacy Policy URL | https://github.com/bkareti/LemmeTypeApp/blob/main/docs/privacy-policy.md |
| Support URL | https://github.com/bkareti/LemmeTypeApp/blob/main/docs/support.md |
| Marketing URL | leave empty |
| Copyright | 2026 <your legal name or company> |
| Version | 1.0.0 (build from `Config/Version.xcconfig`) |

**Promotional text (≤ 170):**

> Speak, check, copy. In Local mode your voice becomes text on your iPhone or iPad and never leaves it. Try free for 7 days.

**Keywords (≤ 100, comma-separated, no spaces):**

> dictation,speech to text,voice typing,transcribe,dictate,offline,private,voice notes,talk to text

Do not add other apps' or companies' names (Guideline 2.3.7): no "Siri", "Whisper",
"ChatGPT", "Apple".

**Description:**

> LemmeType turns your voice into text, privately, on your iPhone or iPad.
>
> Tap Start Dictating, speak, and tap Stop. LemmeType writes what you said and lets you read it before you copy it into any app: Messages, Mail, Notes, or anything else.
>
> PRIVATE BY DESIGN
> • Local mode turns your voice into text on your device. It never leaves it, and it works in Airplane Mode.
> • Cloud speech is optional and off until you turn it on. It sends only the recording of that dictation to LemmeType's server and a speech service in India, and nothing is stored.
> • No LemmeType account, no ads, no analytics, no tracking.
> • The recording is deleted as soon as the text is ready.
> • Copied text stays on this device and is removed after the time you choose.
>
> WRITE THE WAY YOU WANT
> • Exact: your words as you said them.
> • Clean: removes filler words and tidies punctuation.
> • Message mode, your own modes, and vocabulary for the names and terms you use.
> • On supported devices, an on-device model can adjust the tone. You always see the original too.
>
> START FASTER
> • Start dictating from the Action Button, Back Tap, or the Shortcuts app.
>
> CHOOSE YOUR ENGINE
> • Apple's on-device speech recognition works right away.
> • Or download an open-source speech model (78 to 488 MB) that stays on your device.
> • Cloud speech (optional) adds Telugu.
>
> LemmeType understands English on your device, and Telugu through Cloud speech.
>
> SUBSCRIPTION
> • LemmeType Pro is US$1.99 a month after a 7-day free trial, in your App Store currency. It includes Local dictation and a monthly allowance of Cloud speech.
> • Payment is charged to your Apple Account at the end of the trial and renews monthly unless cancelled at least 24 hours before the end of the period. Manage or cancel it in your Apple Account settings.
> • Terms of Use: https://github.com/bkareti/LemmeTypeApp/blob/main/docs/terms-of-use.md
> • Privacy Policy: https://github.com/bkareti/LemmeTypeApp/blob/main/docs/privacy-policy.md
>
> So the microphone is never left on, a recording stops when you leave the app, when a call comes in, or after five minutes.

**What's New (1.0.0):**

> The first release of LemmeType for iPhone and iPad: private voice to text on your device, with optional Cloud speech for Telugu.

## 3a. Subscription (App Store Connect › Monetization › Subscriptions)

The product is built in the app (`StoreKitSubscriptionService`, ADR 0034) and mirrored in `Config/LemmeType.storekit`.
Everything below is the maintainer's to do in App Store Connect; nothing sells until it is done.

1. **Agreements, Tax, and Banking:** sign the **Paid Applications Agreement** and complete the tax and bank forms.
   Subscriptions cannot be created or tested end to end without it.
2. **Subscription group:** create *LemmeType Pro* (the group name is the reference name shown to people in
   Apple's manage-subscriptions screen).
3. **Product:** an auto-renewing subscription, product id `com.lemmetype.LemmeType.iOS.pro.monthly`, duration 1 month.
   **The id cannot be reused or renamed once saved**, so confirm it first (it is also `IOSComposition.subscriptionProductID`).
4. **Price:** US$1.99 as the base; let Apple fill the other countries with its equivalent prices (adjust any you want).
5. **Introductory offer:** free for 1 week, new subscribers only. Family Sharing off.
6. **Localization:** a display name and a description of the subscription for each language of the page.
7. **Review screenshot:** a screenshot of the paywall (Settings › Subscription › *Start 7-day Free Trial*), plus review
   notes saying how to reach it and that a Sandbox account is enough to test.
8. **Terms of Use and Privacy Policy links:** add the Terms of Use link (`docs/terms-of-use.md` on GitHub, or Apple's
   standard EULA) in App Information. The paywall already shows both links beside the price (Guideline 3.1.2).
9. **Notifications:** App Information › App Store Server Notifications: set the URL for **Production** and **Sandbox**
   to the gateway's `/v1/apple/notifications` (ADR 0033, E13-S2) and choose **Version 2**.
10. Add the app's numeric **Apple ID** to the gateway's `apps.yaml` (`appAppleId`) before the first real purchase.
11. **Sandbox testers:** create at least one Sandbox Apple Account for MA-74.

## 4. App Privacy (App Store Connect › App Privacy)

Cloud speech is part of this release, so the answers are **not** "Data Not Collected". They match
`App/LemmeTypeiOS/PrivacyInfo.xcprivacy` (checked by `make security-check` and `scripts/verify-ios-appstore.sh`),
`docs/privacy-policy.md`, and the gateway (the `speech-gateway` repository's privacy page).

- **Do you or your third-party partners collect data from this app?** Yes.
- **Tracking:** No. No IDFA, no tracking domains, no data shared with data brokers or used for advertising.

| Data type | Collected for | Linked to the person? | Used to track? | Where it goes and for how long |
|---|---|---|---|---|
| **Audio Data** | App Functionality | No | No | Only a Cloud dictation: the recording goes to LemmeType's server and a speech service, in memory. LemmeType keeps nothing. The speech service's retention is gate 1 in section 9 |
| **Purchases** | App Functionality | Yes | No | The subscription's product, status, and end date, under a one-way code, so the server can allow Cloud speech. Deleted 35 days after the billing period ends |
| **Other Usage Data** | App Functionality | Yes | No | Seconds of Cloud speech used in each billing period, under the same code. Deleted 35 days after the billing period ends |

Why "Linked: Yes" for the last two: the code is made from the person's Apple subscription and is used to
find their record, so Apple's definition of "linked to identity" is met even though it holds no name, email,
Apple Account, or device. "Linked: No" for audio holds only while LemmeType and its speech service do not keep it.

What is **not** collected: text (dictated or typed), the keyboard's contents, contacts, location, identifiers
(IDFA or device), diagnostics, or crash data. In **Local** mode nothing at all leaves the device.
If a launch gate shows the speech service keeps audio, change the Audio Data row to
*Linked: No, retained* and tell the privacy policy first.

Update this section and the privacy policy together in the same change (`docs/security/privacy-release-checklist.md`).

## 5. App Review information

- **Sign-in required:** No. (A Sandbox Apple Account is enough to try the subscription.)
- **Contact:** your name, phone, and email (App Review only).
- **Notes** (paste as is; fill the bracketed value):

> LemmeType is a voice-to-text app. It has no account or sign-in.
>
> To test dictation:
> 1. Tap "Start Dictating". A short explanation appears; tap Continue. iOS then asks for the microphone and for Speech Recognition — please allow both (Local mode uses Apple's on-device speech recognition).
> 2. Speak an English sentence and tap Stop.
> 3. Read the text and tap Copy, then paste it in Notes.
>
> Subscription: LemmeType Pro is an auto-renewing monthly subscription with a 7-day free trial. The first launch shows the offer once; it is also in Settings › Subscription. A Sandbox Apple Account can start the trial. Without a trial or subscription, recording is not available; Settings, Restore Purchases, Manage Subscription, Export and Delete All Local Data stay available. Terms of Use and Privacy Policy are linked on the offer and in Settings › About.
>
> Cloud speech (optional, off by default): Settings › Cloud speech › Turn On Cloud Speech…, then agree to the screen that explains it. Create or edit a mode, choose the Cloud engine and Telugu, and dictate. Only the recording of that dictation is sent, to LemmeType's server ([production host]) and from there to a speech service in India; LemmeType stores no audio or text. Local modes never use the network. Cloud speech is part of the subscription (a monthly allowance).
>
> Privacy: Local speech recognition runs on the device only (SFSpeechRecognizer with requiresOnDeviceRecognition, or an open-source model on the device). The app declares Audio Data, Purchases, and Other Usage Data (App Functionality) in its App Privacy answers for Cloud speech and the subscription.
>
> Keyboard: the LemmeType keyboard has typing keys. When you dictate with the Action Button, it shows a recording view and inserts the finished text into the field that was open when recording started. It does not request Full Access, has no network access, and cannot use the microphone.
>
> Optional: Settings › Models offers open-source Whisper speech models (MIT licence, from huggingface.co). They are model weights (data, not code), downloaded only after the user confirms the size, and verified by SHA-256.
>
> The only background mode is audio. It lets the Action Button start a recording from another app (press once to start, again to stop) while a Live Activity shows that the microphone is on; starting needs an unlocked iPhone. A recording also stops on an interruption such as a call, or after five minutes. In the app, a recording stops when the app leaves the foreground.
>
> Tone rewriting uses Apple's on-device Foundation Models framework and appears only on devices that support it.

- **Export compliance:** the build declares `ITSAppUsesNonExemptEncryption = NO` (only
  HTTPS, for the model download and the speech gateway), so App Store Connect does not ask.

## 6. Screenshots

`scripts/make-app-store-screenshots.sh` writes them to `build/app-store-screenshots/`:

| Set | Device | Size | Screens |
|---|---|---|---|
| iPhone 6.9" (required) | iPhone 18 Pro Max | 1320 × 2868 | ready, recording, review, copied, settings, privacy, Cloud speech switch, subscription offer |
| iPad 13" (required, the app runs on iPad) | iPad Pro 13-inch (M5) | 2064 × 2752 | same |

They are the real screens (the UI-test build, with a fixed sentence standing in for speech)
and the standard 9:41 status bar. Upload 3–6 per set, in order. The subscription offer shows the
price from the fake service, which uses the same name, price, and trial as `Config/LemmeType.storekit`
(and so as App Store Connect); `AppStoreScreenshotsUITests.testCaptureThePaywall` fails if the price differs.
The Cloud speech and offer screens belong in the set only for a build that offers Cloud speech (section 9).

## 7. Before submitting: checks a person must do

App Review installs the build on real devices. Do these on a real iPhone and iPad from
**TestFlight**, not the Simulator:

| # | Check | Why App Review cares |
|---|---|---|
| 1 | Fresh install → Start Dictating → Continue → allow both prompts → speak → Stop → text → Copy → paste in Notes | 2.1 completeness: the first try must work |
| 2 | Deny the microphone, then try again: the screen explains and offers Open Settings; nothing crashes | 5.1.1 respect for denial |
| 3 | Deny Speech Recognition: the screen says why and offers Allow Speech Recognition / another engine | 2.1 |
| 4 | Settings › Models › download Base: the size is shown first; it installs; dictate with it | 2.5.2 data download, 2.1 |
| 5 | Lock the screen, take a call, and switch apps while recording: it stops, keeps the text | 2.5.4 no background audio |
| 6 | iPad: portrait and landscape, Split View | 2.4.1 iPad support |
| 7 | Settings › About: Privacy Policy and Help open in Safari; Acknowledgements shows the licences | 5.1.1(i) in-app policy link |
| 8 | Airplane mode: dictation still works with Apple Speech | the privacy claim |
| 9 | VoiceOver: Start Dictating, Stop, Copy are read and work | Accessibility: every control has a label |
| 10 | Sandbox Apple Account: start the trial, restore on a second device, cancel, let it expire; the offer's price, trial length, and renewal wording match App Store Connect | 3.1.2 subscriptions, 3.1.1 |
| 11 | Turn Cloud speech on, agree, dictate Telugu; then Airplane Mode: Local still works, Cloud says it could not reach the service | 5.1.1 data use is as described; 2.1 |
| 12 | Delete All Local Data: Cloud speech is off, the agreement is gone, the app asks again | 5.1.1(v) deletion |

These are also MA-66…MA-76 in `docs/testing/manual-acceptance.md`.

## 8. Review-risk checklist

| Guideline | Risk | How 1.0.0 meets it | Evidence |
|---|---|---|---|
| 2.1 App completeness | Reviewer cannot dictate on first try | Speech Recognition is asked with the microphone on the first dictation when no engine is ready | `QuickDictationModelTests.theFirstStartAsksForSpeechRecognitionAfterTheExplanationWhenNeeded` |
| 2.2 Beta testing | "Beta", "evaluation", "not reliable" text | Release builds offer English, plus Telugu through Cloud speech only when the gateway is live; no language badges, no translation (ADR 0029, `LanguageScope.englishWithCloud`) | `-DENGLISH_ONLY_RELEASE` checked in the archive; `LanguageScopeTests` |
| 2.3 Accurate metadata | Screenshots or text promise more than the app does | Screenshots are the real screens; description lists only shipped features and says "Local mode" wherever it says nothing leaves the device; the price and trial appear as Apple requires | this document, `AppStoreScreenshotsUITests` |
| 2.3.7 Keywords | Third-party names | none used | section 3 |
| 2.4.1 iPad | Broken on iPad | Universal app, all iPad orientations, iPad screenshots | `verify-ios-appstore.sh` |
| 2.5.1 Public APIs | Private API | only public frameworks; no XCTest linked in Release | `verify-ios-appstore.sh` |
| 2.5.2 Downloaded code | Model download seen as code | Weights are data, pinned by SHA-256, downloaded after consent; stated in the review notes | ADR 0011, 0022 |
| 2.5.4 Background | Background audio misuse | No background modes; recording stops on leaving the app | `verify-ios-appstore.sh`, `RecordingEndingsUITests` |
| 4.2 Minimum functionality | "Just a recorder" | Review, cleanup modes, vocabulary, snippets, Action Button, on-device models | screenshots |
| 5.1.1(i) Privacy policy | Missing in-app link | Settings › About › Privacy Policy, and the App Store Connect URL | `AcknowledgementsTests`, section 3 |
| 3.1.1 In-app purchase | Unlocking features other than through StoreKit | The only purchase is the StoreKit subscription; no other payment, code, or link out | ADR 0034, `StoreKitSubscriptionServiceTests` |
| 3.1.2 Subscriptions | Missing price, length, renewal terms, Restore, or links | The offer shows the StoreKit price, the trial and renewal wording, Restore, Terms of Use, and Privacy Policy; the description repeats them | `UI/Mobile/PaywallView.swift`, `SubscriptionGateUITests`, MA-74 |
| 4.4.1 Keyboards | A keyboard that launches apps, needs Full Access without reason, or sends typing off the device | Typing keys and an insert from a dictation the person started; no Full Access (`RequestsOpenAccess` is false); no network; no microphone | `make security-check`, ADR 0032 |
| 5.1.1(ii) Permission strings | Vague purpose strings | Both strings say what and why, for Local and Cloud | `Config/LemmeTypeiOS.xcconfig`, `make security-check` |
| 5.1.1(iv) Pre-permission screens | A "Not Now" before the system prompt | The explanation has only Continue | `RecordingEndingsUITests.testTheExplanationOnlyContinuesToTheSystemPrompt` |
| 5.1.1 Privacy manifest | Missing required-reason APIs or collected data | UserDefaults (CA92.1), disk space (E174.1), file timestamps (C617.1) declared; whisper.cpp uses none of the listed APIs; the three collected data types are declared | `App/LemmeTypeiOS/PrivacyInfo.xcprivacy`, `make security-check` |
| 5.1.2 Data use | Labels wrong or out of step with the policy and the manifest | Audio Data, Purchases, and Other Usage Data are declared (App Functionality), tracking is No, and the policy, app, and manifest say the same | section 4, `make security-check`, `docs/backlog/reviews/epic-13-s8-agreement.md` |
| Legal (licences) | MIT notices missing from the binary | Settings › About › Acknowledgements | `AcknowledgementsTests` |
| Export compliance | Missing answer delays review | `ITSAppUsesNonExemptEncryption = NO` | `verify-ios-appstore.sh` |

No checklist removes the chance of a reviewer question; it removes the known reasons for
one. If App Review does write, answer in Resolution Center with the matching row.

## Mac: why not the Mac App Store for 1.0.0

The Mac App Store requires the App Sandbox (Guideline 2.4.5(i)) and forbids an app's own
update check (2.4.5(vii)). LemmeType's Mac app types the text into the app you were
using through the Accessibility API, which is why it runs without the sandbox
(ADR 0001); whether that insertion works sandboxed has never been tested (MA-61), and an
app that asks for Accessibility to control other apps is the kind App Review asks
questions about. Shipping the Mac app there now would risk exactly the review feedback
this release avoids.

**For 1.0.0 the Mac app is released by Developer ID: signed, notarized, and downloaded
from GitHub Releases** (ADR 0026, `docs/release/runbook.md`). It is not reviewed by App
Review; it needs the same Apple Developer Program membership for the certificate.
A Mac App Store version is a separate project: run MA-61 (sandboxed build, does insertion
still work?), build without the `Updates` module, and decide from the result.

## 9. Launch gates

The Cloud option is part of this release (decision of 2026-11-13) and sends the recording to a speech
service, so it ships only when every gate is **Closed** with evidence. `scripts/verify-ios-appstore.sh` refuses
an archive while any row below says `Open`, or while `LEMMETYPE_GATEWAY_HOST` is empty, staging, or a placeholder.
The same gates, with their background, are in
[ADR 0031](../decisions/0031-cloud-speech-provider.md#launch-gates).

| Gate | What closes it | Status |
|---|---|---|
| 1. Sarvam's written answer on training and retention for API accounts | A written confirmation or DPA from Sarvam, linked here; then add its statement to `docs/privacy-policy.md` (Cloud speech) and re-check the Audio Data row in section 4 | Open |
| 2. Training opt-out and retention set on the account | A screenshot or settings export of the production account, linked here | Open |
| 3. How keys reach the app | The gateway holds the key; no key in the app ([ADR 0033](../decisions/0033-speech-gateway.md), `LegacyCloudKeyEraser`) | Closed |
| 4. The 34-sentence Telugu–English test | The result, linked here, run against the production gateway | Open |
| 5. Production gateway live | `speech-gateway` deployed as `production` (its runbook), `appAppleId` set, App Store Server Notifications URLs set, and `LEMMETYPE_GATEWAY_HOST` set to its host | Open |
| 6. Documents say what is true | Network allowlist, threat model (T-25…T-28), privacy checklist, App Store labels, policy, in-app text, and brief updated in E13-S8 (`docs/backlog/reviews/epic-13-s8-agreement.md`) | Closed |

While gate 1, 2, 4, or 5 is Open, build and test with `LEMMETYPE_GATEWAY_HOST` empty (Cloud speech and the
Telugu choice are off) and do not submit: the store text above mentions Cloud speech and Telugu.
