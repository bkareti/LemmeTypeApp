# Epic 11 — opt-in cloud speech for Indian languages

## Epic issue body

### Objective

Let a user who speaks Telugu mixed with English turn on a cloud speech engine and get
accurate text, while everyone else stays fully local and the provider can be replaced
without changing the rest of the app.

### Business value

Local models made 93 % character errors on Telugu; Sarvam made 4.9 % on the same clips
(ADR 0031). Multi-GB local models were ruled out. An opt-in engine serves these users
without changing the promise for anyone who leaves it off.

### In scope

- One vendor-neutral cloud engine, with Sarvam `saaras:v4` as its first provider.
- Telugu dictation (`codemix`, English words in English letters) and Telugu to English
  (`translate`, always through the existing review).
- Recordings longer than one provider request.
- Off by default: consent naming the provider, the user's own API key in the Keychain, a
  visible cloud indicator, and refusal in sensitive places.
- The privacy, security, and quality gates in ADR 0031.

### Out of scope

- Any language other than Telugu (added one at a time, each after it is measured).
- English-only dictation in the cloud; it stays on the local engines.
- Streaming or partial results.
- A relay server and shared API keys (needed for a public release; a separate decision).
- A provider picker for users, or changing the provider without an app update.
- iPhone and iPad (Epic 12 connects this engine to the iPhone app).

### Epic acceptance criteria

- All child stories are accepted.
- With cloud speech off, the app opens no new network connection, and `NetworkSilenceTests` passes.
- No audio leaves the Mac without consent for that provider, a stored key, and a mode that names the cloud engine.
- Automatic selection and engine fallback never choose the cloud engine.
- A test adds a second provider without changing the pipeline, recorder, Settings, or preferences.
- Every launch gate in ADR 0031 is closed before a Release build can use the cloud engine.

---

## E11-S1 — Add a replaceable cloud speech engine with a Sarvam provider

**User story**

As the product team, we want one vendor-neutral cloud engine with Sarvam behind a small
adapter so that we can change provider later by replacing only that adapter.

**Scope**

- Domain: `ProcessingLocation.cloud`, `RecognitionEngineID.cloud`, and the pure
  `CloudSpeechProvider` from ADR 0031, with `CloudHTTPRequest`, `CloudHTTPResponse`,
  `CloudAudioClip`, `CloudSpeechTransport`, and `CloudCredentialProviding`.
- `EngineSelector`: a cloud engine is used only when it is the `preferred` engine. It is
  never picked by Automatic, by `fallsBackAutomatically`, or listed in `alternatives`.
- `Recognition/Cloud/` (no new module): `CloudSpeechEngine`, `SarvamProvider`, and
  `URLSessionCloudSpeechTransport`, added to `docs/security/network-allowlist.txt`. The
  transport uses an ephemeral session with no cache or cookies, and refuses any host other
  than `provider.host`, including on a redirect.
- `SarvamProvider`: `POST https://api.sarvam.ai/speech-to-text`, `saaras:v4`, language
  `te-IN`, `mode=codemix` for transcribe and `mode=translate` for translate. Supported
  language: `te` only. `RecognitionRequest.hints` are never sent.
- The engine converts the recording to 16-bit WAV in memory, throws `.silentAudio` for a
  recording `SpeechActivity.isSilent` rejects (no upload, no charge), sends one request at
  a time, allows 20 seconds per attempt, retries rate limits and server errors twice with
  backoff, and stops when the session is cancelled.
- `RecognitionError` gains `cloudOffline`, `cloudKeyRejected`, `cloudRateLimited`,
  `cloudQuotaExhausted`, and `cloudServiceFailed`, each with a stable identifier, a
  message, and actions (Retry, Another Engine, Save Audio, Discard). Provider error text is never kept.
- TestSupport: `FakeCloudSpeechTransport`, `FakeCloudCredentials`, and
  `CloudSpeechProviderContract`. An opt-in real test runs with `LEMMETYPE_REAL_CLOUD=1`, never on CI.
- The engine is **not** added to `AppComposition` in this story; E11-S3 does that. A
  recording longer than `maximumClipSeconds` fails with a typed error until E11-S2.

**Acceptance criteria**

- `CloudSpeechEngine` passes `RecognitionEngineContract`, and `SarvamProvider` passes `CloudSpeechProviderContract`.
- Sarvam's request has the documented URL, header, and fields for transcribe and translate (unit tests against recorded response fixtures).
- A second test-only provider passes both contracts with no change outside its own file.
- `EngineSelector` tests show the cloud engine is chosen only when preferred, including when it is the only ready engine.
- The transport refuses another host and a redirect to another host (unit tests).
- HTTP 403, 429, 5xx, `insufficient_quota_error`, and no network each produce the matching typed error; 429 and 5xx retry at most twice (`ManualClock`).
- Without a key the engine reports `permissionUnavailable` and makes no request.
- Silent audio makes no request. Cancelling stops the request and never returns text.
- A canary test finds no transcript, audio, or key in logs, diagnostics, or errors.
- `make network-check`, `make security-check`, and `make test-unit` pass.

**Dependencies:** ADR 0009, ADR 0031  
**Estimate:** 8 points

---

## E11-S2 — Send long recordings to the cloud in parts

**User story**

