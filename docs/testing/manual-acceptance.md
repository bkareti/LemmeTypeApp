# Manual acceptance checklist

Steps that cannot be automated on CI (clean installs, real permission prompts,
real hardware, other applications). Each story adds its steps here. Record
results in the PR description as `MA-N: pass/fail — notes`.

## Running the full checklist (release candidates and Epic sign-off)

1. Use a **team-signed** build (`Config/Signing.local.xcconfig`) so macOS keeps
   permission grants, on a Mac at the minimum supported macOS (26.0) if possible.
2. Start from a clean install:
   ```bash
   tccutil reset Microphone com.lemmetype.LemmeType
   tccutil reset Accessibility com.lemmetype.LemmeType
   defaults delete com.lemmetype.LemmeType
   rm -rf "$TMPDIR/LemmeType"
   ```
3. Run MA-1 to MA-44 in order: clean-install onboarding (MA-6) must come
   before anything that assumes permissions; real-microphone checks are MA-11
   to MA-13 and MA-14 to MA-17.
4. Finish with `make privacy-check` and confirm `$TMPDIR/LemmeType/Sessions` is empty.

Results template:

```markdown
Build: <version (build)> · macOS <version> · <Mac model> · tester <initials> · <date>
| Check | Result | Notes |
|---|---|---|
| MA-1 | pass | |
```

## E1-S1 — Project scaffold

**MA-1 Clean checkout builds and tests**
1. `git clone` the repository into a new directory.
2. `make bootstrap` — reports Xcode 27.0 and finds `xcodegen` and `swiftlint`.
3. `make build` — `** BUILD SUCCEEDED **` with no manual Xcode configuration.
4. `make test` — `** TEST SUCCEEDED **`; package, `LemmeTypeTests`, and
   `LemmeTypeUITests` all report results.

**MA-2 Live services launch**
1. `make run`.
2. The status window shows the version, Microphone and Accessibility status
   read from this Mac, and a non-zero input-device count on a Mac with a microphone.
3. No permission prompt appears (status is read, never requested).

## E1-S2 — Menu-bar lifecycle

**MA-3 Status menu actions** (XCUITest cannot click status-menu items)
1. `make run`. A waveform icon appears in the menu bar; no Dock icon, no window.
2. Choose **Settings…** — the settings window appears in front.
3. Choose **Settings…** again — the same window comes forward; no second window.
4. Close the window, choose **Settings…** — it reopens.
5. Choose **About LemmeType** — the standard About panel shows the version.
6. **Start Test Recording** is disabled.
7. Choose **Quit LemmeType** — the icon disappears and the process exits.

**MA-4 Single instance**
1. With LemmeType running, run `open -n build/DerivedData/Build/Products/Debug/LemmeType.app`.
2. Only one menu-bar icon remains; the settings window of the running copy comes forward.
3. `pgrep -f LemmeType.app/Contents/MacOS/LemmeType` lists one process.

**MA-5 Launch at Login** (use a build copied to /Applications)
1. Turn on **Launch at Login** in Settings › General.
2. If macOS asks for approval, the pane says so and **Open Login Items Settings…** opens the right pane.
3. Quit and relaunch LemmeType — the toggle matches System Settings › Login Items.
4. Log out and back in — LemmeType is in the menu bar.
5. Turn it off, relaunch — the toggle is off and the login item is gone.

## E1-S3 — Permission onboarding

Use a team-signed build so macOS keeps grants across rebuilds. Reset state
first: `tccutil reset Microphone com.lemmetype.LemmeType`,
`tccutil reset Accessibility com.lemmetype.LemmeType`, and
`defaults delete com.lemmetype.LemmeType hasCompletedOnboarding`.

**MA-6 Clean-install onboarding**
1. Launch. The onboarding window opens on Welcome; no system prompt is visible.
2. Continue to Microphone. No prompt until **Allow Microphone Access…** is pressed.
3. Allow in the system prompt — the status changes to Granted without relaunching.
4. Continue to Accessibility, press **Allow Accessibility Access…** — the
   system alert appears; open System Settings and enable LemmeType.
