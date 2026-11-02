# Evaluation harness

The automated QA framework that measures transcription, translation, writing modes,
accuracy, and speed from recorded audio instead of manual dictation. It is built in
phases; this page records what exists and what comes next. **No accuracy numbers are
recorded here until a real run produces them.**

## What exists (Phase 1: harness core)

All of it is in `Packages/LemmeTypeKit/Sources/TestSupport`, Debug-only where it touches
audio, and runs on macOS and iOS.

| Part | What it does |
|---|---|
| `EvaluationRunner` | Runs one corpus case through the production `TranscriptionPipeline` (engine selection, recognition, writing mode, delivery) with only the delivery target replaced. It copies the audio into a work directory in the speech capture format, so corpus files are never deleted. It returns an `EvaluationResult` with metrics only, never text. `reviewsEveryResult` gives the iPhone and iPad flow. |
| `FileAudioSource` | An `AudioSource` that plays a clip instead of a microphone, so corpus speech goes through the real `AudioCaptureService` (resampling, level meter, session file). The test decides how much plays and when an interruption or device loss happens. |
| `AudioClip` | Mono audio in memory: load (any format, mixed down to mono), write (CAF or WAVE), and deterministic edge cases: silence, tone, seeded white noise, noise at a chosen SNR, clipping, padding, cutting short, and repeating. |
| `TranscriptNormalizer` | The one normalization every metric uses: NFC, zero-width characters removed, lower case, punctuation (including the danda) as a word break, vowel signs and other combining marks kept. |
| `EditAlignment` | Levenshtein edits split into substitutions, deletions, and insertions. |
| `WordErrorRate`, `CharacterErrorRate` | WER over words. CER over Unicode scalars of the normalized text, spaces included. CER is the fairer measure for Telugu, Kannada, Tamil, and Hindi. |
| `TranscriptScore` | WER, CER, insertion rate, and two hallucination flags: text from audio without speech, and a repetition loop (the same phrase three or more times in a row, more often than the reference says it). |

`DictationBenchmark` (macOS) now runs its synthesized corpus through `EvaluationRunner`.
Its report format is unchanged.

Tests: `TranscriptMetricsTests` (DomainTests), `FileAudioSourceTests` (AudioTests),
`EvaluationRunnerTests` (EndToEndTests), `AudioFileReaderTests` (RecognitionTests). The
harness compiles for iOS, but only DomainTests run on the iOS Simulator so far; the
others run on macOS until Phase 5 adds them to the `LemmeTypeiOS` scheme.

### Rules the harness keeps

- Only human references count as ground truth; an AI output is never a reference. The
  Phase 2 manifest enforces this with a review status on every case.
- Results hold metrics and identifiers only. Spoken and reference text stays in memory.
- The runner never deletes or changes corpus audio; working copies are deleted after
  each case.
- Runs are deterministic: noise comes from a seed, and `FileAudioSource` is not timed by a
  real clock.

### Defect found while building it

`AudioFileReader` (Recognition) read each recording with one `AVAudioFile.read`, which
returns whole 1,024-frame blocks only. The last 8–64 ms of every dictation never reached
Whisper or Apple Speech. It now reads until the file ends; `AudioFileReaderTests` fails
on the old code.

## Corpus (Phase 2)

The corpus is described in [corpus/README.md](corpus/README.md): sources and licences,
review statuses, how to fetch and build it, and what it does not cover yet.

| Part | What it does |
|---|---|
| `CorpusManifest` | Decodes `docs/testing/corpus/*.json`, reports every broken rule (`problems()`), and turns a manifest into `CorpusItem`s after checking every recording's SHA-256. `unverified` cases are skipped unless asked for. |
| `CorpusVariant` | Noise, clipping, padding, speed, and repeat, applied at run time to every n-th recording; the reference carries over. |
| `CorpusItem` | One run: a recording, a generated no-speech clip in one language, or a variant. `run(with:workDirectory:)` makes its audio, runs it through `EvaluationRunner`, and deletes what it made. |
| `scripts/corpus.py` | `fetch` (pinned FLEURS revision and checksums; prints the plan unless `--yes`), `build-fleurs` (200 per language, English references joined by sentence id), and `verify`. |

Tests: `CorpusManifestTests` (EndToEndTests) and `scripts/tests/test-corpus.py`
(`make corpus-check`).

## Next phases

| Phase | Scope |
|---|---|
| 3. Reports | Per-case JSON, JUnit XML, a self-contained HTML dashboard, and a baseline comparison. |
| 4. Modes and translation | Exact, Clean, Message, translation (chrF against the human English reference, plus number and negation checks), and style. |
| 5. iOS | XCUITests for permission denial, interruptions, background, time limit, copy, and settings, and an on-device benchmark entry point. |
| 6. CI and gates | A PR smoke job, a nightly full run, a release workflow, and `release-gates.json`. |
| 7. TestFlight readiness | Export settings, encryption declaration, privacy label draft, tester guide. Nothing is uploaded without the maintainer's approval. |
| 8. First real runs | The dashboard and a defect report from actual runs only. |
