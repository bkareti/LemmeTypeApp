# Epic 5 — model management and performance

## Epic issue body

### Objective

Make local speech models easy to understand, safe to download, and efficient on
every supported Apple silicon Mac: choose between models of different size and
accuracy, verify them before use, keep them in memory only while useful, and
adapt to power, heat, memory, and disk limits.

### Business value

A model that is too large drains the battery or memory, one that is too small
mis-hears, and a model that stays loaded forever wastes gigabytes. Clear choices
and automatic, safe resource management let people use the most accurate model
their Mac can comfortably run without thinking about it.

### In scope

- A catalog of Whisper models (Tiny, Base, Small; English) with size, languages,
  memory use, hardware requirements, and fit for this Mac.
- Settings › Models to download, pause, resume, verify, remove, and choose models.
- Integrity verification before a model is loaded, and recovery from
  interrupted downloads.
- Lazy loading, warm-up during recording, and unloading after a configurable
  idle period.
- Automatic, Balanced, Low Power, and Best Accuracy performance profiles.
- Safe handling of memory pressure, thermal pressure, and low disk space.
- Validation, benchmark support, and proposed thresholds.

### Out of scope

- Multilingual models and new dictation languages (later scope).
- Downloadable language models for voice editing (needs its own ADR).
- Importing model files from the user's disk or arbitrary URLs.
- Cloud or Private Cloud Compute processing.
- Automatic background updates of model files.

### Epic acceptance criteria

- All child stories are accepted.
- Downloads show size, language support, and expected hardware requirements.
- Artifacts are verified before use and recover cleanly from interrupted downloads.
- Models load lazily and unload after a configurable idle period.
- Low-power and best-accuracy profiles are available.
- Memory pressure, thermal pressure, and insufficient storage are handled safely.

---

## E5-S1 — Describe models in a catalog with hardware fit

**User story**

As a user, I want to know what each model costs in disk, memory, and speed and
whether it suits my Mac so that I can pick one with confidence.

**Scope**

- Add Whisper Tiny (English) and Whisper Small (English) to `ModelCatalog`,
  pinned by HTTPS URL, size, and SHA-256 like Whisper Base.
- Catalog metadata: speed/accuracy tier, approximate memory in use, languages,
  minimum and recommended memory.
- `ModelFit` for this Mac: recommended, supported, or unsupported with a reason.
- The Whisper engine runs the user's chosen Whisper model, or (Automatic) the
  model the performance profile picks among installed ones.

**Acceptance criteria**

- Every entry has a trusted source, size, SHA-256, licence, languages, memory
  estimate, tier, and hardware requirement (catalog tests).
- Fit is unsupported on Intel or below the minimum memory, supported below the
  recommended memory, and recommended otherwise.
- A chosen model that is not installed makes Whisper "assets missing"; another
  model is never loaded instead.
- An existing Whisper Base installation keeps working without a new download.

**Dependencies:** E2-S3, E2-S4  
**Estimate:** 5 points

---

## E5-S2 — Manage models in a Models settings pane

**User story**

As a user, I want one screen that shows every model, its state, and what it
needs so that I can download, pause, remove, and choose models easily.

**Scope**

- Settings › Models: name, tier, download size, disk space, languages, memory
  use, fit for this Mac, and install state for each model, plus disk used by
  models and free space.
- Actions: Download (with confirmation), Pause, Resume, Remove, and the Whisper
  model choice (Automatic or a specific model).
- The Dictation pane links to Models instead of duplicating model controls.

**Acceptance criteria**

- Every model shows the fields above and its live state, including progress.
- Downloads need confirmation showing download size, disk space, licence, and
  fit; insufficient free space blocks the download and shows both amounts.
- Unsupported models cannot be downloaded and say why.
- Removing a model unloads it first; the pane and engine state update at once.

**Dependencies:** E5-S1  
**Estimate:** 5 points

---

## E5-S3 — Verify models before use and recover interrupted downloads

**User story**

As a user, I want LemmeType to use only intact models and to pick up downloads
where they stopped so that a bad file or a dropped connection never breaks dictation.

**Scope**

- Before an installed model is loaded for the first time in a launch, or after
  its file changed, verify its size and SHA-256 off the main actor; a mismatch
  deletes the active copy and reports `model.digest-mismatch`.
- Cache a successful verification for the launch, keyed by file size and
  modification date.
- Keep download progress when the app quits; retry transient network failures
  automatically before showing the failure with Resume available.

**Acceptance criteria**

- A modified installed file is detected before loading and is never passed to
  the runtime; the model shows as needing a new download.