5. Return to the onboarding window — Accessibility shows Granted within ~1 s.
6. Continue, then **Done**. No Screen Recording or Input Monitoring prompt appeared at any point.

**MA-7 Denied microphone**
1. Reset Microphone, run onboarding, choose **Don't Allow** in the prompt.
2. Status shows Denied with guidance; the button reads **Open System Settings…**
   and opens Privacy & Security › Microphone. Pressing it again never shows the prompt.

**MA-8 Accessibility revoked while running**
1. With everything granted, open Settings › Permissions.
2. In System Settings, turn LemmeType off under Accessibility.
3. Switch back to LemmeType — Accessibility shows Not granted and Text insertion shows Unavailable.
4. The status menu shows **Finish Setup…**.

## E1-S4 — Global shortcut

**MA-9 Activation from another app without stealing focus**
1. Open TextEdit with a document and click in the text. Open LemmeType Settings › Shortcut
   in a second window position so it is visible, then click back into TextEdit.
2. Press ⌥Space briefly (Push to Talk). TextEdit keeps focus (its caret still blinks,
   its title bar stays active) and the Shortcut pane's "Try it" shows "Stopped".
3. Switch the mode to Toggle, click into TextEdit, press ⌥Space — "Started in TextEdit";
   press ⌥Space again — "Stopped". No characters were typed into TextEdit.
4. Press ⌥Space, then Esc — "Cancelled"; press Esc again — TextEdit receives it normally.

**MA-10 Conflicting shortcut**
1. In another app that can register global shortcuts (e.g. Raycast or Alfred), bind ⌥Space.
2. Relaunch LemmeType. The menu shows "Shortcut Unavailable — Choose Another…", which
   opens the Shortcut pane with an error; choosing another shortcut clears it.

## E1-S5 — Audio capture

Requires Microphone permission (team-signed build).

**MA-11 Real microphone and device selection**
1. Settings › Audio lists System Default plus every connected input.
2. **Test Microphone** — the meter moves when you speak and falls when silent. Stop the test.
3. `ls -la $TMPDIR/LemmeType/Sessions` is empty (the test kept nothing).
4. Choose a USB or Bluetooth input, test again — the meter follows that device.

**MA-12 Device loss and fallback**
1. Start a test on a USB/Bluetooth input, then unplug or disconnect it — the test
   stops with "The microphone was disconnected…" and the Sessions folder is empty.
2. With that device still disconnected, the pane says the selected microphone isn't
   connected; **Test Microphone** works and reports it is using the system default.

**MA-13 Sleep**
1. Start a test and put the Mac to sleep (Apple menu › Sleep). After waking, the
   test has stopped with "Recording was interrupted" and no recording remains.

## E1-S6 — Recorder and overlay

**MA-14 Overlay never takes focus** (team-signed build, permissions granted)
1. Click into a TextEdit document so the caret blinks. Press the dictation shortcut.
2. The overlay appears at the top of the screen; TextEdit's title bar stays active
   and the caret keeps blinking. Typing still goes into TextEdit.
3. Stop (release or press again) — the overlay shows Done and disappears.
4. Repeat in a full-screen app and on a second Space — the overlay appears there too.

**MA-15 Cancel and failure from the overlay**
1. Start recording, click **Cancel** on the overlay — Cancelled; TextEdit keeps focus;
   `$TMPDIR/LemmeType/Sessions` is empty.
2. Revoke Microphone in System Settings, press the shortcut — "Couldn't record" with
   **Open Permissions**, which opens Settings › Permissions.

**MA-16 Reduce Motion and VoiceOver**
1. Turn on Reduce Motion — states remain distinguishable by text, symbol, and colour; no pulsing.
2. Turn on VoiceOver — it announces "Recording started", "Recording stopped",
   "Recording cancelled", and failures, and does not read levels while recording.

