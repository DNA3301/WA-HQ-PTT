# Changelog

All notable changes to WA-HQ-PTT are documented here.

## v2.0.5 - 2026-09-27

- Promoted the Android + iOS compatible HQ pipeline after successful real-device verification.
- Restored the high-quality profile used by the Android-good build: OGG/Opus, 48 kHz mono, 20 ms frames, 128 kbps default, VBR, `application=audio`, and waveform support.
- Fixed silent PTT playback on WhatsApp for iOS by pinning the WA-JS nightly build from 2026-09-24 (`4.6.1-alpha.0`, commit `744e3d809f046059744f3cee035eed2bc516d6cd`).
- Pinned the validated WA-JS bundle SHA-256 to `624F910B6A360C8B34C8962C82826E5539765F4AC0BA427D351D224DE29BFDEC`.
- Kept the custom HQ microphone overlay/recording path intact; the native WhatsApp low-quality recording path is not used while the helper is attached.
- Confirmed normal PTT playback and speed controls on recipients while preserving HQ quality on Android and audible playback on iPhone.
- Updated installer, updater, README, troubleshooting notes, third-party notices, and GitHub Pages documentation to match the validated runtime.

## v2.0.4 - 2026-09-25 - superseded experimental build

- Experimental second iOS compatibility pass.
- Lowered Opus output to 64 kbps, changed Opus application mode to `voip`, and changed waveform/media-preparation behavior.
- This experiment was rejected after testing because it degraded the HQ path and could allow the normal WhatsApp recorder behavior to reappear.
- Do not use v2.0.4; v2.0.5 restores the validated HQ path and fixes iOS compatibility at the WA-JS media layer instead.

## v2.0.3 - 2026-09-25

- Replaced WebM/Opus stream-copy remuxing with a canonical Opus re-encode for outgoing PTT audio.
- Normalized outgoing voice notes to OGG/Opus, 48 kHz, mono, 20 ms frames, with regenerated timestamps starting at zero.
- Kept `audio/ogg; codecs=opus`, `isPtt: true`, waveform support, and the existing HQ recording UI.
- Kept 128 kbps Opus as the default recording/output bitrate for high speech quality.
- Android playback and quality were good, but the then-pinned WA-JS 4.6.0 path could still result in silent playback on iOS.

## v2.0.1 - 2026-08-20

- Added a visible cancel button during HQ recording.
- Escape key now cancels the active recording.
- Cancelled recordings are discarded immediately.
- Cancelled recordings are never converted or sent.
- Microphone streams and temporary recording data are cleaned after cancellation.

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
