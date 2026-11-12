# 0031 — Cloud speech: Sarvam first, behind a replaceable provider

- Status: Accepted (provider choice, 2026-11-09). Not implemented; launch gates below are open.
- Date: 2026-11-09
- Stories: [Epic 11](../backlog/epic-11-cloud-speech.md), E11-S1 … E11-S4, and [Epic 12](../backlog/epic-12-iphone-cloud-english.md) for iPhone (no GitHub issues yet)
- Updates: [ADR 0023](0023-multilingual-dictation.md), which rejected cloud speech outright

## Context

Local models are not accurate enough for Indian languages. On our corpus, Whisper Small
made 93 % character errors on Telugu, which is unusable. Larger local models are multi-GB
downloads, which the maintainer ruled out. The product goal is Telugu mixed with English
first, with more languages added one at a time.

ADR 0023 rejected cloud speech because it breaks the local-only promise. The product brief
rules out only *mandatory* cloud processing, so an opt-in engine that is off by default is
allowed if Local mode stays network-silent.

## Decision

### Provider

Use **Sarvam Saaras v4** (`saaras:v4`) with `mode=codemix` for Telugu with English, and
`mode=translate` when the user asks for English output.

Evidence, from `scripts/cloud-speech-eval.py` on FLEURS Telugu (2026-11-07; 133 clips that
every engine answered; [method](../testing/cloud-speech-evaluation.md)):

| Engine | Character errors | Word errors | Typical wait |
|---|---:|---:|---:|
| Sarvam `saaras:v4` | 4.9 % | 17.6 % | 0.56 s |
| Bodhan `indic-transcribe` | 8.2 % | 22.5 % | 0.90 s |
| Whisper Small (local) | 93.3 % | 109.7 % | 7.25 s |

Sarvam also documents a mode that keeps English words in English letters; Bodhan's API
reference shows no such option. Bodhan costs about a fifth as much (₹0.10 against Sarvam's
₹0.49 per audio minute, pay as you go).

**Accepted risk:** the choice was made without measuring real Telugu–English speech. FLEURS
is read speech with no English mixed in. The 34-sentence test
(`scripts/record-corpus.py`) is built and has not been run.

### Product rules

- **Off by default.** The user turns it on, and a consent screen names the provider and the
  host that receives the audio. Consent is stored per provider id, so a new provider asks again.
- **Chosen explicitly.** The cloud engine runs only when the user's mode names it. Automatic
  selection and `fallsBackToReadyEngine` never pick it, and it never falls back to or from a
  local engine silently. A failure ends in `needsAttention` with the existing actions.
- **Visible.** The recording overlay and the menu say the audio is going to the cloud.
- **Audio only.** Cursor context, selection, history, and clipboard are never sent. Vocabulary
  hints are not sent either: `RecognitionRequest.hints` promises they never leave the Mac.
- **Never for excluded or sensitive apps** (`ContextPolicy`); the app refuses before recording.
- **Telugu first.** Other languages are added one at a time, each after it is measured.
  English-only dictation stays on the local engines.
- A translation still ends in `DictationIssue.reviewTranslation` and is never delivered automatically.

### Staying replaceable

The rest of the app knows about one engine, `RecognitionEngineID.cloud`, never about a
vendor. Everything vendor-specific sits in one small adapter.

```
TranscriptionPipeline → RecognitionRunner → SpeechRecognitionEngine
                                              └─ CloudSpeechEngine (one, vendor-neutral)
                                                   ├─ CloudSpeechProvider   ← SarvamProvider (the only vendor code)
                                                   ├─ CloudSpeechTransport  ← the only new network file
                                                   └─ CloudCredentialProviding
```

`CloudSpeechProvider` (Domain, no OS frameworks) is pure: it turns a clip into a request
value and a response value into text, so an adapter needs no network to test.

```swift
public protocol CloudSpeechProvider: Sendable {
    var id: CloudSpeechProviderID { get }  // stored with the consent
    var displayName: String { get }
    var host: String { get }               // shown in the consent; enforced by the transport
    var maximumClipSeconds: Double { get }
    var supportedLanguages: [String] { get }
    var tasks: Set<RecognitionTask> { get }
    func request(for clip: CloudAudioClip, need: RecognitionNeed, credential: CloudCredential) throws(RecognitionError) -> CloudHTTPRequest
    func transcript(from response: CloudHTTPResponse) throws(RecognitionError) -> String
}
```

`CloudSpeechEngine` owns what does not depend on the vendor: converting audio to 16-bit WAV,
cutting long recordings at pauses to `maximumClipSeconds`, one request at a time, retries,
cancellation, and mapping failures to `RecognitionError`. `CloudSpeechProviderContract`
(TestSupport) is the check every adapter must pass, like `RecognitionEngineContract`.

| To change provider | What changes |
|---|---|
| Vendor code | One new adapter file and its contract test |
| Which provider is active | One line in `AppComposition` |
| Security review | The host in the network allowlist, the threat model, and App Store privacy labels |
| Evidence | A new entry in `scripts/cloud-speech-eval.py`; it must beat or match the current provider |
| Users | Consent is asked again, because the provider id changed |
| Pipeline, recorder, delivery, Settings, stored preferences | **Nothing** |