**MA-17 Quit and sleep while recording**
1. Start recording, choose **Quit LemmeType** — the app exits, the microphone
   indicator in the menu bar turns off, and no session file remains.
2. Start recording, sleep the Mac, wake it — the overlay shows the interruption; no file remains.

## E1-S7 — Diagnostics

**MA-18 Export is explicit and content-safe**
1. Dictate a few times (including one cancel), then open Settings › Diagnostics.
2. **Preview Report…** shows JSON with app version, macOS version, Mac model,
   permission states, and events; nothing is saved yet.
3. Search the preview for your microphone's name, the app you dictated into, and any
   word you spoke — none appear.
4. **Save…** writes the same JSON to the chosen file. With Little Snitch or
   `nettop -p LemmeType` running, no network connection is made at any point.

## E2-S2 — Apple Speech engine

**MA-19 On-device recognition with no network** (team-signed build)
1. In System Settings › Keyboard › Dictation, make sure the English (US)
   dictation language is downloaded.
2. Turn Wi-Fi off and unplug Ethernet. Start a network monitor (Little Snitch,
   LuLu, or `sudo nettop -p LemmeType`).
3. With Apple Speech selected, dictate a sentence into TextEdit.
4. A transcript is produced and the monitor shows **no connection attempt** by LemmeType.

**MA-20 Speech Recognition authorization**
1. `tccutil reset SpeechRecognition com.lemmetype.LemmeType`.
2. Dictate with Apple Speech selected. The overlay explains that Speech
   Recognition is needed and offers **Allow Speech Recognition**; the recording
   is kept.
3. Allow it in the system prompt and choose **Retry**: the same recording is
   transcribed. Repeat with **Don’t Allow**: the overlay offers System Settings
   and Discard, and Discard deletes the recording (`$TMPDIR/LemmeType/Sessions` empty).

**MA-21 On-device recognition unavailable**
1. Remove the English dictation language download (or pick a Mac/locale
   without on-device support).
2. Apple Speech shows *Not available on this Mac* and is never used; no network
   recognition happens (monitor as in MA-19).

## E2-S4 — Model downloads

**MA-22 Download confirmation, progress, and verification**
1. Settings › Dictation › Whisper Base (English) › **Download…**. The
   confirmation shows download size, storage use, licence, and free space.
2. Confirm. Progress advances; **Pause** stops it; **Resume** continues from
   the same point (not from zero).
3. Quit during download and relaunch: the model shows *Paused* and resumes or
   restarts; it is never shown as installed before verification.
4. When finished, `~/Library/Application Support/LemmeType/Models/whisper-base-en/`
   contains the model and `.verified`; `Models/Staging` is empty.

**MA-23 Insufficient storage and removal**
1. Fill the disk (or use a small disk image as the home volume) so less than
   the shown requirement is free. **Download…** explains the required space and
   does not start.
2. With the model installed, **Remove**: the folder is deleted, Whisper shows
   *Download required*, and dictation falls back to Apple Speech (Automatic) or
   asks before changing engine.

## E2-S3 — Whisper model

**MA-24 Offline Whisper transcription and unload**
1. Install the Whisper model (MA-22), select **Whisper Base (English)**, and
   turn off networking (as MA-19).
2. Dictate an English sentence into TextEdit: a transcript is produced; the
   network monitor shows no connection.
3. Start a long dictation and cancel during *Processing…*: processing stops
   within a second and Activity Monitor shows LemmeType's memory dropping back
   after **Settings › Dictation › Unload model** (or quitting).
4. On an Intel Mac or a Mac with less than 8 GB memory, Whisper is not offered
   and the reason is shown.
5. About LemmeType › Credits lists whisper.cpp and OpenAI Whisper (MIT).

**MA-25 Benchmark run** (minimum and recommended hardware)
1. `scripts/run-recognition-benchmark.sh` with the model installed.
2. `scripts/run-e2e-benchmark.sh` (Apple Speech and Whisper, inside the app,
   under the network monitor; allow Speech Recognition on first run).
