# Epic 12 — English writing from Telugu and English speech on iPhone

## Epic issue body

### Objective

Let someone on iPhone speak Telugu, Telugu mixed with English, or English, and get clean
English text to review and copy.

### Business value

iPhone is the device people have with them when they want to write quickly. Today the
iPhone app has only local Whisper for Telugu, which is too inaccurate to use, and English
dictation does not fix grammar. The cloud engine from Epic 11 already builds for iPhone.

### In scope

| You say | Language to choose | You get | How |
|---|---|---|---|
| Telugu | Telugu | English | Sarvam `translate` (cloud) |
| Telugu mixed with English | Telugu | English | Sarvam `translate` (cloud) |
| English | English | English with corrected grammar | Local recognition, then Apple's on-device model |

- Cloud speech on iPhone: off by default, consent, the user's own API key in the Keychain.
- Two ready-made modes, so the user picks one choice instead of three settings.
- A grammar option for English that keeps the speaker's words and facts.
- Proof on a real iPhone.

### Out of scope

- Typing into other apps from iPhone. Delivery stays review, then Copy (ADR 0027).
- Telugu text as the output on iPhone (Epic 11 covers `codemix`; iPhone can add it later).
- Languages other than Telugu and English.
- One mode that works out the language by itself (not measured; see the readiness review).
- A relay server or a key built into the app (ADR 0031).
- A grammar step after a translation: Sarvam's English goes straight to review.

### Epic acceptance criteria

- All child stories are accepted.
- With cloud speech off, the iPhone app makes no new network connection.
- Telugu and mixed speech end in the existing review, in English, and nothing is copied until the user taps Copy.
- English grammar correction changes no name, number, date, negation, or commitment; anything else keeps the original text.
- A Release build keeps cloud speech off until every gate in ADR 0031 is closed.

---

## E12-S1 — Connect cloud speech to the iPhone app

**User story**

As an iPhone user who speaks Telugu, I want to turn on cloud speech with my own key so
that my phone can use accurate recognition, knowing my voice leaves the device.

**Scope**

- Shared by iPhone and Mac: `KeychainCloudCredentialStore` (Support; this-device-only, never
  synced), a consent store keyed by provider id, and `CloudSpeechSettingsModel` (UI). If
  E11-S3 is built first, this story reuses them.
- A *Cloud speech* section in `MobileSettingsView`, off by default. Turning it on shows a
  consent sheet naming the provider and host, saying audio goes to India, and listing what is
  never sent. Then the user pastes a key, which is never shown again.
- `IOSComposition` registers `CloudSpeechEngine` with `SarvamProvider`. The registration is
  on in Debug and behind one off-switch in Release until E12-S4.
- `LanguageReadiness` and `LanguageSupportMatrix` learn about `.cloud` rows for Telugu
  (status `evaluation`), so a Cloud choice is judged by the cloud engine and not by Whisper.
- `languageScope`: Release stays English only until the off-switch changes.
- A cloud indicator on the Quick Dictation screen for the whole session.
- Text that says audio stays on the device becomes true in both states: Quick Dictation,
  Privacy and Data, and `NSMicrophoneUsageDescription` (with `docs/security/usage-strings-allowlist.txt`).
- Turning it off, or Delete All, removes the key and consent.

**Acceptance criteria**

- On a fresh install the section is off and no Cloud engine is offered.
- No request is possible without consent for the current provider and a stored key (unit tests with `FakeCloudSpeechTransport`).
- A consent stored for another provider id is not accepted.
- The key is only in the Keychain: canary tests find it in no preferences, export, diagnostics, or log.
- The indicator shows for a cloud session and never for a local one.
- Leaving the app during an upload ends in a typed failure with the recording kept, or in a finished result; never in lost audio with no message.
- Turn-off and Delete All remove the key and consent (unit tests).
- UI tests cover consent, cancel, and turn-off with fakes; VoiceOver labels exist; `make l10n-check` and `make security-check` pass.
- A Release build with the off-switch off shows no cloud option and has no way to reach the transport.

**Dependencies:** E11-S1, ADR 0027, ADR 0029, ADR 0031  
**Estimate:** 8 points