The active provider is compiled in, not remote configuration: where audio goes is always a
reviewed change. Streaming is out of scope; the contract is one final transcript per recording.

## Launch gates

No user audio goes to Sarvam until these are closed.

| Gate | Why | Status |
|---|---|---|
| Written confirmation or a DPA on training and retention for API accounts | Sarvam's documents disagree (below) | Open |
| Training opt-out and retention set on the account | Belt and braces while the terms disagree | Open |
| How keys reach the app | A shared key cannot ship inside the app (below) | Decided for the friends beta: each user's own key. Open for a public release |
| Run the 34-sentence Telugu–English test | The accepted risk above; it costs about ₹2 | Recommended before any beta |
| Network allowlist, threat model, privacy checklist, App Store labels, product brief wording | They say nothing leaves the device | Open |

### Sarvam's data terms disagree

| Source (read 2026-11-09) | Says |
|---|---|
| [Speech-to-Text page](https://www.sarvam.ai/speech-to-text) | API inputs are never used for training; zero retention after processing unless requested |
| [Trust Center](https://www.sarvam.ai/trust-center) | Retention is configurable per customer; an ephemeral mode exists; audio stays in India |
| [Privacy Policy](https://www.sarvam.ai/privacy-policy) | Content trains models unless you opt out; the policy does not apply to business offerings such as enterprise accounts |

Which applies to a pay-as-you-go API account is not settled. Audio from users outside India
would cross a border to reach India; the consent screen must say so.

### Keys

No API key is ever built into the app, encrypted or not: the app would have to decrypt it to use
it, so anyone with a copy could extract it.

| Stage | Approach | Trade-off |
|---|---|---|
| Friends beta (decided 2026-11-09) | Each user pastes their own key; stored in the Keychain | No server, no shared cost; too technical for a public release |
| Public release (proposed) | A small relay we run, which holds the key | Ongoing cost and a new party that sees audio. It would be a `CloudSpeechProvider` like any other |

Sarvam's pay-as-you-go limit is 60 requests a minute per account, enough for one person but
not for a shared key at release ([pricing](https://docs.sarvam.ai/api-reference-docs/pricing)).

## Alternatives considered

| Option | Why not |
|---|---|
| Bodhan `indic-transcribe` | Cheaper, but less accurate on Telugu, more often rate limited in our test, and no documented way to keep English in English letters. The natural first replacement if Sarvam's terms or price fail |
| Deepgram Nova-3 | Telugu alone only; its code-switching set does not include it |
| Soniox, ElevenLabs Scribe | Not tested. Candidates if Sarvam fails the mixed-speech test |
| Indic-Transcribe on the device | Keeps audio local, but 4.6 GB as shipped and no Mac runtime |
| A vendor-specific engine (`SarvamEngine`) | Quicker once, but a change of vendor would touch preferences, UI, and stored modes |

## Consequences

- LemmeType gains a third file that may use the network, and "local only" becomes "local unless
  you turn on Cloud". Local mode stays network-silent, and `NetworkSilenceTests` must still pass.
- Each user who turns it on sends audio to a third party, at about ₹29 per hour of audio.
- `RecognitionEngineID` gains a stable `cloud` value that never names a vendor.

## Addition: iPhone (E12-S1)

`Support` now imports Security for `KeychainCloudCredentialStore`: a new edge in the module table. Keys stay
on this device (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, no iCloud sync). The iPhone app offers cloud
speech only in Debug builds until the launch gates above close (`IOSComposition.offersCloudSpeech`).

## Addition: the gateway replaces each user's own key (E13-S3, ADR 0033)

The "Keys" table above chose each user's own key for the friends beta and a relay we run for a public
release. The relay is now built ([ADR 0033](0033-speech-gateway.md), `speech-gateway`), and the apps use it:

- `GatewaySpeechProvider` is the provider in the apps. It names LemmeType, not a vendor, and sends the audio,
  a `task`, and a `language` to the gateway. `SarvamProvider` stays in the code as the model for the server's
  adapter and is not registered in an app.
- The user enters nothing. `KeychainCloudCredentialStore`, the key field, and `ConsentedCloudCredentials`
  are gone. `LegacyCloudKeyEraser` deletes a key an earlier build stored.
- `GatewayService` trades the subscription for a 15-minute access token (E13-S2) and keeps it in memory only.
  `GatewayTransport` adds it to each request and replaces a refused token once. Until the subscription exists
  in the app (E13-S4), a Debug build can use a fixed staging token (`-LemmeTypeGatewayToken`).
- Consent is stored with the gateway's `consentVersion`. A vendor change inside the approved list keeps the
  number. Anything else raises it, and the app asks again before the next Cloud use. The check runs when the
  Cloud settings are shown and before each Cloud dictation, never at launch, so launching needs no network.
- The same `URLSessionCloudSpeechTransport` file remains the only network code for cloud speech, now allowed
  to reach the gateway host only. `Support` still imports Security, for the legacy eraser.

The launch gates above are unchanged except "How keys reach the app", which the gateway closes once E13-S4 and
E13-S8 land. Sarvam's data terms stay open.