- An unchanged file is verified at most once per launch.
- Quitting during a download keeps the progress; the next launch shows Paused
  with the received bytes and Resume continues.
- A transient network failure is retried up to 2 times, then the failure is
  shown with Resume available.
- Diagnostics record asset identifiers and outcomes only.

**Dependencies:** E5-S1, E2-S4  
**Estimate:** 5 points

---

## E5-S4 — Load models lazily and unload them when idle

**User story**

As a user, I want models in memory only while I'm dictating so that LemmeType
doesn't hold gigabytes of memory all day.

**Scope**

- No model loads at launch. A model loads on first use, or starts warming up
  when recording starts (when the profile allows) so loading overlaps speech.
- A residency controller unloads every loaded model after the idle period that
  follows the last session; a new session cancels the timer.
- Settings › Models: "Unload models after" 1, 5 (default), 15, or 60 minutes, or Never.

**Acceptance criteria**

- No engine is prepared at launch.
- With warm-up on, starting a recording prepares the engine once and
  recognition does not load it again.
- After the idle period with no session, models are unloaded once; a session
  before then restarts the timer (tested with a test clock).
- Never keeps models loaded until quit or memory pressure.
- Models are never unloaded while a session is recording or processing.

**Dependencies:** E5-S1, E2-S5  
**Estimate:** 5 points

---

## E5-S5 — Offer low-power and best-accuracy performance profiles

**User story**

As a user, I want to choose between saving power and getting the best accuracy
so that LemmeType fits how I use my Mac.

**Scope**

- `PerformanceProfile`: Automatic (default), Balanced, Low Power, Best Accuracy.
- Each profile maps to a plan: Whisper model preference order, inference
  threads, GPU use, warm-up during recording, and the idle-unload limit.
- Automatic uses Low Power while macOS Low Power Mode is on, otherwise Balanced,
  evaluated when each recording starts.
- Settings › Models shows the profile picker, what each profile does, and the
  profile in effect.

**Acceptance criteria**

- Each profile maps to a documented plan (unit tests of the pure mapping).
- Automatic picks Low Power when macOS Low Power Mode is on and Balanced otherwise.
- With the Automatic Whisper model, the profile picks the first installed model
  in its order; with a specific model, the profile changes only threads, GPU,
  warm-up, and idle unload.
- A profile change applies from the next session; a model loaded with
  different GPU settings is reloaded on next use.
- Diagnostics record the profile and plan identifiers only.

**Dependencies:** E5-S1, E5-S4  
**Estimate:** 5 points

---

## E5-S6 — Handle memory pressure, thermal pressure, and low storage

**User story**

As a user, I want LemmeType to back off when my Mac is short on memory, hot, or
nearly full so that dictation never makes my Mac worse.

**Scope**

- A `SystemConditionsMonitoring` protocol with a `Lifecycle` implementation
  using memory-pressure events, thermal-state and Low Power Mode notifications.
- Memory pressure (warning or critical) unloads idle models at once, or right
  after the running session.
- Serious or critical thermal state makes new sessions use the Low Power plan
  and Settings shows why; nominal restores the chosen profile.
- Recording does not start with less than 100 MB free for temporary audio.

**Acceptance criteria**

- On a memory-pressure event, idle models unload; a running recognition
  finishes first and its model is unloaded afterwards.
- On serious or critical thermal state, new sessions use the Low Power plan and
  Settings › Models says performance is reduced to keep the Mac cool.
- With less than 100 MB free, recording does not start and the user sees
  "Not enough disk space to record".
- A download without enough space shows the required and available space.
- Conditions are recorded in diagnostics as identifiers only.

**Dependencies:** E5-S4, E5-S5  
**Estimate:** 5 points

---

## E5-S7 — Validate model management and performance

**User story**

As a product team, we want measured evidence for every model and profile so
that model choices and thresholds are based on real Macs.

**Scope**

- End-to-end tests for lazy loading, idle unload, profile plans, memory
  pressure, a tampered model, and low disk space.
- The recognition benchmark can run each installed model and records load time,
  real-time factor, and resident memory.
- Proposed thresholds and manual acceptance steps.

**Acceptance criteria**

- End-to-end tests cover every scenario in scope.
- The benchmark reports per model load time, real-time factor, and memory.
- Load-time and memory thresholds per model are documented as Proposed.
- The manual checklist covers download/quit/resume, Low Power Mode, thermal
  state, and real memory measurement.

**Dependencies:** E5-S1 through E5-S6  
**Estimate:** 3 points

## Epic 5 story order

1. E5-S1
2. E5-S2 and E5-S3
3. E5-S4
4. E5-S5
5. E5-S6
6. E5-S7