---

## E12-S2 — Turn Telugu and mixed speech into English on iPhone

**User story**

As a Telugu speaker on iPhone, I want to speak Telugu or a Telugu–English mix and get
English text so that I can write in English without typing.

**Scope**

- After consent and a key, offer a custom **Telugu to English (Cloud)** mode: language Telugu,
  output English, engine Cloud. Choosing it from Quick Dictation takes one tap.
- Recordings up to the iPhone's five-minute limit, using E11-S2's parts.
- The result ends in the existing translation review: Copy, Translate Again, Discard.
- *Translate Again* warns that it uploads the recording again.
- Failures show the Epic 11 messages. A failure never switches engine by itself.

**Acceptance criteria**

- A Telugu recording in this mode sends `mode=translate` and `language_code=te-IN`, and ends in `reviewTranslation` with English text (end-to-end test with fakes).
- Nothing reaches the clipboard until the user taps Copy.
- A recording at the five-minute limit is sent in parts, and the text is joined in order.
- With no key, or offline, the user sees the matching message, and the recording is kept for Retry.
- The mode shows as not ready after cloud speech is turned off, and never runs on another engine.

**Dependencies:** E11-S2, E12-S1  
**Estimate:** 5 points

---

## E12-S3 — Correct English grammar on-device

**User story**

As someone dictating in English, I want my grammar corrected without my meaning changing
so that the text is ready to send.

**Scope**

- `StyleOptions` gains `correctsGrammar` (off by default; tolerant decoding, so saved modes keep
  working). A style with it on is not `isNone`, and its `identifier` changes only when it is on.
- `StyleInstruction`: a fixed instruction to correct grammar, spelling, and punctuation only, and
  to keep the speaker's wording otherwise. It is never built from dictated text.
- A built-in **Proper English** mode: English, Clean Writing, `correctsGrammar` on.
- The Modes editor offers the option on iPhone and Mac.
- It uses the existing path: `FoundationModelsRewriter`, `PreservationChecker`, then a review with the original one tap away.
- No cloud: this path ships in Release under the English-only scope.

**Acceptance criteria**

- With the option off, the model is never called and existing modes behave exactly as before (existing tests stay green).
- A saved mode without the new key loads with the option off.
- The instruction is deterministic and contains no dictated text (unit test).
- A rewrite that changes a name, number, date, negation, or commitment is rejected, and the original is offered (unit test with `FakeTextRewriter`).
- On a device without Apple Intelligence, the user gets the cleaned-up text and a clear notice, with no failure.
- Every result ends in a review; nothing is copied automatically.
- An opt-in real-model test covers a fixed set of grammar errors with `LEMMETYPE_REAL_REWRITE=1`.

**Dependencies:** ADR 0024  
**Estimate:** 5 points

---

## E12-S4 — Prove it on a real iPhone and close the gates

**User story**

As the product owner, I want evidence from a real iPhone so that we release this only
when it works and its data handling is settled.

**Scope**

- Manual checks with the next free `MA-` numbers on a physical iPhone: Telugu, mixed speech, English grammar, offline, wrong key, used-up credits, leaving the app mid-upload, and turn-off.
- Record the 34-sentence test (`scripts/record-corpus.py`) and add a `translate` result for the mixed sentences, with a person reading a sample for meaning.
- A reviewer reads 20 English grammar results for changed meaning.
- Update the privacy labels, privacy policy, and App Store text for the cloud option.
- Turn on the Release off-switch only when every ADR 0031 gate is closed.

**Acceptance criteria**

- Each manual check is recorded as passed on a named device and OS.
- The human review finds no changed name, number, date, negation, or commitment in the samples.
- Each ADR 0031 gate shows Closed with a link to its evidence, or the off-switch stays off.
- `make quality-gate` and `make test-ios` pass.

**Dependencies:** E12-S1, E12-S2, E12-S3, a written answer from Sarvam, recordings from the maintainer  
**Estimate:** 3 points

## Epic 12 story order

1. E12-S1
2. E12-S2
3. E12-S3
4. E12-S4
