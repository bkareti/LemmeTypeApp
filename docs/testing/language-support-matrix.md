# Language support matrix (E9-S1)

The matrix lives in code (`LanguageSupportMatrix`, Domain) and is tested; this
page explains it and holds the evaluation plan. A language is **validated**
only when a measurement record is linked from its row.

## Current status

| Language | Task | Engine | Recommended model | Status |
|---|---|---|---|---|
| English | Transcribe | Apple Speech, Whisper | Base | **Validated** (Epics 2 and 5) |
| Hindi | Transcribe, translate to English | Whisper (multilingual) | Small | Evaluation — not measured |
| Telugu | Transcribe, translate to English | Whisper (multilingual) | Small | Evaluation — not measured |
| Tamil, Malayalam, Kannada | — | — | — | Not selectable; next candidates |

Evaluation means the language can be chosen and is expected to work. It does
not mean any accuracy is promised. Settings labels these languages
"Evaluation".

Mixed speech (Telugu–English, Hindi–English) is evaluated with the language
setting on the main language and on Automatic. It is a scenario, not a row.

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
