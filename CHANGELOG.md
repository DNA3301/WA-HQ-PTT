# Changelog

All notable changes to WA-HQ-PTT are documented here.

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