As a Telugu speaker, I want a long dictation to work the same as a short one so that I
do not have to keep every sentence under 30 seconds.

**Scope**

- `CloudSpeechEngine` splits a recording longer than `maximumClipSeconds` at pauses,
  aiming for 25 seconds, and at the limit when there is no pause.
- Parts go one at a time, in order, and the text is joined with single spaces.
- `RecognitionUpdate.progress` reports parts finished.

**Acceptance criteria**

- A recording at or under the limit is sent as one request.
- No part exceeds `maximumClipSeconds`, and no audio is lost or duplicated at a cut (unit tests with generated audio).
- Cuts fall inside a pause when one exists within the window.
- If any part fails after retries, the session fails with that typed error, no partial text is delivered, and the recording is kept for Retry.
- Cancelling stops further uploads.
- Parts are held in memory and leave no extra files (`make privacy-check`).

**Dependencies:** E11-S1  
**Estimate:** 3 points

---

## E11-S3 — Let the user turn on cloud speech for Telugu

**User story**

As a Telugu speaker, I want to turn on cloud speech knowingly so that I get accurate
Telugu–English text and always know when my voice leaves my Mac.

**Scope**

- A *Cloud speech* section in Settings › Dictation, chosen from the existing *Show* menu
  (no new tab; the window width is fixed). Off by default.
- Turning it on shows a consent sheet naming the provider, the host, that audio is sent to
  India, and what is never sent. Consent is stored per provider id.
- The user pastes their own API key. `KeychainCloudCredentialStore` (Support) stores it in
  the login Keychain; it is never shown again, logged, or exported. No key is ever built into the app.
- After consent and a key, the app offers to create a custom **Telugu (Cloud)** dictation
  mode: language Telugu, engine Cloud, writing mode Exact. Other modes do not change.
- `AppComposition` registers the engine, behind one Release off-switch that stays off until E11-S4.
  `ENGLISH_ONLY_RELEASE` (ADR 0029) also hides Telugu in Release, so `LanguageScope` must offer Telugu for the Cloud mode when that switch is on.
- `LanguageSupportMatrix` rows for Telugu on `.cloud`, status `evaluation`.
- Reuses the consent store, Keychain store, and settings model from E12-S1 if that story is built first.
- The overlay and menu show a cloud indicator whenever the active engine's `location` is `.cloud`.
- Before recording with the cloud engine, the app refuses in excluded or built-in sensitive
  apps, password fields, and secure input, using a new `ContextPurpose` and a `DictationIssue`.
- The "everything runs on this Mac" text in Settings, privacy text, and onboarding becomes
  accurate for both states.
- Turning it off, or *Delete All Local Data*, removes the key and consent. A Cloud mode
  then shows as not ready and never runs on another engine.

**Acceptance criteria**

- On a fresh install the section is off, and no Cloud engine or mode is offered.
- No request is possible without consent for the current provider, a key, and a mode naming the engine (unit tests with `FakeCloudSpeechTransport`).
- A consent stored for another provider id is not accepted, and the sheet is shown again.
- The key is written only to the Keychain: canary tests find it in no preferences, export, diagnostics, or log.
- The indicator is visible for the whole session with the cloud engine and never with a local one.
- Each refusal case happens before recording starts and sends nothing.
- A Telugu (Cloud) failure offers Another Engine and never switches by itself.
- A Telugu to English result ends in the existing review and is not delivered automatically.
- Turn-off and Delete All Local Data remove the key and consent (unit tests).
- UI tests cover consent, cancel, and turn-off with fakes. VoiceOver labels exist, and `make l10n-check` passes.
- A Release build with the off-switch off shows no cloud option and has no way to reach the transport.

**Dependencies:** E11-S1, E11-S2, ADR 0017, ADR 0021, ADR 0025  
**Estimate:** 8 points

---

## E11-S4 — Close the privacy and quality gates and enable release

**User story**

As a user who trusts LemmeType's privacy promise, I want cloud speech released only after
its data handling and quality are proven so that turning it on is an informed choice.

**Scope**

- Record in ADR 0031 Sarvam's written answer or DPA on training and retention for API
  accounts, and the account's opt-out and retention settings.
- Run the 34-sentence Telugu–English test and record it. Pass limits are the ones proposed
  in `docs/testing/cloud-speech-evaluation.md`, once a product owner approves them.
- Update the threat model, privacy release checklist, product brief, data inventory
  (ADR 0025), and privacy labels.
- `NetworkSilenceTests` cover cloud off, and cloud on with a local mode active.
- Manual checks with the next free `MA-` numbers: consent, a real Telugu–English dictation,
  offline, wrong key, used-up credits, and turn-off.
- Turn on the Release off-switch from E11-S3 only when every gate is closed.

**Acceptance criteria**

- Each ADR 0031 gate shows Closed, with a link to its evidence.
- The Telugu–English results meet the approved limits, or the off-switch stays off.
- With a local mode active, the socket watch sees no connection, with cloud speech on or off.
- `make privacy-docs-check`, `make security-check`, and `make quality-gate` pass.
- The manual checks are recorded as passed on a signed build.

**Dependencies:** E11-S1, E11-S2, E11-S3, a written answer from Sarvam, the maintainer's recordings  
**Estimate:** 5 points

## Epic 11 story order

1. E11-S1
2. E11-S2
3. E11-S3
4. E11-S4
