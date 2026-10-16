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
