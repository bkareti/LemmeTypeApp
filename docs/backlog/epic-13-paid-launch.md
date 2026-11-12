# Epic 13 — paid public launch: managed cloud speech, subscription, and keyboard microphone

## Epic issue body

### Objective

Let anyone download LemmeType on iPhone, try it free for 7 days, subscribe for $1.99 a month,
and dictate in English on the device or in Telugu and other languages through a LemmeType-run
cloud service, with no account, no API key, and a microphone key on the keyboard itself.

### Business value

Today cloud speech needs each user's own Sarvam key (too technical for the public) and the only
way to start a keyboard dictation is the Action Button, which many iPhones do not have. There is
no way to charge. This epic removes those three blocks to a public launch.

### Decisions already made (maintainer, 2026-11-12)

| Topic | Decision |
|---|---|
| Cloud keys | We run one server that holds the provider keys. The app contains no provider key and the user enters none |
| When to use which | English to English uses **Local**. Telugu and other languages use **Cloud** |
| Swapping providers | Must be possible later without changing the apps (ADR 0031 already keeps the provider replaceable) |
| Other apps | The server must be able to serve MeetQyl later |
| Price | **$1.99 per month** after a **7-day free trial**. One subscription covers Local and Cloud |
| Sign-in | None. The Apple ID and StoreKit identify the subscriber (Epic issue #142 was closed for this reason) |
| Keyboard | The LemmeType keyboard gets its own microphone key, so the Action Button is not required |

### In scope

- A speech gateway (the server): keys, access control, limits, cost caps, and a provider adapter. Built to host more than one app.
- The iPhone and iPad app calling the gateway instead of the user's own key.
- An auto-renewing StoreKit 2 subscription, the 7-day free trial, the paywall, restore, and a rule that dictation needs an active trial or subscription.
- A microphone key on the LemmeType keyboard, proven on a device first.
- Privacy text, privacy labels, and App Store information that are true for the paid, partly cloud app.

### Out of scope

- A Mac subscription. The Mac app is not on the Mac App Store, so how it is paid for is still open.
- Accounts, sign-in, or Firebase.
- MeetQyl changes. This epic only makes the gateway able to serve it (S1 proves it with a second test app).
- Languages other than Telugu and English, and streaming speech.
- App Attest or other device binding. Quotas already limit the damage from a copied token; revisit if usage shows sharing.
- Choosing a different speech vendor. Sarvam stays first; the gateway only makes a change cheap.

### Risks the maintainer should know

| Risk | Detail | Handled in |
|---|---|---|
| **Cloud speech can cost more than a subscriber pays** | Sarvam costs about ₹29 per hour of audio (ADR 0031). After Apple's commission, $1.99 is roughly ₹140–150 (exchange rate assumed, not checked), so about 5 hours of cloud audio a month breaks even | S2: per-person monthly cap and a global budget switch |
| Free trials can be repeated with new Apple IDs | Each trial could use cloud speech at our cost | S2: a small cloud allowance during the trial |
| Sarvam allows 60 requests a minute for the whole account | Every user shares it | S2: a global limiter below the provider limit; ask Sarvam for a higher limit before launch |
| Sarvam's data terms disagree (ADR 0031 launch gate) | Retention and training rules for an API account are not settled | S8: the launch gate stays closed until Sarvam answers in writing |
| Audio now passes through our server | "Local mode is network-silent" stays true; Cloud is no longer "your own account" | S1 (no audio stored), S4 (consent), S8 (policy and labels) |
| A keyboard that asks for Full Access gets stricter App Review | ADR 0032 says no Full Access today; the held-mic design needs it | S6 decides before S7 builds |
| The Apple Developer Program, Paid Applications Agreement, tax and banking forms are needed to sell | Without them no subscription can be created or tested end to end | S5 lists what the maintainer must do |

### Epic acceptance criteria

- All child stories are accepted.
- A fresh install on a real iPhone starts the free trial, dictates in English locally with the network off, and dictates Telugu through Cloud with no setup beyond switching it on and agreeing to the consent.
- A user who is not subscribed and has no trial cannot start a dictation, on the app, the Action Button, Shortcuts, and the keyboard.
- The gateway never stores audio or text, and a test proves it.
- Where audio goes, who receives it, and what is stored is described in the app, the privacy policy, and the App Store privacy answers, and all three agree.
- The ADR 0031 launch gates are each Closed with evidence, or Cloud stays off in the Release build.

---

## E13-S1 — Create the speech gateway

**User story**

As the maintainer, I want one server that holds the speech provider keys and turns an app's
audio into text so that no app ships a key, the provider can change without an app update, and
MeetQyl can use the same server later.

**Scope**

- A new private repository, `bkareti/speech-gateway` (default; the decision is recorded in a new
  ADR in this repository, next free number, before code starts). MeetQyl must not depend on the
  LemmeType repository. Language: TypeScript on Node 22. Hosting default: Google Cloud Run in
  `asia-south1` (Mumbai, near Sarvam) with Secret Manager. The maintainer confirms or changes
  these defaults in the ADR; nothing below depends on the vendor.
- Two environments, `staging` and `production`, with separate provider keys, separate hosts, and no key in any file or log.
- Public API `v1`, described by `openapi.yaml` (the source of truth):
  - `GET /v1/health`, with no secrets in the answer.
  - `GET /v1/capabilities`: the languages and tasks this app may use, `maximumClipSeconds`, and `consentVersion`.
  - `POST /v1/speech/transcriptions`: multipart with one 16 kHz mono 16-bit WAV (`audio`), `task` (`transcribe` or `translate`), and `language` (BCP-47). Answers `{ text, language, durationSeconds, requestId }`.
  - One error shape, `{ error: { code, message, retryAfterSeconds? } }`, with the codes `bad_request`, `unauthorized`, `subscription_required`, `rate_limited`, `quota_exceeded`, `unsupported_language`, `audio_invalid`, `audio_too_long`, `provider_busy`, `provider_unavailable`, `service_unavailable`.
- Access in this story is a placeholder: a static test token, off in production. S2 replaces it. Routes already read an `app` and a `subject` from the verified token, so S2 changes only how the token is made.
- A `SpeechProvider` interface and two implementations: `SarvamProvider` (`saaras:v4`; `codemix` for Telugu with English, `translate` for English output; behaves like the client adapter in `SarvamProvider.swift`) and `FakeProvider`. A contract test suite every provider must pass.
- Per-app configuration in `apps.yaml`, not in code: app id, allowed tasks and languages, maximum clip length, quotas (S2), and which provider serves each language and task. A second test app, `testapp`, with different limits proves the isolation.
- Audio and text live only in memory for the length of one request. Nothing is written to disk, a queue, a cache, or a log. Logs hold the request id, app id, status, duration, byte count, and provider latency only.
- Request size limit sized to `maximumClipSeconds` plus a margin; a request over it is refused before the body is read.
- A runbook (`docs/runbook.md`): deploy, roll back, rotate a provider key, switch a language to another provider, read the logs, and what to do when the provider is down.
- CI in the new repository: lint, type check, unit and contract tests, and an opt-in real-provider test (`GATEWAY_REAL_PROVIDER=1`).

**Acceptance criteria**

- `openapi.yaml` validates, and every route has a request and a response example that a test replays.
- A valid request through `FakeProvider` returns the documented answer; every error code in the list is produced by a test.
- Canary test: a request whose audio and text contain a unique marker leaves that marker in no log line, response header, file, or provider-call log (checked in the test process).
- The service writes no file during a request (test with a read-only working directory).
- `SarvamProvider` passes the provider contract tests against recorded fixtures; the opt-in real test returns text for one fixed Telugu clip.
- A request to `testapp` cannot use `lemmetype`'s languages, limits, or tokens, and the reverse (isolation test).
- Changing the provider for a language is one line in `apps.yaml` and needs no code change (test with two fake providers).
- A request larger than the limit is refused with `audio_too_long` without being read (test).
- `staging` is deployed from CI and `GET /v1/health` answers; the production deploy exists but takes no traffic until S2 is merged.
- The runbook steps are each followed once on `staging` and the result is recorded in the repository.

**Dependencies:** ADR 0031. Needs from the maintainer: the hosting account, a domain name for the gateway host, and a Sarvam production API key.  
**Estimate:** 8 points

---

## E13-S2 — Let only active subscribers use the gateway

**User story**

As the maintainer, I want the gateway to accept speech only from people with an active trial or
subscription, and to limit how much each person can use, so that cloud speech cannot cost more
than the subscription brings in.

**Scope**

- `POST /v1/session`: the app sends its StoreKit 2 signed transaction (JWS). The gateway verifies the certificate chain to Apple's root (Apple Root CA - G3, pinned in the repository), the bundle id, a product id listed in `apps.yaml`, the environment, that it is an auto-renewing subscription, that it has not expired, and that it is not revoked. Use Apple's App Store Server Library.
- It answers a short-lived access token (15 minutes, EdDSA) with `app`, `sub`, `plan` (`trial`, `paid`, `sandbox`), and `exp`. `sub` is an HMAC of the original transaction id with a server secret, so the token and the stored data hold no Apple ID and cannot be turned back into one.
- `POST /v1/apple/notifications`: App Store Server Notifications V2. The gateway verifies each signed payload and keeps, per `sub`, the status and expiry (renewed, expired, refunded, revoked, billing retry, grace period). A refunded or revoked subscription is refused within one token lifetime.
- The production gateway accepts `Sandbox` transactions (App Review uses them) with a tiny allowance (default 15 minutes a month) and never counts them as paid.
- Limits, all in `apps.yaml` and changeable without a release. Proposed defaults, to be approved by the maintainer in the PR:
  - `paid`: 180 minutes of cloud audio per calendar month.
  - `trial`: 30 minutes in total.
  - 20 requests a minute per `sub`.
  - A global limiter at 50 requests a minute (the provider allows 60 for the account) with a short queue; beyond it, `provider_busy` with `retryAfterSeconds`.
  - A global monthly budget in provider cost; at 50 %, 80 %, and 100 % the maintainer gets an alert, and at 100 % cloud answers `service_unavailable` while the apps keep working locally.
- Every success answer carries `X-Quota-Remaining-Seconds`. `quota_exceeded` carries the reset date.
- Stored per `sub` only: plan, status, expiry, month, seconds used, request count, last request time. Kept 35 days after expiry, then deleted. Nothing about content, devices, or locations. Network addresses are used for rate limiting in memory only.
- `GET /v1/account/usage` for the signed-in token: seconds used, allowance, and reset date, for the app to show.

**Acceptance criteria**

- A test transaction signed with a test certificate chain is accepted; one with a wrong bundle id, unknown product, expired date, revocation date, broken signature, or untrusted chain is refused with `unauthorized` or `subscription_required` (one test each).
- Replaying the Apple notification fixtures (`DID_RENEW`, `EXPIRED`, `REFUND`, `REVOKE`, `DID_FAIL_TO_RENEW`, `GRACE_PERIOD_EXPIRED`) moves the stored status as documented, and the next token request after a refund is refused.
- Two requests that together pass the monthly allowance: the second gets `quota_exceeded`. A new month resets it (clock injected in the test).
- The 51st request in a minute across all subscribers gets `provider_busy` and never reaches the provider (fake provider call count).
- At the global budget the gateway answers `service_unavailable` and records one alert event.
- The token holds no Apple ID, original transaction id, or email (decode test), and `sub` differs between two `apps.yaml` apps for the same transaction.
- A canary test finds no audio, text, or transaction id in logs or storage.
- A sandbox transaction in production gets the sandbox allowance and `plan: sandbox`.
- The apple-side steps use `staging` with Apple's sandbox, and one real sandbox purchase from the S5 build is accepted end to end (manual, recorded).

**Dependencies:** E13-S1. Real-purchase check needs E13-S5. Needs from the maintainer: App Store Connect in-app purchase key and issuer id for the server, and approval of the proposed limits.  
**Estimate:** 8 points

---

## E13-S3 — Use the gateway from the apps and remove the own-key setup

**User story**

As an iPhone user who speaks Telugu, I want to switch on Cloud and agree once so that I can
dictate without finding or pasting any key.

**Scope**

- A new `GatewaySpeechProvider` (a `CloudSpeechProvider`, id `lemmetype-gateway`) that sends the clip to `/v1/speech/transcriptions` and maps the error codes to `RecognitionError` and `DictationIssue` with the existing messages plus two new ones (`quota_exceeded`, `subscription_required`). `SarvamProvider` stays in the code as the model for the server adapter and is not registered in the apps.
- A small `GatewayAccess` (Support) that exchanges the StoreKit transaction for a token through `/v1/session`, keeps the token in memory only, refreshes it before expiry, and tries once more on `unauthorized`. It depends on a Domain protocol, so tests use a fake.
- `URLSessionCloudSpeechTransport` talks only to the gateway host; the network allowlist and the transport's host check change to the gateway host, and nothing else.
- Remove the key field, `KeychainCloudCredentialStore` use, and the "paste your key" copy from `CloudSpeechSettingsModel` and the iPhone Settings; delete any key a Debug build stored. Cloud is now one switch plus the consent sheet.
- The consent sheet names LemmeType's server and the speech service that receives the audio, says audio is sent only while a Cloud mode records, and is not stored by LemmeType. It is stored with the `consentVersion` from `/v1/capabilities`; a different version asks again before the next Cloud use. A change of speech vendor inside the approved list that does not change the country or the terms keeps the version; anything else must raise it.
- A Cloud mode shows the remaining allowance (from `/v1/account/usage`) and a plain message when it is used up; Local keeps working.
- English-only releases: Release builds still hide Telugu until S8 closes the launch gates. A single compile-time switch (`IOSComposition.offersCloudSpeech`, from E12-S1) turns the Cloud option on; this story does not flip it.
- Update ADR 0031 with an addendum (gateway replaces "each user's own key") and the Architecture section of `CLAUDE.md`.

**Acceptance criteria**

- With Cloud off, no request is made to any host (existing `NetworkSilenceTests` stay green; add one for the iPhone path).
- No request is made without consent for the current `consentVersion` (unit tests with `FakeCloudSpeechTransport` and a fake `GatewayAccess`).
- Changing `consentVersion` makes the next Cloud use ask again; the old consent is not accepted (test).
- Each gateway error code maps to the documented message, and none switches to another engine by itself (test).
- Canary tests find no token, audio, or text in preferences, exports, diagnostics, or logs; the token is never written to disk (test).
- No Keychain key code remains reachable from the iPhone app; a Debug upgrade removes a stored key (test).
- Telugu to English and Telugu with English each end in the existing review with Copy, and nothing reaches the clipboard before Copy (end-to-end test with fakes).
- Leaving the app during an upload ends in a typed failure with the recording kept, or a finished result (existing behaviour, re-checked).
- `make network-check`, `make security-check`, `make privacy-docs-check`, `make l10n-check`, and `make test-ios` pass; VoiceOver labels exist for the new screens.
- One real Telugu dictation against `staging` works on a physical iPhone (manual, recorded with a `MA-` number).

**Dependencies:** E13-S1, E13-S2, E12-S1, ADR 0031  
**Estimate:** 5 points

---

## E13-S4 — Sell the monthly subscription with a 7-day free trial

**User story**

As someone trying LemmeType, I want to start a free week and then pay a small monthly price
that I can cancel in Settings so that I know exactly what I am agreeing to.

**Scope**

- One subscription group and one auto-renewing monthly product, `com.lemmetype.LemmeType.iOS.pro.monthly` (default id; the maintainer may change it before the first App Store Connect save, because it cannot be reused or renamed later). Base price **$1.99 USD** (other countries use Apple's equivalent prices). Introductory offer: **free for 1 week**, new subscribers only. Family Sharing off.
- A `Subscriptions` module (depends on Domain + Support): `StoreKitSubscriptionService` implements the Domain protocol `SubscriptionProviding` with `purchase()`, `restore()`, the current `SubscriptionState` as an `AsyncStream`, and `product` (price, period, and whether this Apple ID can still get the trial, all read from StoreKit and never hard-coded). A `FakeSubscriptionService` in `TestSupport`.
- Listen to `Transaction.updates` from launch, finish verified transactions, and treat an unverified one as no subscription.
- `PaywallView` (UI module) shown at the end of onboarding and whenever S5 blocks a dictation. It shows, before the button: the price from StoreKit, "7 days free, then $1.99/month" when the trial is available, that it renews until cancelled, and how to cancel; **Terms of Use** and **Privacy Policy** links; **Restore Purchases**; and a button labelled with what happens ("Start 7-day free trial" or "Subscribe"). No dark patterns: a visible way to close the sheet and keep Settings and data tools.
- Settings › Subscription: status, renewal or expiry date, **Manage Subscription** (`AppStore.showManageSubscriptions`), Restore Purchases.
- `LemmeType.storekit` configuration file in the repository, with the same product, price, and offer, for local runs and tests (`StoreKitTest`).
- Terms of Use: a new `docs/terms-of-use.md` (default: Apple's standard EULA, linked in App Store Connect, unless the maintainer supplies their own).
- What the maintainer must do in App Store Connect (listed in `docs/release/app-store.md`): sign the **Paid Applications Agreement** and complete tax and banking, create the group and product, set the price and offer, add the review screenshot of the paywall, and create the App Store Server Notifications V2 URL (sandbox and production) pointing at S2's endpoint.

**Acceptance criteria**

- With the StoreKit test session: purchase with the trial starts `trialing` with an expiry 7 days out; renewal moves to `subscribed`; cancel keeps access until expiry; expiry moves to `expired`; refund moves to `revoked`; billing retry and grace period are reported (one test each, using `SKTestSession` time travel).
- The Apple ID that already used the trial sees "$1.99/month" and no trial wording (test with the second purchase).
- Purchase cancelled by the user, purchase pending (Ask to Buy), and an unverified transaction each leave the app without access and show a plain message (tests).
- Restore Purchases finds an existing subscription on a clean install (StoreKit test session).
- No price, duration, or trial length is written in code or strings: they all come from StoreKit (test that changing the `.storekit` price changes the paywall).
- The paywall meets App Review 3.1.2: price, period, trial, renewal, cancellation, and both links are visible without scrolling on iPhone SE and 6.9-inch sizes, at the largest Dynamic Type size, and with VoiceOver (UI tests with fakes).
- `make l10n-check` passes; no analytics or tracking is added.
- Manual, on a physical iPhone with a Sandbox Apple ID: start the trial, restore on a second device, cancel, and let it expire (accelerated renewal); results recorded with `MA-` numbers.
- A real sandbox purchase is accepted by the staging gateway (the E13-S2 manual check).

**Dependencies:** ADR 0027, the Apple Developer Program, the Paid Applications Agreement (needs the maintainer)  
**Estimate:** 8 points

---

## E13-S5 — Require an active subscription for dictation

**User story**

As the maintainer, I want dictation to work only during a trial or a paid subscription, on and
off the network, so that the app is a paid product without ever locking people out of their data.

**Scope**

- `EntitlementPolicy` (Domain, pure) turns `SubscriptionState`, the current date, and the last verified date into `allowed`, `allowedOffline(grace)`, or `blocked(reason)`. States: trialing, subscribed, billing retry (allowed for the grace period Apple reports), grace period, expired, revoked, and unknown.
- `StoreKit` verifies signed transactions on the device, including offline from the cached ones, so Local dictation needs no network per recording.
- Offline rule (proposed): a verified subscription is trusted until its expiry date plus 3 days when the device cannot reach the App Store; after that it is blocked until it renews. Clock guard: the last verified date is stored, and a clock set earlier than it is treated as unknown, not as more time.
- Where it applies: Quick Dictation, the Action Button intent, Shortcuts, Control Center control, and the keyboard's dictation. Each asks the same `EntitlementPolicy` before it records. A blocked start shows the paywall (in the app) or a short message (outside the app).
- An `EntitlementSummary` (state and expiry only, no identifiers) in the App Group, so the keyboard and intents can show a state without StoreKit. It is erased on Delete All Local Data.
- Never blocked, even when expired: opening Settings, Subscription, Manage Subscription, Restore, Export, Delete All Local Data, Privacy Policy, Terms, and Acknowledgements; typing with the LemmeType keyboard's normal keys. Saved modes, vocabulary, and history are kept.
- A visible trial countdown ("3 days left in your free trial") in Settings, and one in-app notice at 1 day left. No push notification.

**Acceptance criteria**

- A table test of `EntitlementPolicy` covers every state, the offline grace, the clock guard, and the boundary seconds (injected clock via `ManualClock`).
- With the StoreKit test session expired, a start from each entry point (app, Action Button intent, Shortcuts, keyboard) is refused before the microphone opens, and no audio is captured (tests with fakes).
- With airplane mode and a verified trial, Local dictation works and makes no network request (extends `NetworkSilenceTests`).
- After expiry the user can still open Settings, export and delete data, and type with the keyboard keys (UI test).
- Setting the device clock back by 30 days does not extend access (test).
- `EntitlementSummary` holds no Apple ID, transaction id, or other identifier (decode test) and is removed by Delete All Local Data.
- The paywall appears on a blocked start inside the app and returns to the same screen after purchase (UI test with fakes).
- `make test-ios`, `make test-ui-ios`, `make l10n-check`, and `make security-check` pass.

**Dependencies:** E13-S4  
**Estimate:** 5 points

---

## E13-S6 — Prove a keyboard microphone key on iPhones without an Action Button

**User story**

As a person whose iPhone has no Action Button, I want a microphone key on the LemmeType
keyboard so that I can start and stop dictation without leaving the app I am typing in.

**Background**

Device tests on 2026-11-10 (ADR 0032, `spike/keyboard-mic-session`) found: a keyboard extension has
no microphone. With Full Access off it cannot signal the app. With Full Access on, keyboard to app
signals work and the app can keep the microphone open in the background; that path captured real audio
with WhatsApp in front. Stopping the audio engine and restarting from the background failed. Apple's
guidance and App Review rule 4.4.1 forbid a keyboard that launches other apps, so the keyboard cannot
open LemmeType to start the microphone itself.

**Scope**

A proof, not shipping code, on a branch. It answers these questions with numbers and ends in a new
ADR (next free number, `Proposed`) that the maintainer approves or rejects.

1. **Arming.** How a session is started on an iPhone with no Action Button, without the keyboard launching the app. Try each: opening LemmeType and tapping Start, a Control Center or Lock Screen control, Back Tap running a Shortcut, and the Shortcuts app. Record which work from the lock screen and which need the phone unlocked.
2. **Session length.** How long the microphone can stay open in the background with a Live Activity showing End, and what ends it (timeout, memory, call, Siri, other audio, force-quit, low power mode).
3. **Tap to text.** Time from tapping the key to audio being captured, and from the second tap to the text in the field, in Messages, WhatsApp, and Notes.
4. **Safety.** The wrong-field guard still holds; the orange dot and the keyboard state show whenever the microphone is open; Stop ends capture even if the keyboard is closed.
5. **Cost.** Battery per hour with the session armed and idle; memory of the app; effect on music playback.
6. **Full Access.** What the key shows with Full Access off; that typing still works; and what the keyboard target contains that could use the network (it must be nothing).
7. **App Review.** Written reading of 4.4.1, 5.1.1, and the Full Access wording against this design, with the one-sentence reason shown in the Full Access explanation.
8. **Models.** Which iPhones were used, and whether one without an Action Button was available. If not, the same steps with the Action Button unconfigured, with the gap stated.

**Proposed pass thresholds** (the maintainer may change them in the PR)

- Key tap to captured audio: 95th percentile ≤ 500 ms over 20 taps.
- Second tap to text in the field: ≤ 2 s for a 10-second Local English clip.
- 20 start and stop cycles in 30 minutes across three apps with no missed tap and no text in the wrong field.
- Armed idle battery ≤ 10 % an hour on the test iPhone.
- An interruption (call, Siri, other audio) ends the session visibly, and the next arming works without restarting the iPhone.

**Acceptance criteria**

- Every question above has a result recorded in `docs/testing/ios-feasibility.md` with device, iOS version, and date.
- The new ADR states the chosen design, the Full Access request and its explanation, the session length limit, the End control, and what happens when the session ends.
- If a threshold fails, the ADR says so and proposes a fallback (for example an Action Button or Control Center-only flow with the keyboard showing status), and E13-S7 is changed before it starts.
- Manual acceptance steps for the mic key are added with the next free `MA-` numbers.
- No code from the proof is merged into `main`.

**Dependencies:** ADR 0032, PR #150. Needs from the maintainer: devices, including one without an Action Button if possible.  
**Estimate:** 5 points

---

## E13-S7 — Add the keyboard microphone key

**User story**

As an iPhone user, I want to tap a microphone key on the LemmeType keyboard, speak, tap again,
and see the text appear where I am typing so that I can dictate in any app without the Action Button.

**Scope**

Built to the design the maintainer approved in E13-S6. The defaults below are the recommended design,
and apply unless the ADR says otherwise.

- A microphone key on the keyboard's bottom row. States: not ready (no session), ready, listening (the recording view with a Stop key), writing, and failed. Words carry the state as well as colour and motion.
- A **dictation session**: the app keeps the microphone open for a limited time (default 15 minutes, proposed; the user picks 5, 15, or 30 in Settings) and ends it with an End button in a Live Activity, on the time limit, on an interruption, or when the iPhone locks. The microphone icon in the system (orange dot) shows while it is open.
- Starting a session never happens from the keyboard (rule 4.4.1). It starts from the app, a Control Center control, a Lock Screen control, an App Intent, or Back Tap through Shortcuts, which all use one `StartDictationSessionIntent`. A not-ready key shows two lines of help and the controls available.
- Commands go keyboard to app through a small `KeyboardCommandChannel` (start capture, stop capture) and the existing `KeyboardHandoff` returns the text. Text is inserted only into the field open when the capture started (existing guard). The channel carries no text from the screen.
- The keyboard asks for Full Access only for this key. Before the first tap it shows why in one sentence. With Full Access off, typing keys work and the mic key explains how to turn it on; nothing is sent.
- `scripts/check-security-config.py` changes from "the keyboard must not request Full Access" to "may request it, and the keyboard target must contain no network, speech, or audio-session code", and a test enforces the second part.
- Respect E13-S5: a blocked entitlement turns the key into "Subscribe in LemmeType".
- Modes, cloud speech, translation, and the pipeline are unchanged; the keyboard is one more way to start and stop the existing recorder.

**Acceptance criteria**

- Unit tests with fakes cover the key state machine for every transition: no session, session start, tap, second tap, interruption, time limit, End, force-quit recovery, blocked entitlement, Full Access off.
- Two taps in a row in the same field insert the text once, in that field; a field change between taps offers the text instead of inserting it (existing guard, re-tested).
- The microphone is never open without a visible session indicator (Live Activity) and the system orange dot; ending the session closes the audio engine (test with `FakeAudioSource` that records open and close).
- The keyboard target links no `URLSession`, `Network`, `AVFoundation`, `Speech`, or `AVAudioSession` symbol (the build check from `check-security-config.py`).
- The Full Access explanation, `RequestsOpenAccess`, `PrivacyInfo.xcprivacy` for the keyboard, the threat model, and the privacy checklist are updated together (`make privacy-docs-check` and `make security-check` pass).
- With Full Access off the typing keys work and the mic key shows the explanation (UI test).
- On a physical iPhone, E13-S6's thresholds hold for the shipped build, and the results are recorded with `MA-` numbers: Messages, WhatsApp, Notes, locked and unlocked arming, a phone call mid-session, and a force-quit.
- If E13-S6 recorded a failed threshold, this story's scope is updated by the maintainer before it starts.
- `make test-ios`, `make test-ui-ios`, `make l10n-check`, and `make quality-gate` pass.

**Dependencies:** E13-S6 (approved), E13-S5, ADR 0032  
**Estimate:** 8 points

---

## E13-S8 — Update privacy text and App Store information for the paid launch

**User story**

As a person deciding whether to install LemmeType, I want the App Store page, the privacy
answers, and the app to say the same true thing about what is paid for, what stays on my
iPhone, and what is sent to a server so that I am not surprised.

**Scope**

Changes the words, not the features, and closes the launch gates. Each item names the file it changes.

- `docs/privacy-policy.md` (and the in-app copy in Settings › Privacy): Local mode sends nothing; Cloud sends audio to LemmeType's server and then to the named speech provider, stores no audio or text, keeps usage numbers tied to a pseudonymous subscription code for 35 days after expiry, and uses Apple for payment. Names the countries involved. Lists the speech providers in use and how a change is announced. Describes the keyboard and Full Access in plain words.
- `docs/release/app-store.md`: sections 3, 4, 5, and 8.
  - Promotional text and description no longer say "no cloud" or "no account" without saying "Local mode"; they mention the free week and the price in the way App Review 3.1.2 and 2.3 allow.
  - **App Privacy answers** change from "Data Not Collected" to what is true (default, to be checked against the gateway design): Audio Data (Cloud only; App Functionality; not retained), Purchases, and Other Usage Data (App Functionality), each with the Linked to You answer decided from how the pseudonymous code is used; Tracking: No.
  - Subscription information, the review notes (how to start Cloud, a sandbox subscription, the keyboard Full Access and why), the review-risk checklist rows for 3.1.1, 3.1.2, 4.4.1, and 5.1.1, and the Terms of Use and Privacy Policy links in the metadata.
- `NSMicrophoneUsageDescription` (and `docs/security/usage-strings-allowlist.txt`), the keyboard's Full Access text, and the Quick Dictation "Before You Dictate" text: true for Local and Cloud.
- `PrivacyInfo.xcprivacy` for the app and the keyboard: collected data types and reasons that match the privacy answers.
- `docs/security/threat-model.md`, `docs/security/privacy-release-checklist.md`, `docs/security/network-allowlist.txt`: the gateway host, the new data flow, the tokens, and the keyboard channel. `make privacy-docs-check` and `make network-check` pass.
- `docs/release/app-store.md` § "Launch gates": update the ADR 0031 gates table. Each gate is Closed with a link, or the Cloud option stays off.
- Screenshots (`scripts/make-app-store-screenshots.sh`): add the paywall and the Cloud switch; check no screenshot shows a price that differs from StoreKit.
- The product brief wording about "network-silent" and "no account" now reads "Local mode is network-silent".

**Acceptance criteria**

- A reviewer checks every sentence about data in the policy, the app, and `app-store.md` against the code and the gateway, and records agreement in `docs/backlog/reviews/` (no sentence says nothing leaves the phone without saying "Local").
- The App Store Connect privacy answers are entered and a screenshot of the final answers is attached to the PR description by the maintainer.
- `make privacy-docs-check`, `make network-check`, `make security-check`, `make l10n-check`, `make docs-check`, and `make quality-gate` pass.
- `make ios-appstore-check` passes on a Release archive that contains the subscription and the keyboard changes.
- Each ADR 0031 gate is Closed with evidence: Sarvam's written answer on training and retention, the account opt-out and retention setting, the key route (the gateway), the 34-sentence Telugu–English result, and the updated documents. If any is Open, the Release build keeps `offersCloudSpeech` off and the App Store text says nothing about Telugu.
- A final pass on a physical iPhone from a clean install: first launch, trial, English offline, Telugu through Cloud, keyboard mic key, cancel, and expiry. Each is recorded with an `MA-` number, a device, and an iOS version.
- The build submitted to App Review has review notes with a working Sandbox subscription path.

**Dependencies:** E13-S3, E13-S4, E13-S5, E13-S7, a written answer from Sarvam, the Apple Developer Program  
**Estimate:** 5 points

---

## Epic 13 story order

1. E13-S1
2. E13-S2
3. E13-S4
4. E13-S3
5. E13-S5
6. E13-S6
7. E13-S7
8. E13-S8
