# App Store submission — LemmeType 1.0.0 for iPhone and iPad

Everything needed to put the iPhone and iPad app on the App Store, written so App
Review has no reason to come back with questions. The Mac app is released by
Developer ID download instead; see [Mac](#mac-why-not-the-mac-app-store-for-100).

## 1. One-time setup (needs you)

1. Join the **Apple Developer Program** (paid) with the account that will own the app.
2. In **Certificates, Identifiers & Profiles**, register the App ID
   `com.lemmetype.LemmeType.iOS` (no capabilities needed: no App Groups, no background
   modes, no push).
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
screen, iPhone + iPad, icon, privacy manifest (no tracking, no collected data), arm64,
no XCTest or Swift Testing linked, embedded framework metadata and minimum iOS, no
recordings inside, and the English-only build flag.

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
| Price | Your choice (the app has no in-app purchases) |
| Privacy Policy URL | https://github.com/bkareti/LemmeTypeApp/blob/main/docs/privacy-policy.md |
| Support URL | https://github.com/bkareti/LemmeTypeApp/blob/main/docs/support.md |
| Marketing URL | leave empty |
| Copyright | 2026 <your legal name or company> |
| Version | 1.0.0 (build from `Config/Version.xcconfig`) |

**Promotional text (≤ 170):**

> Speak, check, copy. Your voice becomes text on your iPhone or iPad — no account, no cloud, no tracking.

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
> • Your voice is turned into text on your device and never leaves it.
> • No account, no sign-in, no ads, no analytics, no tracking.
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
>
> LemmeType understands English.
>
> So the microphone is never left on, a recording stops when you leave the app, when a call comes in, or after five minutes.

**What's New (1.0.0):**

> The first release of LemmeType for iPhone and iPad.

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

- **Do you or your third-party partners collect data from this app?** No → label
  **"Data Not Collected"**.
- Tracking: no. The app has no IDFA use and no tracking domains (`PrivacyInfo.xcprivacy`).
- Why this is accurate: audio, text, vocabulary, history, and settings stay on the
  device; there is no account, analytics, crash reporting, or advertising SDK. The only
  network request on iPhone is a model download the user confirms, which sends nothing
  about the user (Apple's definition of "collect" is data sent off the device and kept).

## 5. App Review information

- **Sign-in required:** No.
- **Contact:** your name, phone, and email (App Review only).
- **Notes** (paste as is):

> LemmeType is a voice-to-text app. Nothing requires an account.
>
> To test:
> 1. Tap "Start Dictating". A short explanation appears; tap Continue. iOS then asks for the microphone and for Speech Recognition — please allow both (the app uses Apple's on-device speech recognition).
> 2. Speak an English sentence and tap Stop.
> 3. Read the text and tap Copy, then paste it in Notes.
>
> Privacy: speech recognition runs on the device only (SFSpeechRecognizer with requiresOnDeviceRecognition). No audio or text leaves the device, and the app collects no data.
>
> Optional: Settings › Models offers open-source Whisper speech models (MIT licence, from huggingface.co). They are model weights (data, not code), downloaded only after the user confirms the size, and verified by SHA-256.
>
> The app has no background modes. A recording stops when the app leaves the foreground, on an interruption such as a call, or after five minutes. The "Start Dictating" App Shortcut can be assigned to the Action Button or Back Tap.
>
> Tone rewriting uses Apple's on-device Foundation Models framework and appears only on devices that support it.

- **Export compliance:** the build declares `ITSAppUsesNonExemptEncryption = NO` (only
  HTTPS for the model download), so App Store Connect does not ask.

## 6. Screenshots

`scripts/make-app-store-screenshots.sh` writes them to `build/app-store-screenshots/`:

| Set | Device | Size | Screens |
|---|---|---|---|
| iPhone 6.9" (required) | iPhone 18 Pro Max | 1320 × 2868 | ready, recording, review, copied, settings, privacy |
| iPad 13" (required, the app runs on iPad) | iPad Pro 13-inch (M5) | 2064 × 2752 | same |

They are the real screens (the UI-test build, English-only, with a fixed sentence
standing in for speech) and the standard 9:41 status bar. Upload 3–6 per set, in order.

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

These are also MA-66…MA-72 in `docs/testing/manual-acceptance.md`.

## 8. Review-risk checklist

| Guideline | Risk | How 1.0.0 meets it | Evidence |
|---|---|---|---|
| 2.1 App completeness | Reviewer cannot dictate on first try | Speech Recognition is asked with the microphone on the first dictation when no engine is ready | `QuickDictationModelTests.theFirstStartAsksForSpeechRecognitionAfterTheExplanationWhenNeeded` |
| 2.2 Beta testing | "Beta", "evaluation", "not reliable" text | Release builds are English only; no language badges, no translation (ADR 0029) | `-DENGLISH_ONLY_RELEASE` checked in the archive |
| 2.3 Accurate metadata | Screenshots or text promise more than the app does | Screenshots are the real screens; description lists only shipped features; English only stated | this document |
| 2.3.7 Keywords | Third-party names | none used | section 3 |
| 2.4.1 iPad | Broken on iPad | Universal app, all iPad orientations, iPad screenshots | `verify-ios-appstore.sh` |
| 2.5.1 Public APIs | Private API | only public frameworks; no XCTest linked in Release | `verify-ios-appstore.sh` |
| 2.5.2 Downloaded code | Model download seen as code | Weights are data, pinned by SHA-256, downloaded after consent; stated in the review notes | ADR 0011, 0022 |
| 2.5.4 Background | Background audio misuse | No background modes; recording stops on leaving the app | `verify-ios-appstore.sh`, `RecordingEndingsUITests` |
| 4.2 Minimum functionality | "Just a recorder" | Review, cleanup modes, vocabulary, snippets, Action Button, on-device models | screenshots |
| 5.1.1(i) Privacy policy | Missing in-app link | Settings › About › Privacy Policy, and the App Store Connect URL | `AcknowledgementsTests`, section 3 |
| 5.1.1(ii) Permission strings | Vague purpose strings | Both strings say what and why, on this device | `Config/LemmeTypeiOS.xcconfig` |
| 5.1.1(iv) Pre-permission screens | A "Not Now" before the system prompt | The explanation has only Continue | `RecordingEndingsUITests.testTheExplanationOnlyContinuesToTheSystemPrompt` |
| 5.1.1 Privacy manifest | Missing required-reason APIs | UserDefaults (CA92.1), disk space (E174.1), file timestamps (C617.1) declared; whisper.cpp uses none of the listed APIs | `App/LemmeTypeiOS/PrivacyInfo.xcprivacy` |
| 5.1.2 Data use | Labels wrong | "Data Not Collected" is accurate | section 4 |
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
