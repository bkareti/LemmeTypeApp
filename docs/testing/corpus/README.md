# Evaluation corpus

The cases the [evaluation harness](../evaluation-harness.md) runs. Each manifest here
lists recordings by licence, SHA-256, and human references. **Audio is never committed**:
`scripts/corpus.py fetch` keeps it in `~/Library/Caches/LemmeTypeCorpus` (or
`LEMMETYPE_CORPUS_CACHE`), and `make privacy-check` fails on audio files in the
repository.

## Manifests

| File | What it holds | Status |
|---|---|---|
| `edge-cases.json` | Generated audio without speech: silence, white noise, and tones, each run in English, Hindi, Telugu, Kannada, and Tamil (40 runs). The reference is empty by construction; any text is a hallucination. | Committed |
| `variants.json` | Changes applied to sampled recordings at run time: noise at 20, 10, and 5 dB SNR, clipping, a late start and long pause, 0.9× and 1.1× speed, and a long dictation made of three repeats. The recording's reference carries over (repeated for the long dictation). | Committed |
| `fleurs.json` | 200 read-speech recordings per language from the FLEURS test split, with English references for translation. Written by `scripts/corpus.py build-fleurs`. | **Hindi and Telugu** (the priority languages). English, Kannada, and Tamil are added by rebuilding with all five; selection is deterministic per language, so the Hindi and Telugu cases do not change. |

## Sources and licences

| Source | Licence | Pinned to | Used for |
|---|---|---|---|
| [FLEURS](https://huggingface.co/datasets/google/fleurs) (Conneau et al. 2022, arXiv:2205.12446) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | revision `70bb2e84b976b7e960aa89f1c648e09c59f894dd`; every file's checksum is in `scripts/corpus.py` | English, Hindi, Telugu, Kannada, Tamil transcription; translation to English |

The licence and checksums were read from the Hugging Face API on 2026-11-02. A new source
is added only after its licence is recorded here. Attribution: transcripts are used
unchanged; audio is not redistributed; variants are changes made in memory at run time.

## Ground truth

Every case has a `review` status. Only human references are ground truth.

| `review` | Meaning | Scored against release gates |
|---|---|---|
| `dataset-human` | The dataset's own human transcript (FLEURS: the sentence the speaker read) or human translation | Yes |
| `maintainer-verified` | Checked or corrected by a maintainer | Yes |
| `by-construction` | Generated audio without speech; the reference is empty | Yes |
| `unverified` | Not checked by a person, for example a model's output | Never; skipped by default |

How FLEURS references work: every utterance has a sentence id shared across languages.
The Hindi, Telugu, Kannada, and Tamil sentences are human translations of the same English
sentence, so the English reference for a translation is the English sentence with that id.

Known limits of the references:

- FLEURS writes numbers as digits ("1911") while speakers say words. Cases whose reference
  has a digit are tagged `numbers`, so reports can show them apart until number
  normalization exists (Phase 4).
- FLEURS is read speech. It has no code-switching (Telugu–English, Hindi–English) and no
  dictation-style commands.
- Kannada and Tamil cannot be chosen in the app yet ([language support matrix](../language-support-matrix.md));
  their runs measure the engine only.

## Get the audio

Hindi and Telugu are the priority languages and the ones `fleurs.json` holds today:

```bash
python3 -I scripts/corpus.py fetch --languages hi_in,te_in
```

That prints the files, sizes, and licence, and downloads nothing. Add `--yes` to download:
about 523 MB for Hindi and Telugu (plus the 2 MB of English transcripts that hold the
translation references), or about 1.84 GB for all five languages without `--languages`.
Each file is checked against its pinned checksum; archives are extracted safely and then
deleted, leaving about 620 MB of recordings for Hindi and Telugu. Then:

```bash
python3 -I scripts/corpus.py build-fleurs --languages hi_in,te_in
```

```bash
python3 -I scripts/corpus.py verify docs/testing/corpus/fleurs.json --root ~/Library/Caches/LemmeTypeCorpus/fleurs/70bb2e84b976b7e960aa89f1c648e09c59f894dd
```

The same check from Swift, which also plays one real recording through the pipeline:

```bash
LEMMETYPE_CORPUS_ROOT=~/Library/Caches/LemmeTypeCorpus/fleurs/70bb2e84b976b7e960aa89f1c648e09c59f894dd swift test --package-path Packages/LemmeTypeKit --filter CorpusOnDiskTests
```

What the Hindi and Telugu build holds (2026-11-02):

| Language | FLEURS test recordings | Selected | With English reference | Reference has digits | Audio |
|---|---|---|---|---|---|
| Hindi | 418 | 200 | 200 | 35 | 39.0 min, 3.8–26.8 s each |
| Telugu | 472 | 200 | 200 | 50 | 36.8 min, 4.2–24.3 s each |

With the edge cases (40) and the sampled variants (470), that is 910 runs per engine and
task. Adding English, Kannada, and Tamil brings the recordings to 1,000.

`make corpus-check` runs the script tests and checks the committed manifests without audio.

## Gaps and consented recordings

Not covered by any licensed source yet: code-switched speech, Indian-accented English at
scale, spoken punctuation and commands, and real noisy rooms. These need recordings
made for this project:

1. Each speaker signs a written consent that names the use (evaluating LemmeType), where
   the audio is kept (the maintainer's machine, never the repository), how long, and how
   to withdraw.
2. Speakers read a fixed script, and the script is the reference (`review:
   maintainer-verified` after a listen-through). No personal data in the script.
3. Recordings go in the cache under `consented/`, with a manifest whose source records the
   consent date and licence `LicenseRef-LemmeType-consented`.