3. Copy the summaries from `build/benchmarks/*.md` into the *Recorded runs*
   table of `docs/testing/performance-thresholds.md` with the Mac model and
   date. The check script must pass.

## E2-S5 — Dictation sessions

**MA-26 One recording, one result, clean-up**
1. Dictate into TextEdit. The overlay shows *Transcribing…* then *Done* with
   how the text was delivered; `$TMPDIR/LemmeType/Sessions` is empty afterwards.
2. Dictate a long sentence and press **Cancel** while *Transcribing…*: nothing
   is delivered, the overlay shows *Cancelled*, and the Sessions folder is empty.
3. Select Whisper without installing it and dictate: the overlay explains the
   engine isn't ready and offers **Use Apple Speech**, **Choose Engine…**,
   **Save Audio…**, **Discard**. **Use Apple Speech** transcribes the same
   recording. Repeat and choose **Discard**: the recording is deleted.
4. Repeat step 3, press the shortcut again instead of choosing: the old
   recording is deleted and a new session starts.
5. Repeat step 3 and quit LemmeType: the Sessions folder is empty.

## E2-S6 — Writing modes

**MA-27 Exact Dictation and Clean Writing**
1. With default settings, open the status menu: it shows *Writing Mode: Exact
   Dictation*. Start a recording: the overlay shows *Exact Dictation* under
   *Recording*.
2. Dictate "um can you send me the the slides comma thanks": the delivered
   text keeps every word as recognised (no fillers or repeats removed).
3. Quit LemmeType, run `defaults write com.lemmetype.LemmeType writingMode
   clean`, and relaunch (the Settings control arrives in E2-S9). The menu and
   overlay show *Clean Writing*.
4. Dictate the same sentence: the result is "Can you send me the slides,
   thanks." Dictate "meet on Tuesday sorry Wednesday": it becomes "Meet on
   Wednesday." Dictate "send it to ana@example.com by 5": the address and
   number are delivered exactly as recognised.
5. Run `defaults delete com.lemmetype.LemmeType writingMode` to restore Exact.
6. Start a Clean Writing dictation and, while still recording, switch the
   mode to Exact (from E2-S9, in the status menu's *Writing Mode* submenu).
   That session still uses Clean Writing; the next one uses Exact. The
   overlay shows *<mode> · On this Mac* while recording and processing.

## E2-S7 — Accessibility insertion

**MA-28 Insert, replace selection, target changed, password fields**
Record results per app in `docs/testing/insertion-matrix.md`.
1. TextEdit: put the caret mid-sentence and dictate. The text appears once at
   the caret; the overlay shows *Text inserted.*
2. Select a word and dictate: the selection is replaced.
3. Start dictating in TextEdit, click into a Notes note before processing
   finishes. Nothing is typed into Notes; the overlay offers **Copy Text**,
   **Retry Insert**, **Discard**. Click back into the TextEdit field and choose
   **Retry Insert**: the text is inserted once.
4. Safari › any sign-in page: focus the password field and dictate. Nothing is
   typed; the overlay explains LemmeType never types into password fields.
5. Revoke Accessibility (`tccutil reset Accessibility com.lemmetype.LemmeType`)
   and dictate: the overlay offers **Copy Text** and **Open Permissions**.

## E2-S8 — Clipboard fallback

**MA-29 Paste and restore**
1. Copy a mix to the clipboard: rich text from TextEdit, then (separately) an
   image from Preview and a file in Finder — run the steps once for each.
2. Dictate into Slack's message composer (Electron ignores Accessibility
   writes). The text is pasted once; the overlay says *Text pasted.*;
   ⌘V in TextEdit afterwards pastes your original clipboard item, unchanged.
3. Settings › Dictation › When text can't be inserted: **Copy only**. Dictate
   into Slack: nothing is pasted, the overlay says *Text copied. Press ⌘V to
   paste it.*
