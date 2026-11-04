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
`EvaluationRunnerTests` (EndToEndTests), `AudioFileReaderTests` (RecognitionTests). All four
suites also run on the iOS Simulator (`make test-ios`) since Phase 5; tests that need the Mac
(the shortcut, insertion into other apps, the socket watch, `say`) are marked `#if os(macOS)`.

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

## Modes, translation, and style (Phase 4)

| Part | What it does |
|---|---|
| `EvaluationRunner(mode:)` | Runs any `DictationMode`: Exact, Clean, Message, or a mode with a style. A style mode needs a `rewriter`; without one the pipeline offers the original, as the app does. |
| `NumberNormalizer` | Digits of any script to ASCII, thousands separators dropped, English number words to digits ("nineteen eleven" → 1911). Every score also carries `numberNormalizedWords`, so reports show WER with and without it. Hindi, Telugu, Kannada, and Tamil number words are **not** converted. |
| `CharacterNGramStatistics` | chrF (character 1–6-grams, β = 2, whitespace removed), pooled across runs. Defined in the type's documentation; not checked against sacreBLEU. |
| `TranslationScore` | For translation runs: chrF against the human English reference and `PreservationChecker` (numbers, dates, names, negation, commitments, links) after number normalization. A changed number or negation is a **problem** (a JUnit failure); the others are reported as rates. |
| `StyleResult` | For style modes: whether the rewrite applied (and the notice when not), facts it changed, whether bullets or plain text were followed, and whether a concise rewrite was shorter. Style runs score accuracy on the text **before** the rewrite. |

What the rules cannot judge, and stays with people:

- Translation meaning beyond numbers, negation, names, dates, commitments, and links: the
  human review rubric in [language-support-matrix.md](language-support-matrix.md).
- Tone ("professional", "friendly", "casual") and the shape of message and email formats:
  [style-rewriting.md](style-rewriting.md).

The opt-in real run takes `LEMMETYPE_EVALUATION_MODE` (`exact`, `clean`, `message`) and
`LEMMETYPE_EVALUATION_STYLE` (`tone-format-length`, such as `professional-email-concise`,
which needs Apple Intelligence). Each mode or style is its own report; recognition runs
again for each, so run Exact and Message on a language subset when time matters.

Report schema 2 adds `mode` and `style` to the report and `numberNormalizedWords`,
`translation`, and `style` to each run. `scripts/evaluation-report.py` reads schema 2 only;
reports are keyed by label, task, and mode. The three fixtures in `scripts/tests/fixtures/`
are made by `make-evaluation-fixtures.py` and are test data, not measurements.

## iPhone and iPad (Phase 5)

### UI tests on the Simulator

`make test-ui-ios` runs `LemmeTypeiOSUITests` against fakes (`-LemmeTypeUITesting`). A test
picks a scenario with launch arguments, read by `IOSComposition.UITestScenario` (Debug only):

| Argument | Scenario |
|---|---|
| `-LemmeTypeMicrophone notRequested\|denied\|restricted` | The microphone permission at launch (default granted) |
| `-LemmeTypeMicrophoneAnswer denied` | What the system prompt resolves to |
| `-LemmeTypeInterruptAfter <seconds>` | The fake microphone reports an interruption (a call, Siri, an alarm) |
| `-LemmeTypeRecordingLimit <seconds>` | A shorter recording limit than five minutes |
| `-LemmeTypeRecognition no-speech` | The engine finds no speech |
| `-LemmeTypeLaunchRequest` | A shortcut left a launch request, as the App Intent does |

| Test | Checks |
|---|---|
| `QuickDictationUITests` | Record, review, copy; cancel; discard; Settings sections |
| `RecordingEndingsUITests` | The microphone explanation (Continue only, Guideline 5.1.1), a denial at the prompt and at launch (Open Settings), an interruption (Try Again, nothing to copy), the time limit (the text is still reviewed), leaving the app (the dictation is kept), no speech, Dictate Again, and a shortcut start |

Writing these found a gap against E8-S4: after the explanation, denying the system prompt
left the screen at Start Dictating with no message. `QuickDictationModel.continueAfterExplanation`
now goes through the recorder either way, so a denial shows why and offers Open Settings
(`denyingAtTheSystemPromptSaysWhyAndOffersSettings`).

Not covered by the Simulator, and kept in the device checklist: real calls, Siri, alarms, and
route changes (MA-69), a five-minute recording, the app-switcher snapshot (MA-71), VoiceOver,
and Airplane Mode (MA-70).

### On-device evaluation

`scripts/run-ios-evaluation.sh` (or `make evaluation-ios MODEL=whisper-base`) runs the same
corpus evaluation **inside the Debug iPhone and iPad app**, with the app's own model store,
memory check, and performance plan, and with `reviewsEveryResult` as on the phone:

1. It builds and installs the app on the Simulator (default `iPhone 17`) or on `--device`.
2. It puts the manifests, and the corpus, in `Documents/LemmeTypeEvaluation/`. On the
   Simulator the corpus is a link to this Mac's cache; on a device it is copied (only the
   `--languages` folders when given).
3. It launches the app with `-LemmeTypeEvaluation <model id>` (and `-LemmeTypeEvaluationTask`,
   `Mode`, `Style`, `Languages`, `Label`). `IOSComposition+Evaluation.swift` runs
   `CorpusEvaluation`, writes the report and `status.json`, deletes the copied manifests and
   audio, and quits.
4. It copies the report to `build/evaluation/ios/` and writes the summary, JUnit XML, and
   dashboard to `build/evaluation/ios/report/`.

The model must be installed in the app (Settings › Models), or copied from this Mac with
`--copy-mac-model` (it is verified by SHA-256 when it loads). The report's `hardwareModel` names
the device. There is no socket watch on iOS, so a device run is made in Airplane Mode. A full
FLEURS run on a phone takes hours; start with `--languages te` or `--manifests edge-cases.json`.

Running it on the Simulator found that the app refused every Whisper model there:
`os_proc_available_memory()` has no limit to report on the Simulator and returns 0, so the load
check (E8-S5) always said "not enough memory". `IOSComposition.availableMemory()` now treats it
as unknown on the Simulator only; devices keep the check. With that fixed, loading a model on
the Simulator then crashed in whisper.cpp's Metal code (the Simulator's GPU driver cannot
allocate its shared buffers), so Whisper runs on the CPU there (`gpuRunsWhisper`). Both changes
apply to the Simulator only, so Simulator timings are not device timings. Whisper Small is still refused on an
iPhone by the catalog (it is offered on iPads with 8 GB or more), so use Tiny or Base there.

The device path (`--device`) uses `xcrun devicectl` and the signing set up in Xcode. It has not
been run yet; only the Simulator path has (see the PR).

## Decoding diagnostics

`WhisperDecodingDiagnosticsTests` (RecognitionTests, opt-in, macOS) explains *why* a run
scored as it did. It runs corpus cases through the real pipeline with one or more
`WhisperDecoding` settings and writes one JSON line per run to
`build/evaluation/diagnostics/<model>-<setting>.jsonl`: the run's scores plus what
whisper.cpp did — segments, text tokens, the most tokens in one segment, whisper.cpp's and
the start-of-transcript no-speech probability per window, mean log probability, the share
of letters in the expected script and in Latin, the detected language and the requested
language's probability, the longest run of a repeated phrase, decode time, and the word
and character errors again after folding Hindi spelling variants (nukta, chandrabindu).
Numbers only; the decoded text is held in memory to score it and never written.

```bash
LEMMETYPE_WHISPER_DIAGNOSTICS=1 LEMMETYPE_CORPUS_ROOT=… \
LEMMETYPE_EVALUATION_LANGUAGES=hi,te LEMMETYPE_DIAGNOSTICS_MANIFESTS=fleurs.json \
LEMMETYPE_DIAGNOSTICS_EVERY=10 LEMMETYPE_DIAGNOSTICS_DECODING=shipped,whisper.cpp \
swift test --package-path Packages/LemmeTypeKit --filter WhisperDecodingDiagnosticsTests
```

| Variable | Meaning |
|---|---|
| `LEMMETYPE_DIAGNOSTICS_DECODING` | Settings to compare: `shipped` (default), `whisper.cpp` (the library's defaults), `no-fallback`, `suppress-nst`, `no-fallback-nst`, `nst-inc4`, `nst-best5`, `nst-beam5` |
| `LEMMETYPE_DIAGNOSTICS_MANIFESTS` | `fleurs.json`, `edge-cases.json`, or both (default) |
| `LEMMETYPE_DIAGNOSTICS_EVERY` | Every n-th item only, for a quick sample |
| `LEMMETYPE_DIAGNOSTICS_MATCH` | Only ids containing this text, such as `long-dictation` |
| `LEMMETYPE_DIAGNOSTICS_ENGLISH=1` | Also run the English benchmark (synthesized with `say`) with the same numbers |
| `LEMMETYPE_EVALUATION_MODEL`, `LEMMETYPE_EVALUATION_LANGUAGES` | As for the evaluation |

What it found on 2026-11-03 is in [ADR 0028](../decisions/0028-whisper-decoding-safeguards.md)
(decoding safeguards) and the [language support matrix](language-support-matrix.md)
(Telugu and Hindi with Whisper Small).

## Next phases

| Phase | Scope |
|---|---|
| 6. CI and gates | A PR smoke job, a nightly full run, a release workflow, and `release-gates.json`. |
| 7. TestFlight readiness | Export settings, encryption declaration, privacy label draft, tester guide. Nothing is uploaded without the maintainer's approval. |
| 8. First real runs | The dashboard and a defect report from actual runs only. |
