# LemmeType friends beta — guide for testers

Thank you for testing LemmeType. This page is for you: how to install it, what to
try, what is known not to work yet, and how to tell us what you found. It takes
about 10 minutes to get started.

## What LemmeType does

You press a shortcut, speak, and press it again. LemmeType turns your speech into
text **on your Mac** and types it where your cursor was — in Mail, Notes, Slack,
a browser, almost anywhere you can type. This beta understands **English only**.

## What you need

- A Mac with Apple silicon (M1 or later) on macOS 26 or later.
- 8 GB of memory or more (16 GB recommended for the most accurate model).
- About 200 MB free for the speech model.

## Install

You get a file named `LemmeType-<version>.zip` from us.

1. Double-click the zip. Move **LemmeType** to your **Applications** folder.
2. Open LemmeType. This beta is not yet notarized by Apple, so macOS stops the
   first launch and says it cannot verify the app. Click **Done** (not *Move to
   Trash*).
3. Open **System Settings › Privacy & Security**, scroll down, and click **Open
   Anyway** next to the LemmeType message. Confirm with your password or Touch ID.
4. If there is no **Open Anyway** button, open **Terminal** and paste this line,
   then open LemmeType again:

   ```bash
   xattr -dr com.apple.quarantine /Applications/LemmeType.app
   ```

You need to do this again for every new beta version.

## First run

LemmeType lives in the menu bar (look for its icon at the top right). The first
time, it walks you through:

1. **Microphone** — so it can hear you while you dictate. It never listens at
   other times.
2. **Accessibility** — so it can type the text into the app you were using. Turn
   on LemmeType in **System Settings › Privacy & Security › Accessibility**.
   - **After installing a new beta version** macOS may show LemmeType as on but
     not let it type. Turn it off and on again, or remove it with **–** and add it
     again. This happens because test builds are not signed by a registered
     developer yet.
3. **Speech engine** — after setup, open **Settings › Dictation** (menu bar icon ›
   Settings…). Either download the English **Whisper** model (Base is about
   150 MB, from huggingface.co, once, after you confirm), or choose **Apple
   Speech**, which needs no download but asks for Speech Recognition permission.
   Settings shows a green check when dictation is ready.

## Five things to try first

1. **Short dictation.** In Notes, press **⌥ Space** (Option + Space), say
   "Let's meet at three thirty tomorrow at the usual place", press **⌥ Space**
   again. The text appears at your cursor.
2. **Cancel.** Start dictating, then press **Esc**. Nothing is typed.
3. **A long message.** Dictate a paragraph of a minute or more into an email.
4. **Your own words.** Names, places, email addresses, numbers and dates,
   technical terms from your work. Add the ones it gets wrong in **Settings ›
   Dictation › Vocabulary** and try again.
5. **Modes.** Try **Exact** (your words as spoken) and **Clean** (removes "um" and
   fixes punctuation) from the menu bar. Exact never rewrites what you said.

If the text cannot be typed into an app, LemmeType keeps it and offers **Copy**,
or pastes it and then puts your previous clipboard back.

## Privacy

- **Your voice and your text stay on your Mac.** Speech is turned into text on
  your Mac. Nothing you say or type is sent anywhere.
- LemmeType connects to the internet for only two things, both when you ask:
  downloading a speech model, and **Check for Updates**.
- The recording is deleted as soon as the text is ready. History is **off** by
  default.
- LemmeType reads a few words around your cursor only if you turn on context
  formatting, and never in password fields.
- **Settings › Privacy › Delete All Local Data** removes everything LemmeType has
  stored.

## Known limits in this beta

- **English only.** Other languages are not offered in this beta.
- **Not notarized.** You need **Open Anyway** for every new version, and may need
  to turn Accessibility off and on again (see above).
- **No automatic updates.** We send you the new zip. **Check for Updates** only
  opens the releases page.
- **Some apps do not accept typed text** (some games, remote desktops, terminal
  apps, password fields). LemmeType then offers Copy instead. Tell us which app.
- **Noise and music.** Very noisy rooms make more mistakes. If there is no speech
  at all, LemmeType says "No speech was detected" and types nothing.
- **Recording always shows** a small recording overlay on screen. It stops
  when you press the shortcut again, press Esc, quit LemmeType, or the Mac sleeps.

## How to report a problem or an idea

1. **Settings › General › Report a Problem…** opens a form with the version and
   your Mac model filled in. You need a free GitHub account.
2. No GitHub account? Choose **Copy Support Info** in the same place and email it
   to the person who gave you the build, with:
   - what you did,
   - what you expected,
   - what happened, and which app you were typing into.
3. **Never send** recordings, your dictated text, or screenshots that show private
   text. We do not need them.

## If something goes badly wrong

- To stop LemmeType: menu bar icon › **Quit LemmeType**.
- To remove it: quit it, drag it from Applications to the Trash, and remove it from
  **Privacy & Security › Accessibility** and **Microphone**. Before that, choose
  **Settings › Privacy › Delete All Local Data** if you want nothing left behind.
- If a beta version is withdrawn, we tell you, and you go back to the previous zip.

## iPhone

The iPhone app is not part of this round. It needs Apple's TestFlight, which we
will use once the developer account is set up.