4. Choose **Ask me (Copy Text)** (fallback off). Dictate into Slack: the
   overlay offers **Copy Text** and **Discard**.
5. With a clipboard manager (Maccy, Raycast) running, repeat step 2: the
   dictated text does not appear in its history (transient marker).

## E2-S9 — Engine and mode selection

**MA-30 Choosing engines and modes**
1. Settings › Dictation lists Automatic, Apple Speech, and Whisper. Each row
   shows its status (*Ready*, *Download required*, *Needs Speech Recognition
   access*, or *Not available on this Mac*), *On this Mac*, its languages, and
   what it needs installed. Automatic explains which engine it uses.
2. The status menu shows *Writing Mode: …* and *Engine: Automatic (Apple Speech) ·
   On this Mac*. Switch the writing mode from the menu; Settings follows.
3. Select Whisper without installing the model: the pane explains it isn't
   ready; dictating asks before using Apple Speech. Turn on *use another
   on-device engine without asking* and dictate again: Apple Speech is used
   without a prompt.
4. Start a long dictation, switch the engine in Settings during *Transcribing…*:
   the current session finishes with the engine it started with.
5. Revoke Speech Recognition and choose Apple Speech: the pane shows *Needs
   Speech Recognition access* with **Allow Speech Recognition**.

## E2-S10 — End-to-end acceptance

**MA-31 Clean user account, offline, every supported app**
1. Create a new macOS user account, log in, and install the team-signed
   build in /Applications. Complete onboarding (MA-6).
2. Download the Whisper model (MA-22), then turn off Wi-Fi and Ethernet.
3. Start `scripts/check-network-silence.sh --attach 600` (from the
   developer account with `sudo -u <user>` or a second terminal) and keep a
   network monitor (Little Snitch, LuLu, or `sudo nettop -p LemmeType`) open.
4. With **Automatic**, then **Apple Speech**, then **Whisper**, and in both
   **Exact** and **Clean** mode, dictate one sentence into each app of
   `docs/testing/insertion-matrix.md`; fill in its result columns. Include a
   password field and a focus change during processing.
5. Expected: text arrives once in every app (Accessibility or paste, as the
   matrix says), the clipboard is restored, no app loses data, and both
   monitors show no connection.
6. Afterwards `$TMPDIR/LemmeType/Sessions` is empty and Settings › Diagnostics
   › Copy shows session durations but no dictated words.

## E3-S1/S2/S6 — Cursor context

**MA-32 Context is read only on a shortcut press, and only when allowed**
1. Fresh install: Settings › Context shows *Use text near the cursor* **off**
   and *Edit selected text by voice* **on** with ⌥⇧Space.
2. In TextEdit type "We met on Monday and", dictate "then we left" (Clean):
   the result is Epic 2 behaviour ("andThen we left.") and the overlay shows
   no context line.
3. Turn the switch on and repeat: "We met on Monday and then we left." and the
   overlay shows *Using text near the cursor*; VoiceOver says
   "Recording started. Using text near the cursor".
4. Put the caret mid-sentence before "world" in "Say world", dictate "hello":
   "Say hello world" (no period, one space each side).
5. Settings › Diagnostics › Copy: `activation.start` has `context: captured`
   and no words from the document.

**MA-33 Exclusions, sensitive apps, and password fields**
1. Settings › Context › *Add App…* › Notes. Dictate in Notes: no context line
   (or *Context off for this app*), and text is still inserted. Remove Notes:
   context is used again from the next dictation.
2. In 1Password or Keychain Access (if installed) and in any password field
   (Safari login form), press both shortcuts: nothing is read, nothing is typed,
   voice editing explains why, and nothing is recorded for the voice edit.

## E3-S4/S5 — Voice editing

**MA-34 Rewriting the selection on device**
1. On a Mac with Apple Intelligence on, Settings › Context shows *The on-device
   model is ready.* With it off (or on an ineligible Mac) it explains how to
   enable it, and pressing ⌥⇧Space shows the same reason without recording.
