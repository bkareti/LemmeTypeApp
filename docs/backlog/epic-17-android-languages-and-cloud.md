# Epic 17 — Android Indian languages, speech-to-English, and opt-in cloud

## Epic issue body

### Objective

Measure Hindi, Telugu, and mixed speech on Android phones, keep local multilingual models
behind the English-only scope until a language is validated, and offer opt-in cloud speech
through the LemmeType gateway without weakening Local mode
([plan](../android/android-plan.md) Phase 6; ADR 0023, 0029, 0031, 0033).

### Business value

Telugu and Hindi speakers are a core audience. Mac measurements already show local Whisper
Small is unusable for Telugu (93 % character errors); the gateway route serves them on
iPhone. Android needs the same route, with the same honesty about quality.

### In scope

- An on-device evaluation harness producing the existing report format.
- Multilingual Whisper in Debug builds, gated by `LanguageScope` and `LanguageSupportMatrix`.
- Gateway support for Android (Play Billing proof) in the `speech-gateway` repository.
- The cloud engine, consent, visible cloud state, and network confinement in the app.
- Translation review.

### Out of scope

- Local models larger than Small (maintainer ruled out multi-GB downloads).
- Languages not in the evaluation set (Tamil, Malayalam, Kannada come later, one at a time).
- Cloud for English (English stays local, Epic 13 decision).

### Epic acceptance criteria

- All child stories are accepted.
- No language is offered in a Release build without a `validated` row.
- Local mode remains network-silent (socket test) in a build that has `INTERNET`.
- Cloud is used only when the mode names it, after consent, with visible state; never for excluded apps.

---

## E17-S1 — Evaluate speech on Android phones

**Objective:** comparable accuracy and latency numbers from phones, not only the Mac.

**User story**

As the product owner, I want the same corpus scored on Android phones so that a language is
promoted only on measured results.

**Scope**

- Instrumentation-run evaluation (`-e corpus <path>`), Debug only, reading corpus audio from app-private storage pushed with `adb` (never committed).
- Output in the `EvaluationReport` JSON format so `scripts/evaluation-report.py` reads it.
- `make android-evaluation MODEL=… DEVICE=…` (not CI).

**Acceptance criteria**

- English Base.en run on two phones; WER within 2 points of the Mac for the same model, or the gap explained.
- Report passes `make evaluation-check` fixtures.
- No audio or transcript in the repository or CI logs.

**Dependencies:** E14-S12  
**Automated verification:** report schema test.  
**Physical-device verification:** the runs above.  
**Estimate:** 5 points (Medium)

---

## E17-S2 — Multilingual Whisper behind the language scope

**Objective:** Hindi and Telugu available for evaluation in Debug, invisible in Release.

**User story**

As an evaluator, I want to try Hindi and Telugu locally on Android with honest labels, and
as a beta tester I want to see only what works.

**Scope**

- Multilingual Tiny/Base/Small from the catalog fixture; `LanguageScope.allLanguages` in Debug, `englishOnly` in Release (build config field).
- Language detection limited to the evaluation set; `languageUncertain` instead of guessing.
- Labels "Evaluation" and "Not reliable" from `LanguageSupportMatrix`.

**Acceptance criteria**

- Release build lists English models only (test on the build config).
- Telugu shows "Not reliable" with the reason (test).
- Non-English text is written Exact (test).

**Dependencies:** E17-S1, E16-S1  
**Automated verification:** JVM tests; build-variant test.  
**Physical-device verification:** Hindi evaluation run on one phone.  
**Estimate:** 3 points (Small)

---

## E17-S3 — Accept Android subscribers in the speech gateway

**Objective:** the gateway (ADR 0033) can serve Android apps.

**User story**

As an Android subscriber, I want cloud speech to work without an account or API key, just
like on iPhone.

**Scope** (in `bkareti/speech-gateway`; cross-repository)

- Play Billing: the app sends a purchase token; the gateway verifies it with the Google Play Developer API (service account in Secret Manager), maps the product to an allowance in `apps.yaml`.
- Android app entry in `apps.yaml` (languages, tasks, consent version).
- Optional: Play Integrity verdict as an extra signal (open decision).
- Same error codes and token lifetime as iOS.

**Acceptance criteria**

- Contract tests with a fake Play API: valid, expired, refunded, wrong package.
- No audio, text, or purchase token stored or logged (existing gateway rule).
- Staging deploy verified with a license-test account.

**Dependencies:** maintainer decision D4 (billing), E17-S4 needs this  
**Automated verification:** gateway test suite.  
**Physical-device verification:** purchase with a Play license tester on internal testing.  
**Estimate:** 8 points (Large)

---

## E17-S4 — Opt-in cloud speech in the Android app

**Objective:** cloud speech that cannot leak into Local mode.

**User story**

As a Telugu speaker, I want to turn on Cloud for my Telugu mode, know exactly where my audio
goes, and keep English fully on my phone.

**Scope**

- Add `INTERNET` (allowlisted with a reason); `cloud-gateway` module is the only network code (network check allowlist line).
- Play Billing client (subscription, restore, state from Play), `GatewayClient` (token in memory, one retry on refusal), cloud `SpeechEngine` with `SpeechSplitter` behaviour from Apple.
- Consent screen naming the provider and host; consent stored per `consentVersion`.
- Engine runs only when the mode names it; never automatic fallback; excluded apps refuse before recording.
- "Audio goes to the cloud" on the recording strip and notification.

**Acceptance criteria**

- Local-mode socket test still passes in this build (test).
- Cloud engine is never selected without consent and a mode that names it (tests ported from Apple).
- Cloud silence guard: a no-speech clip never inserts text (gateway returned "Okay." for silence in staging).
- Data safety and privacy text updated (E18-S4).

**Dependencies:** E17-S3, E16-S1, E14-S16  
**Automated verification:** JVM tests with a fake transport; network check; socket test.  
**Physical-device verification:** Telugu synthetic clip via staging gateway; airplane mode shows a clear cloud error.  
**Estimate:** 8 points (Large)

---

## E17-S5 — Review translations before they are used

**Objective:** translated text is always seen before it is inserted or copied.

**User story**

As a user who speaks Telugu and wants English text, I want to read the English version and
choose to insert, copy, translate again, or discard.

**Scope**

- `DictationIssue.reviewTranslation` flow in Quick Dictation and the keyboard strip.
- Original and translation shown together; Translate Again reuses the audio until a decision, then it is deleted.

**Acceptance criteria**

- No translation is delivered without a tap (tests).
- Audio deleted after the decision (test).

**Dependencies:** E17-S4 (or E17-S2 for local Debug translation), E15-S4  
**Automated verification:** JVM tests.  
**Physical-device verification:** one translation via the keyboard into WhatsApp (not sent).  
**Estimate:** 3 points (Small)

---

## Epic 17 story order

1. E17-S1
2. E17-S2
3. E17-S3
4. E17-S4
5. E17-S5
