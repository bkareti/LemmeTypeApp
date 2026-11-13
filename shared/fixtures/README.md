# Shared fixtures

Rules that both the Apple apps (Swift, `Packages/LemmeTypeKit`) and the Android app
(Kotlin, `android/`) implement. Each file is checked by a test on **both** sides, so a
change to a rule on one platform fails a test until the other platform agrees
([ADR 0035](../../docs/decisions/0035-android-app.md), E14-S7).

| File | What it holds | Swift test | Kotlin test |
|---|---|---|---|
| `cleanup-corpus.json` | Exact and Clean before/after cases, whitespace, recorded changes, protected tokens | `SharedFixturesTests` (EndToEndTests) | `TextCleanerFixtureTest` (core-writing) |
| `recorder-transitions.json` | Every recorder (state, event) pair and its result; `null` means rejected | `SharedFixturesTests` | `RecorderStateMachineFixtureTest` (core-domain) |
| `model-catalog.json` | Whisper files, sizes, SHA-256 pins, tiers, memory | `SharedFixturesTests` | `ModelCatalogFixtureTest` (core-domain) |
| `recognition-errors.json` | Recognition error identifiers and whether a retry can help | `SharedFixturesTests` | `RecognitionErrorFixtureTest` (core-domain) |

## Rules

- **Synthetic text only.** Never put real dictations, messages, names, or recordings here.
- **The Swift code is the reference today.** Change the Swift rule, update the file, then
  make Kotlin pass. A pull request that edits a file must keep both `make test-unit` and
  `make android-core-test` green.
- Stable names are lowercase with hyphens (`spoken-punctuation`, `needs-attention`).
- Device-specific values (memory fit per phone) are not shared; each platform measures its own.
