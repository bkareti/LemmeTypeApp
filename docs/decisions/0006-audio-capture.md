# 0006 — Audio capture

- Status: Accepted
- Date: 2026-10-16
- Story: E1-S5

## Decision

- **Format**: 16 kHz, mono, 32-bit float linear PCM (`AudioCaptureFormat.speech`),
  delivered as `AudioChunk`s and written to one CAF file per session. Accepted
  by Apple Speech and Whisper-class engines without further conversion.
- **Layers**: `AudioSource` (Domain protocol) is the hardware edge;
  `AVAudioEngineSource` taps the input node, downmixes to mono, and reports
  `AVAudioEngineConfigurationChange` (device change/loss) and system sleep.
  `AudioCaptureService` (actor) checks Microphone permission, resamples with
  `AVAudioConverter` (flushing the filter tail on stop), meters levels, and
  owns start/stop/cancel/failure. Tests drive it with `FakeAudioSource`.
- **Device selection**: `AudioInputSelection` (`systemDefault` or a device UID)
  is persisted. A specific device is selected by translating its UID to a Core
  Audio device and setting `kAudioOutputUnitProperty_CurrentDevice`. If it is
  missing, capture falls back to the system default and says so.
- **Failure**: device loss, configuration change, and sleep stop capture,
  delete the partial recording, and surface a typed `AudioCaptureError` with a
  recovery message. Wake needs no handling because capture already stopped.
- **Storage**: `$TMPDIR/LemmeType/Sessions` (0700), files 0600, deleted on
  cancel and failure, by the consumer after transcription (Epic 2), and at every
  launch. The settings test meter always cancels, so it never keeps audio.
- **Privacy**: samples and levels are never logged. Level meters expose a
  coarse description ("Sound detected") to VoiceOver rather than numbers.

## Consequences

- Any configuration change during capture (including a default-device switch)
  ends the session with "microphone disconnected"; the user starts again.
- Real-microphone behaviour is verified manually (MA-11 to MA-13).