2. In TextEdit select a long sentence, hold ⌥⇧Space, say "make this shorter",
   release. The overlay shows *Editing selection · On this Mac* →
   *Rewriting on this Mac…* → *Done*; only the selection is replaced.
3. Repeat with "fix the grammar", "turn this into a bulleted list", and
   "translate to Spanish". ⌘Z in the app restores the original; record per app
   in the insertion matrix.
4. Start an edit, then click elsewhere to change the selection before it
   finishes: nothing is replaced; the overlay offers **Copy Text**.
5. With nothing selected, press ⌥⇧Space: *Select the text you want to change*,
   no recording indicator.

**MA-35 Network silence during rewriting**
1. Start `scripts/check-network-silence.sh --attach 300` and
   `sudo nettop -p LemmeType`, turn off Wi-Fi, and run MA-34 step 2 three
   times: every rewrite succeeds and neither monitor shows a connection.
2. Optional developer check: `LEMMETYPE_REAL_REWRITE=1 swift test --package-path
   Packages/LemmeTypeKit --filter FoundationModelsRealRewriteTests` passes
   offline.

**MA-36 Shortcuts and switches**
1. Settings › Context › *Change…*: record ⌃⌥E; the status menu shows *Edit
   Selection: ⌃⌥E*. Recording the dictation shortcut there is refused.
2. While dictating with ⌥Space held, press ⌥⇧Space: nothing changes. Esc
   cancels either kind of session.
3. Turn voice editing off: ⌥⇧Space is free for other apps (no LemmeType
   reaction) and the menu line disappears.

**MA-37 Latency (records the voice-edit threshold run)**
1. On the minimum supported Apple Intelligence Mac, run MA-34 step 2 ten times
   with a 1–3 sentence selection. Settings › Diagnostics › Copy: note the
   `rewriteSeconds` and `processingSeconds` values of `session.delivered`
   events with `purpose: editing`, and record p95 in
   `docs/testing/performance-thresholds.md` › Voice editing.

## E4-S1/S2/S3 — Vocabulary, replacements, and snippets

**MA-38 Personalization with real engines**
1. Quit LemmeType. Create `~/Library/Application Support/LemmeType/Personalization/library.json`
   by exporting from a test build, or add entries in Settings › Personalization
   (E4-S4): vocabulary "LemmeType" (sounds like "lemme type"), replacement
   "my email" → `pat@example.com`, snippet "sign off" → "Best regards,⏎Pat".
2. `ls -l` the file: `-rw-------`; its folder is `drwx------`.
3. In TextEdit, with Apple Speech and then Whisper, dictate "I use lemme type
   every day": both deliver "LemmeType". Dictate "send it to my email": the
   address is inserted. Say "Sign off": the two-line snippet is inserted exactly.
4. Say "please sign off now": no snippet; the sentence is dictated.
5. Replace the file's contents with `{ broken`, relaunch: Settings explains the
   file could not be read; `library-unreadable-*.json` holds the old contents.
6. Settings › Diagnostics › Copy: no vocabulary, phrase, or snippet text appears.

## E4-S4 — Personalization settings

**MA-39 Managing vocabulary, replacements, and snippets**
1. Settings › Dictation: the *Show* menu lists Engine, Models, Vocabulary,
   Replacements, Snippets, and Modes, each with an explanation and "0 of N".
2. Add a word, a replacement, and a two-line snippet; Edit each and Save; the
   rows update. Saving an empty field or a duplicate shows the reason in the
   sheet and nothing is saved.
3. Start a dictation, add a replacement while recording, finish: the new
   replacement is not applied; the next dictation applies it.
4. With VoiceOver on, every row's Edit and Delete buttons are announced with the
   item's name, and a validation error is announced.
5. Quit and relaunch: everything is still there.

## E4-S5/S6/S7 — Dictation modes

