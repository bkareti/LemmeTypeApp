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

## Reports (Phase 3)

| Part | What it does |
|---|---|
| `CorpusEvaluation` | Runs every item of the chosen manifests through one engine (optionally only some languages), times warm-up and peak memory, and returns an `EvaluationReport`. For translation it skips items that cannot be scored and counts why (`already-english`, `no-english-reference`). |
| `EvaluationReport` | The run as JSON in `build/evaluation/<label>-<task>-<mode>.json`: device, corpus manifests by SHA-256, and each run's metrics. No text. |
| `scripts/evaluation-report.py` | Reads reports and writes `summary.json`, `junit.xml`, and a self-contained `index.html` dashboard (no scripts, no external requests, light and dark). With `--baseline`, compares like for like on the case ids both runs share. |
| `CorpusEvaluationTests` (RecognitionTests) | Opt-in: real Whisper models on the fetched corpus, with a socket watch that fails the run on any network socket. |
| `scripts/run-evaluation.sh` (`make evaluation`) | Verifies the corpus, runs `CorpusEvaluationTests`, writes the reports, and checks no audio was left behind. |

How the numbers are made:

- Word and character error rates are **pooled**: total edits ÷ total reference length
  over the group, not an average of per-run rates. Only human references count.
- A run **fails on its own** (JUnit failure) when speech produced no text, when audio
  without speech produced text, or when the output loops. Accuracy alone never fails a
  run: there are no approved thresholds yet (Phase 6 adds the release gates).
- **Regressions** against a baseline: word or character error rate up by more than the
  tolerance (default 2 points); any rise in no-text, text-from-silence, or loop rates;
  p95 latency up by more than 20 % and 0.2 s; or a case that passed and now fails.
  Groups under 10 runs are not compared. If the corpus changed, only shared case ids count.

Tests: `EvaluationReportTests` (EndToEndTests) and `scripts/tests/test-evaluation-report.py`
(`make evaluation-check`) share `scripts/tests/fixtures/evaluation-report.json`, a
hand-made fixture (label `fixture`): its numbers are test data, not measurements.

```bash
make evaluation
```

That needs a multilingual Whisper model installed in LemmeType. None is installed on the
maintainer's Mac as of 2026-11-02, so **no real report exists yet** (Phase 8).

## Next phases

| Phase | Scope |
|---|---|
| 4. Modes and translation | Exact, Clean, Message, translation (chrF against the human English reference, plus number and negation checks), and style. |
| 5. iOS | XCUITests for permission denial, interruptions, background, time limit, copy, and settings, and an on-device benchmark entry point. |
| 6. CI and gates | A PR smoke job, a nightly full run, a release workflow, and `release-gates.json`. |
| 7. TestFlight readiness | Export settings, encryption declaration, privacy label draft, tester guide. Nothing is uploaded without the maintainer's approval. |
| 8. First real runs | The dashboard and a defect report from actual runs only. |
