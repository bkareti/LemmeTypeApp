# 0028 — Whisper decoding safeguards

- Status: Accepted. The thresholds are **Proposed** until the quality thresholds are
  approved (E9-S6, Epic 7).
- Date: 2026-11-03
- Issues: #135 (text from audio without speech), #136 (repetition loops), #137 (Telugu
  runaway decoding)

## Context

The first real corpus evaluation (2026-11-02, Mac16,1, Whisper Small) found that Whisper
wrote text from noise and tones (37.5 % of no-speech cases with `whisper-small-en`, 62.5 %
with multilingual `whisper-small`), fell into repetition loops (1.4 % of runs, 20 % of
Telugu long dictations), and took about 7.3 s for almost every Telugu clip whatever its
length.

`WhisperCppRuntime` called `whisper_full_default_params(WHISPER_SAMPLING_GREEDY)` and
changed nothing that affects decoding. `WhisperDecodingDiagnosticsTests` (opt-in, metrics
only) measured why, on the fetched corpus and the English benchmark:

| Finding | Evidence |
|---|---|
| whisper.cpp's no-speech probability is always about 0 for multilingual models | It is read after the prompt's last token. For a multilingual model that is the task token, after the language token, where the no-speech token is almost never predicted; OpenAI reads it right after start-of-transcript. On `whisper-small-en` (prompt = start-of-transcript only) both readings agree to two decimals. So whisper.cpp's own gate (`no_speech_thold`) never fired for `whisper-small`, and every failed window went on to the temperature fallback. |
| The text from noise in Hindi and Telugu comes from the fallback | With fallback off, all 15 Hindi and Telugu noise and tone cases decode to nothing. With it on, they produce 1–65 tokens at a mean log probability of −0.9 to −13.9. |
| Telugu runs the whole fallback ladder | At temperature 0, Small writes one 219-token run of Telugu (the per-window cap) for every clip; whisper.cpp flags it as failed and retries at 0.2, 0.4 … 1.0. Six decodes of up to 220 tokens is the fixed ~7.5 s; the kept 1.0 attempt is 60 % Latin letters at a mean log probability of −3.5. |
| The fallback still matters for Hindi | Without it, Hindi WER rose from 69 % to 81 % on a 10 % sample, all from loops it no longer broke. |
| Start-of-transcript no-speech probability separates noise from speech | Noise and tones: 0.77–0.96 (both models). English benchmark speech (4 accents, noisy set): at most 0.21. Hindi speech: at most 0.42 in a first window. Telugu speech: median 0.44, up to 0.83, because Small barely hears Telugu (#137). Cost: 0.18 s per 30-second window on Small. |
| Suppressing non-speech tokens is free | Two of three English noise hallucinations stop; English benchmark WER is identical (15.1 % `small-en`, 16.3 % `small`); Hindi within noise. |
| Beam search is not worth it | 5 beams: clean Hindi WER 66 → 60 %, but Hindi p95 latency 6 → 9.6 s and loops of up to 15 copies came back. |

The sample comparisons above ran with one candidate per fallback retry, not whisper.cpp's
default of five; the final settings and the before/after numbers use five.

## Decision

`WhisperDecoding` holds the settings `WhisperCppModel` passes to whisper.cpp; its defaults
are the shipped policy.

- **No-speech gate** (`NoSpeechGate`, `WhisperModel.noSpeechProbabilities`). Before
  decoding, the engine computes the start-of-transcript no-speech probability of every
  30-second window. If every window is at least **0.75**, the recording ends as
  `recognition.no-speech` without decoding. If every window is at least **0.6** and the
  decoded text's token-weighted mean log probability is below **−1** (or there is none),
  the text is dropped as no speech. One window with speech keeps the whole recording.
- **Suppress non-speech tokens** (`suppress_nst`) on.
- **Shorter fallback ladder**: temperature increment **0.4** (retries at 0.4 and 0.8)
  instead of 0.2 (five retries up to 1.0). Greedy decoding with whisper.cpp's five
  candidates per retry (`best_of`); one candidate made Hindi WER about 2 points worse.
- **Loop guard** (`RepetitionLoop`, Domain, pure): after decoding, a phrase of up to 8
  words repeated **4 or more** times in a row is cut to its first copy, compared without
  case or surrounding punctuation. Three copies stay: people say "no, no, no". The engine
  logs how many copies it cut, never the text.

## Alternatives considered

| Option | Why not |
|---|---|
| Turn the temperature fallback off | Telugu falls to 1.5 s, but Hindi WER rises 12 points from unbroken loops. |
| Beam search (5) | Better clean Hindi, but p95 latency +50 % and longer loops. |
| whisper.cpp's built-in VAD | Needs another model file (Silero), with its own download, pinning, and consent. Whisper's own probability, read correctly, already separates the edge cases with a wide margin. |
| An energy or spectral gate | Quiet noise (−40 dBFS) is louder than quiet speech; it would refuse real dictation. |
| The no-speech probability alone at 0.6 | Fits the corpus, but OpenAI pairs it with the log probability because speech over music or far from the microphone can score high. The 0.75 skip is the only place the probability acts alone, above every speech window measured except Telugu (which Small cannot transcribe). |
| Patch whisper.cpp to read the probability at start-of-transcript | A fork of a pinned binary dependency. Worth reporting upstream; not done yet. |

## Consequences

- Every Whisper recognition costs one encoder pass per 30-second window more (0.18 s on
  Small, Mac16,1); a recording with no speech skips decoding and ends sooner (Hindi and
  Telugu noise: 4–9 s → 0.2 s).
- Telugu speech that Small hears as no speech now ends as "No speech was detected"
  instead of random text. Telugu with Whisper Small is marked not reliable (#137).
- A real loop of 4+ copies loses the copies after the first. The scorer's loop rule
  (`TranscriptScore`, 3+ copies of up to 4 words) is stricter, so a three-copy loop still
  counts in reports.
- `WhisperDecodingDiagnosticsTests` and the `LEMMETYPE_DIAGNOSTICS_*` variables
  (docs/testing/evaluation-harness.md) re-measure any change to these settings.