**MA-40 Choosing and managing modes**
1. Upgrade from a build with Clean Writing selected: the status menu shows
   *Mode: Clean Writing* and dictation output is unchanged.
2. Status menu › Mode › Message; dictate "see you tomorrow" in TextEdit:
   "See you tomorrow" (no period). The overlay shows *Message · On this Mac*
   and VoiceOver says "Recording started. Message".
3. Settings › Dictation › Modes › Duplicate Message: "Message Copy" appears.
   Edit it: Output *Clipboard only*, *Add a space after the text*. Dictate:
   TextEdit is unchanged, the overlay says the text was copied, and ⌘V pastes
   it with a trailing space.
4. Make the copy the default, then Delete it: the confirmation says Clean
   Writing becomes the default; after deleting, the menu shows Clean Writing.

**MA-41 Modes by application**
1. Settings › Dictation › Modes › Add App… › Slack (or Messages) and pick
   Message. Dictate in Slack: no final period, the overlay says
   *Message for this app*. Dictate in TextEdit: the default mode is used.
2. Switch to Slack during a TextEdit recording: the TextEdit mode stays for
   that recording (rules are read only when the shortcut is pressed).
3. Remove the rule: Slack uses the default mode again.
4. Diagnostics › Copy: `dictationMode` is `message`/`custom` and `modeSource`
   is `app-rule`; no app or mode name appears.

## E4-S8 — Export, import, and delete

**MA-42 Personalization data controls**
1. With vocabulary, a replacement, a snippet, a custom mode, and an app rule,
   Settings › Dictation › Vocabulary › *Export…*: the save panel opens; save
   to the Desktop. The file is readable JSON with `"formatVersion" : 1`.
2. *Delete All…* explains what is removed; confirm. Every list is empty, a
   custom default mode becomes Clean Writing, and
   `~/Library/Application Support/LemmeType/Personalization/` holds no
   `library*.json`. Dictation still works.
3. *Import…* the exported file › *Replace Mine*: everything is back and
   behaves as before (MA-38 step 3). *Import…* again › *Add to Mine*: the
   result says 0 added and every item skipped.
4. Import a text file renamed `.json`: "This isn’t a LemmeType personalization
   file." and nothing changes.
5. Diagnostics › Copy: only `personalization.*` events with counts appear.

## E5-S1/S2/S3 — Model catalog, Models pane, verification

**MA-43 Choosing and downloading models**
1. Settings › Dictation › Models lists Whisper Tiny, Base, and Small with tier,
   download size, memory, English, the Apple silicon/8 GB requirement, and the
   fit for this Mac (Small says more memory is recommended below 16 GB).
2. *Download…* Tiny: the confirmation names Hugging Face, the sizes, the
   licence, and the fit. Download; the row shows progress, then *Installed and
   verified*. Disk used and free space update.
3. Whisper model › *Whisper Small* while Small isn't installed: Settings ›
   Dictation › Engine shows Whisper needs a download; dictation with Whisper
   asks to choose another engine instead of silently using Tiny.
4. Remove Tiny: the row returns to *Not downloaded* and the engine state
   updates without reopening Settings.

**MA-44 Integrity and interrupted downloads**
1. With Base installed, quit LemmeType and change one byte of
   `~/Library/Application Support/LemmeType/Models/whisper-base-en/ggml-base.en/ggml-base.en.bin`
   (`printf 'x' | dd of=<file> bs=1 seek=100 conv=notrunc`). Relaunch and
   dictate with Whisper: it is not used; Models shows Base as failed
   verification and offers *Download…*. Diagnostics show `model.integrity-failed`.
2. Start downloading Small, quit with ⌘Q mid-way: quitting waits a moment.
   Relaunch: Small shows *Paused at …*; *Resume* continues from there.
3. Start a download and turn Wi-Fi off for 3 seconds, then on: the download
   continues (automatic retry). Turn Wi-Fi off for a minute: the row shows the
   failure with *Resume*; with Wi-Fi back, *Resume* finishes it.

