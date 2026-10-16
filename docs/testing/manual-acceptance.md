# Manual acceptance checklist

Steps that cannot be automated on CI (clean installs, real permission prompts,
real hardware, other applications). Each story adds its steps here. Record
results in the PR description as `MA-N: pass/fail — notes`.

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
