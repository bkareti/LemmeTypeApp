# LemmeType privacy policy

Effective 13 November 2026. Applies to LemmeType for iPhone, iPad, and Mac.

**In short: in Local mode your voice and your words are turned into text on your
device and never leave it. Cloud speech is a separate choice you turn on yourself;
it sends the recording to LemmeType's server to be turned into text, and nothing else.**

## Two ways to turn your voice into text

| | Local (the default) | Cloud speech (you turn it on) |
|---|---|---|
| Where your voice is turned into text | On your device | On a speech service, through LemmeType's server |
| Used for | English, and the other languages your device supports | Telugu (and English if a mode asks for it) |
| What leaves your device | Nothing | The recording of that dictation only |
| Needs the internet | No (it works in Airplane Mode) | Yes |

Cloud speech is on iPhone and iPad only. It is off until you turn it on in Settings and agree to the screen that
explains it. A mode uses it only if you chose the Cloud engine for that mode. You can
turn it off at any time.

## What LemmeType does with your voice and text

- **Your voice** is recorded only while the recording is showing on screen. In Local
  mode it is turned into text on your device, by Apple's on-device speech recognition
  or by the Whisper model stored on your device. The recording is deleted as soon as
  the text is ready, or when you discard it.
- **Your text** stays on your device. On iPhone and iPad it is copied only when you
  tap Copy; that copy stays on this device (it does not go to your other devices
  through Universal Clipboard) and is removed after the time you choose in
  Settings. On Mac, the text is typed where your cursor was.
- **Rewriting and tone**, when you use them, run on Apple's on-device model. The
  text is not sent anywhere.
- **History** is off by default. If you turn it on, the text you kept is stored only
  on your device, for the period you choose, and you can delete it at any time.
- **Words you teach LemmeType** (vocabulary, replacements, snippets, modes) are
  stored only on your device.

## Cloud speech: what happens when you use it

Only for a dictation made with the Cloud engine:

1. The recording goes from your device over an encrypted connection to **LemmeType's
   server**, which runs on Google Cloud in Mumbai, India.
2. The server passes it to the **speech service** that turns it into text:
   **Sarvam AI**, in India. So your recording is processed in India, even if
   you are somewhere else.
3. The text comes back to your device. **LemmeType's server does not store the audio
   or the text**, does not write them to its logs, and forgets them as soon as the
   request ends.
4. The speech service handles the recording under its own terms and privacy policy
   (<https://www.sarvam.ai/privacy-policy>).

Only the recording is sent. Your vocabulary, your other modes, your history, and
anything else on your device are not.

**What LemmeType's server does keep.** To check that you have a subscription and to
count your monthly allowance, the server keeps a short record under a code made from
your Apple subscription by a one-way calculation. The code cannot be turned back into
your Apple Account, your name, your email, or your device. The record holds: the app,
the plan, whether the subscription is active or ended, when it ends, and how many
seconds of Cloud speech you used in each billing period. It is deleted 35 days after
the billing period ends. The server's logs hold only a request number, the time it
took, the size, and an error code. Network addresses are used briefly, in memory, to
limit abuse, and are never stored.

**Access tokens.** The app swaps Apple's signed record of your subscription for a
short-lived access token (15 minutes). The token holds that code and the plan, and
nothing else. The app keeps it in memory only.

**Changing the speech service.** LemmeType may change the speech service behind the
server. A change that keeps the same country and terms needs no new agreement. Any
other change is described in the app and in this policy first, and the app asks you to
agree again before the next Cloud dictation.

## Subscription and payment

LemmeType is sold as an auto-renewing monthly subscription with a 7-day free trial,
through the App Store. **Apple takes the payment.** LemmeType never sees your card,
your Apple Account, or your billing details. You manage or cancel the subscription in
your Apple Account settings. Local dictation and Cloud speech are both part of the
one subscription.

The app asks Apple on your device whether you are subscribed. That check works
offline, using records Apple keeps on your device. The app shares only the kind of
subscription (trial, active, ended) and its end date with the LemmeType keyboard on
the same device, through a file only LemmeType's own apps can read. It holds nothing
that identifies you.

## The LemmeType keyboard

The LemmeType keyboard for iPhone and iPad has typing keys. When you dictate with the
Action Button, it shows a recording view and inserts the finished text into the field that
was open when you started. It **does not ask for Full Access**, cannot use the microphone,
and has no internet access. It cannot read what you type in other apps. The text passes
from the app to the keyboard on your device only, for a few seconds, and is then removed.

## When LemmeType uses the internet

Only in these cases:

| When | What is sent | To |
|---|---|---|
| You use Cloud speech | The recording, and an access token that holds a one-way subscription code | LemmeType's server (Google Cloud, Mumbai), then the speech service (Sarvam AI, India) |
| You open Settings › Cloud speech | A request for the current agreement version and for your remaining allowance, with the access token | LemmeType's server |
| You subscribe, restore, or the app checks your subscription | Handled by Apple's StoreKit under Apple's privacy policy | Apple |
| You choose to download a speech model | A request for the model file, like any web request (your IP address and the app's standard network headers). No audio, text, or personal data. | huggingface.co |
| Mac only: you press Check for Updates, or turn on the weekly check | A request for the list of LemmeType releases. No audio, text, or personal data. | github.com |
| You tap Privacy Policy, Terms of Use, or Help and Support | Your browser opens that page. | github.com |

Those services handle requests under their own privacy policies. In Local mode,
recording, recognition, cleanup, rewriting, and history use no internet at all.

## What LemmeType does not do

No advertising, no analytics, no crash-reporting service, no tracking, and no
selling or sharing of data for advertising. There is no LemmeType account or
sign-in: your Apple subscription is the only thing that identifies you to the server,
and only through the one-way code above.

## Permissions

| Permission | Why |
|---|---|
| Microphone | To hear you while you dictate. Never at other times. |
| Speech Recognition | Only if you use Apple's speech recognition; it runs on your device. |
| Accessibility (Mac only) | To type the text into the app you were using. LemmeType reads a few words around your cursor only if you turn on context formatting, and never in password fields. |

You can turn any permission off in Settings; LemmeType keeps working as far as it can
and tells you what is missing.

## Deleting your data

Everything LemmeType keeps on your device is removed by **Delete All Local Data**
(iPhone and iPad: Settings › Privacy and Data; Mac: Settings › Privacy). It also turns
Cloud speech off and removes your agreement to it. Deleting the app removes it too.

Records on LemmeType's server cannot be tied to you by anyone, including us, except
through your own device; they are deleted automatically 35 days after the billing
period ends. Your subscription itself is managed by Apple.

## Children

LemmeType is suitable for all ages. Cloud speech and the subscription are meant for
adults; the Local mode collects no data from anyone, including children.

## Changes

If this policy changes, the new version is published at this address with a new
date. A change that would send more of your data off your device would be described
in the app before it happens, and the app would ask you to agree again.

## Contact

Questions about privacy: open an issue at
<https://github.com/bkareti/LemmeTypeApp/issues>, or see [Help and Support](support.md).
