# Troubleshooting

Start by completely quitting WhatsApp Desktop, running `AVVIA.cmd`, reopening WhatsApp, and waiting 5–10 seconds.

The local technical log is stored at:

```text
%LOCALAPPDATA%\WA-HQ-PTT\logs\helper.log
```

Logs are intentionally concise. They may contain local file paths and diagnostic details, so review them before sharing publicly.

## The normal WhatsApp recorder starts

The helper has not attached to the current WhatsApp WebView, or a WhatsApp update changed the microphone UI.

1. Completely quit WhatsApp.
2. Run `STOP.cmd`, then `AVVIA.cmd`.
3. Reopen WhatsApp and wait 5–10 seconds.
4. Check `helper.log` for `WA HQ UI injected`.
5. Run `INSTALLA.cmd` again to repair the local installation.

If the log reports that WA-JS did not load or expose `WPP`, the installed WhatsApp build may be temporarily incompatible.

## Cancelling a recording

While the red recording indicator is visible, click the trash/cancel button or press **Escape**. The microphone stream is stopped, captured audio is discarded, and nothing is converted or sent.

If the cancel control is not visible, completely restart WhatsApp and confirm that the installed `ui.js` reports version 2.0.1 in the helper log.

## Microphone permission denied

Allow microphone access for desktop applications in Windows Settings under **Privacy & security > Microphone**, then restart WhatsApp. Also close applications that may be holding the microphone exclusively.

## No active chat

Open a person or group chat before pressing the microphone. WA-HQ-PTT records the destination chat when recording starts.

## FFmpeg missing

Run `INSTALLA.cmd` again. It verifies FFmpeg and attempts to install `Gyan.FFmpeg` with `winget` when needed.

If `winget` is unavailable, install FFmpeg manually, ensure `ffmpeg.exe` is on `PATH`, open a new terminal, and rerun the installer.

## WA-JS missing or failed integrity verification

Run `AGGIORNA-WA-JS.cmd`. Version 4.6.0 is downloaded from pinned CDN URLs and verified against the SHA-256 value recorded in the scripts. A failed hash check is rejected rather than installed.

## Conversion failed

Confirm that `ffmpeg -version` works, then check `helper.log`. Temporary input/output files are removed after the failed attempt.

## Sending failed

Check the network connection and try again in the same chat. If failures began immediately after a WhatsApp update, WA-JS or WhatsApp internals may have changed. Check this repository for a newer release.

## Uninstall

Run `DISINSTALLA.cmd`. It stops the helper, removes its Startup shortcut, restores the registry value saved during the first installation, and removes `%LOCALAPPDATA%\WA-HQ-PTT`.

The uninstaller does not delete WhatsApp data or the WhatsApp user profile. FFmpeg remains installed.
