# Changelog

All notable changes to WA-HQ-PTT are documented here.

## v2.0.4 - 2026-09-25

- Second iOS compatibility pass after real-device confirmation that v2.0.3 still produced silent PTT playback on iPhone.
- Outgoing voice notes now use a `.opus` filename with `audio/ogg; codecs=opus`.
- Canonical Opus encoding changed to 48 kHz mono, 64 kbps VBR, VOIP application mode, and 20 ms frames.
- Disabled WA-JS waveform/duration precomputation so WhatsApp's native media preparation can populate the outgoing PTT metadata.
- The send path now waits for media acknowledgement before reporting success.
- Added an Ogg/Opus signature check (`OggS` + `OpusHead`) before the media is passed to WhatsApp.

## v2.0.3 - 2026-09-25

- Fixed a compatibility case where OGG/Opus PTT messages could play correctly on Android but be silent on WhatsApp for iOS.
- Replaced WebM/Opus stream-copy remuxing with a canonical Opus re-encode for outgoing PTT audio.
- Normalized outgoing voice notes to OGG/Opus, 48 kHz, mono, 20 ms frames, with regenerated timestamps starting at zero.
- Kept `audio/ogg; codecs=opus`, `isPtt: true`, waveform support, and the existing HQ recording UI.
- Kept 128 kbps Opus as the default recording/output bitrate for high speech quality.

## v2.0.1 - 2026-08-20

- Added a visible cancel button during HQ recording
- Escape key now cancels the active recording
- Cancelled recordings are discarded immediately
- Cancelled recordings are never converted or sent
- Microphone streams and temporary recording data are cleaned after cancellation

## v2.0.0 - 2026-08-20

- Replaced the separate HQ button with interception of WhatsApp's native microphone button.
- Added clean local microphone capture with optional browser processing requested off.
- Added automatic high-quality AAC/M4A conversion at 48 kHz.
- Added automatic PTT sending through WA-JS.
- Added automatic UI re-hooking when WhatsApp rebuilds the composer DOM.
- Improved duplicate-instance prevention, stream cleanup, and temporary-file cleanup.
- Improved installer, updater, stop command, and uninstaller behavior.
- Pinned and integrity-checked `@wppconnect/wa-js` v4.6.0.
- Added privacy, security, third-party attribution, and public-release safety documentation.
