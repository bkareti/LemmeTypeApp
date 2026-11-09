# Cloud speech evaluation

`scripts/cloud-speech-eval.py` scores hosted speech-to-text services on the same corpus and
with the same rules as the local engines ([evaluation harness](evaluation-harness.md)), so
a cloud result and a Whisper result can be compared directly. It exists to decide whether
an **opt-in, off-by-default** cloud engine for Indian languages is worth building. It is
not part of the app, and the app stays network-silent.

## What it does

| Step | Detail |
|---|---|
| Choose cases | Original recordings from a corpus manifest (default `docs/testing/corpus/fleurs.json`), optionally `--languages hi,te` and `--limit N` per language. |
| Dry run | Without `--yes`, it prints how many recordings, how many minutes, which host, and the estimated cost. Nothing is uploaded. |
| Upload | With `--yes`, each recording is checked against its manifest SHA-256 and sent once. Rate limits and server errors are retried. |
| Cache | Answers go to `~/Library/Caches/LemmeTypeCorpus/cloud/<engine>-<task>/` (0600), outside the repository, so a rerun costs nothing. |
| Report | An `EvaluationReport` (schema 2) in `build/evaluation/cloud/`: metrics and case ids only, never text. |
| Compare | `compare` pools word and character error rates per language over the cases every report ran. |

Scoring is a Python copy of `TranscriptNormalizer`, `EditAlignment`, `NumberNormalizer`,
`TranscriptScore`, and `CharacterNGramStatistics`. `scripts/tests/test-cloud-speech-eval.py`
(part of `make evaluation-check`) checks it against the cases the Swift tests use.
Translations get chrF only: the `PreservationChecker` meaning checks are Swift-only, so they
are left out rather than reported as passing.

## Providers

| `--provider` | Model | Tasks and outputs | Key |
|---|---|---|---|
| `bodhan` | `indic-transcribe` ([API reference](https://console.bodhan.ai/api-docs/)) | transcribe (native script) | `BODHAN_API_KEY` |
| `sarvam` | `saaras:v4` ([API reference](https://docs.sarvam.ai/api-reference-docs/speech-to-text/transcribe)) | transcribe (`--output native` or `codemix`), translate to English | `SARVAM_API_KEY` |

Both accept at most 30 seconds per request; every FLEURS recording is shorter.

## Keys

Keys come from the environment or from `~/.config/lemmetype/cloud-eval.env` (`KEY=value`
lines, readable by you only; the script refuses a file others can read). To save a key
without it appearing on screen or in shell history:

```bash
(umask 077 && mkdir -p ~/.config/lemmetype && read -rs "k?Bodhan API key: " && print -r -- "BODHAN_API_KEY=$k" >> ~/.config/lemmetype/cloud-eval.env); echo
```

## Run

```bash
python3 -I scripts/cloud-speech-eval.py run --provider bodhan --languages hi,te
```

```bash
python3 -I scripts/cloud-speech-eval.py run --provider bodhan --languages hi,te --yes
```

```bash
python3 -I scripts/cloud-speech-eval.py compare build/evaluation/cloud build/evaluation/whisper-small-transcribe-clean.json
```

The Whisper report ran the Clean mode; non-English text is written Exact (ADR 0023), so for
Hindi and Telugu it is comparable with the cloud engines' raw output.

## Telugu with English

The final choice of service rests on real mixed speech, which no licensed dataset covers.
`scripts/record-corpus.py` asks for consent, then records 24 Telugu–English sentences and
10 English sentences from `docs/testing/corpus/prompts/telugu-english.json`. Audio and the
manifest stay in `~/Library/Caches/LemmeTypeCorpus/consented/telugu-english/`. Have a
Telugu speaker correct the script before recording: the script is the reference.

```bash
python3 -I scripts/record-corpus.py
```

Each mixed sentence has two references, because they answer different questions:

| Report | Reference | Question |
|---|---|---|
| normal | English words in English letters ("meeting") | Is the text ready to use as it comes back? The "English kept" column counts those words. |
| `-native-reference` | English words in Telugu script ("మీటింగ్") | Did the service hear the words correctly, whichever script it wrote them in? |

```bash
python3 -I scripts/cloud-speech-eval.py run --provider sarvam --output codemix --manifest ~/Library/Caches/LemmeTypeCorpus/consented/telugu-english/manifest.json --root ~/Library/Caches/LemmeTypeCorpus/consented/telugu-english --out build/evaluation/cloud-telugu-english --yes
```

Run the same line for `--provider bodhan` (without `--output codemix`), then add
`--reference-field referenceNative` to either: answers are cached, so that costs nothing.

```bash
python3 -I scripts/cloud-speech-eval.py compare build/evaluation/cloud-telugu-english
```

Proposed pass for the chosen service (not yet approved by a product owner): on the mixed
sentences, character errors at most 15 % and English kept at least 90 %; on the English
sentences, character errors at most 5 %; no request fails when clips are sent one at a time.

## Privacy

Only corpus audio is uploaded: public FLEURS recordings (CC BY 4.0), or consented
recordings whose manifest records that consent. Never upload a user's dictation or any
recording made without written consent that names this use. The provider's own retention
terms apply to what is uploaded; check them before uploading consented recordings.

## Limits of the comparison

- FLEURS is read speech with no English words mixed in. It measures Indian-language
  accuracy, not code-mixing; code-mixed recordings need the consented set described in
  [the corpus README](corpus/README.md).
- FLEURS references write numbers as digits. The "numbers as digits" column folds English
  number words only, not Hindi or Telugu ones.
- Latency is the round trip from this Mac, including upload, and depends on the network.
