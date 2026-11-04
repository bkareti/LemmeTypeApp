# Language support matrix (E9-S1)

The matrix lives in code (`LanguageSupportMatrix`, Domain) and is tested; this
page explains it and holds the evaluation plan. A language is **validated**
only when a measurement record is linked from its row.

## Current status

| Language | Task | Engine | Recommended model | Status |
|---|---|---|---|---|
| English | Transcribe | Apple Speech, Whisper | Base | **Validated** (Epics 2 and 5) |
| Hindi | Transcribe, translate to English | Whisper (multilingual) | Small | Evaluation — measured below threshold (see [Measurements](#measurements-2026-11)) |
| Telugu | Transcribe | Whisper (multilingual) | Small | **Not reliable** — measured; Whisper Small gets most of it wrong (see [Measurements](#measurements-2026-11)) |
| Telugu | Translate to English | Whisper (multilingual) | Small | Evaluation — not measured on its own |
| Tamil, Malayalam, Kannada | — | — | — | Not selectable; next candidates |

Evaluation means the language can be chosen and is expected to work. It does
not mean any accuracy is promised. Settings labels these languages
"Evaluation".

Not reliable (`LanguageSupportStatus.unreliable`) means it was measured and the
largest model the app offers gets most of it wrong. The language can still be
chosen, for testing; Settings on the Mac and on iPhone and iPad says "Not
reliable" and why. A row is promoted only by a new measurement, for example with
a larger model.

Mixed speech (Telugu–English, Hindi–English) is evaluated with the language
setting on the main language and on Automatic. It is a scenario, not a row.

## Measurements (2026-11)

First real runs of the corpus evaluation (docs/testing/evaluation-harness.md):
FLEURS test, 200 recordings per language plus noise, clipping, padding, speed, and
long-dictation variants (435 speech runs per language), Whisper Small
(multilingual), Clean mode, Mac16,1 with 16 GB, macOS 27.0. "Before" is the
2026-11-02 run with whisper.cpp's default decoding; "after" adds the decoding
safeguards of [ADR 0028](../decisions/0028-whisper-decoding-safeguards.md). The
cause analysis comes from `WhisperDecodingDiagnosticsTests` (metrics only).

### Telugu with Whisper Small: a model limit (#137)

| | Before | After |
|---|---|---|
| Word error rate | 116 % | 114 % |
| Character error rate | 96 % | 95 % |
| Latency p50 / p95 | 7.3 s / 8.3 s | 3.6 s / 6.7 s |
| No text from speech | 0 % | 11.7 % (unsure output dropped as no speech) |
| Repetition loops | 1.6 % (20 % of long dictations) | 1.1 % (0 %) |

Why it is the model, not the app:

- At temperature 0, Small writes one run of Telugu script up to the decoder's
  per-window cap (219 tokens) for every recording, in clean audio too. With
  whisper.cpp's fallback the kept attempt is sampled at temperature 1.0: 60 % of
  its letters are Latin and its mean token log probability is −3.5. Neither path
  gets below 92 % character error rate, and no decoding setting tried (no
  fallback, best of 5, 5-beam search, shorter fallback) did either.
- Small barely hears Telugu as speech: the no-speech probability of Telugu speech
  is 0.44 at the median (Hindi 0.08, English at most 0.21), and language
  detection scores Telugu at 0.47 on average and picks it for about half of the
  Telugu recordings (Hindi: 0.75, 83 %).
- Hindi on the same model, the same audio pipeline, and the same settings
  scores 62 % / 30 %, so recording, resampling, and scoring are not the cause.

The app-side part was the latency: the fallback retried every window five times
up to temperature 1.0, which is the fixed ~7.3 s. ADR 0028 shortens the ladder.

Decision: `te` transcription is **not reliable** with the models offered.
Telugu stays selectable for testing and Settings says so. Translation from Telugu
was not measured on its own; it depends on the same recognition. A larger model
(Medium or Large, not in the catalog) is the next thing to evaluate.

### Hindi with Whisper Small: below threshold, model limit (#138)

| Slice | Speech runs | WER before → after | CER before → after | Latency p95 before → after |
|---|---|---|---|---|
| All | 435 | HINDI_ALL |
| Clean audio | 208 | HINDI_CLEAN |
| Noise SNR 20 / 10 / 5 | 50 / 50 / 25 | HINDI_NOISE |
| Long dictation | 10 | HINDI_LONG |

What was ruled out:

- **Scoring artifacts.** Normalizing numbers changes WER by less than 0.1 point;
  folding Hindi spelling variants (nukta, chandrabindu as anusvara) by about 0.5
  point. Whisper's published FLEURS numbers use a normalizer that strips Indic
  vowel signs, so they are not comparable with these.
- **Long dictation.** The long-dictation variant repeats every 20th recording
  three times. On those same recordings spoken once, WER is 81.4 %; as long
  dictations, 76.9 %. Length does not make it worse; the slice holds harder
  recordings. whisper.cpp keeps the decoded text as context from one 30-second
  window to the next within a recording (`no_context` only drops context from
  a previous recording), so context is not lost between windows. LONG_DICTATION_NOTE
- **Prompt.** The evaluation passes no vocabulary, so no English prompt steered
  these runs. (A vocabulary prompt is "Glossary: …" and was not evaluated with
  Hindi.)
- **Script and language.** 99 % of the letters written are Devanagari.

What remains is Whisper Small's accuracy on Hindi, worse in noise. Hindi stays
**Evaluation**: the Proposed threshold (WER ≤ 25 %) is far off.

## Hardware baseline

Apple silicon with at least 8 GB (recommended 8 GB for Tiny and Base, 16 GB for
Small), the same as the English models (ADR 0022). Intel Macs are unsupported.

## Proposed thresholds (awaiting product-owner approval)

| Metric | Hindi | Telugu | Notes |
|---|---|---|---|
| Review-rubric pass rate (meaning, names, numbers, dates, negation, intent) | ≥ 90 % of corpus items | ≥ 90 % | Translation and original text scored separately |
| Word error rate, original text (reference only) | ≤ 25 % | ≤ 30 % | Corpus must be human-verified |
| Real-time factor, Small, balanced profile, M-series | ≤ 1.0 | ≤ 1.0 | Inference ÷ audio duration |
| Stop → text shown, 10 s utterance, Small | ≤ 12 s | ≤ 12 s | Includes translation |
| Peak resident memory increase, Small | ≤ 1.2 GB | ≤ 1.2 GB | `peakMemoryIncreaseMB` |
| Automatic detection correct, evaluation languages | ≥ 95 % | ≥ 95 % | Below the confidence threshold counts as "uncertain", not wrong |

These numbers are **Proposed**. Epic 9 cannot be accepted until they are
approved or replaced (set the status below and record who approved them).

- Status: **Proposed**
- Approved by / date: —

## Corpus (for E9-S6)

- Licensed or consented only. Synthetic speech is allowed when the synthesis
  licence permits it; no recordings of real people without written consent.
- Per language: conversational, numeric (amounts, dates, phone-like numbers),
  names and places, negation ("do not", "never"), commitments ("I will send by
  Friday"), and short and long utterances.
- Mixed-language items: matrix-language sentences with English product names,
  numbers, and technical terms.
- Each item carries a human reference in the original language and an English
  reference. Corpus files contain no personal data and are not committed
  until their licence is recorded.

## Human review rubric

| Category | Pass when |
|---|---|
| Meaning | The English (or original) text says what the speaker said. |
| Names | Person, place, and product names are kept or transliterated recognisably. |
| Numbers and dates | Every number and date is present and correct. |
| Negation | No negation is added or dropped. |
| Intent | A request stays a request; a commitment stays a commitment. |
| No invention | Nothing is added that was not said. |

Each item scores pass or fail per category; an item passes when all categories
pass. Two reviewers score independently; disagreements are resolved by a third.
