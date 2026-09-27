# Troubleshooting

Start by completely quitting WhatsApp Desktop, including the tray process, running `AVVIA.cmd`, reopening WhatsApp, and waiting 5–10 seconds.

Technical logs are stored at:

```text
%LOCALAPPDATA%\WA-HQ-PTT\logs\helper.log
%LOCALAPPDATA%\WA-HQ-PTT\logs\bootstrap.log
```

Logs are intentionally concise. They may contain local file paths and diagnostic details, so review them before sharing publicly.

## The normal WhatsApp recorder starts instead of HQ mode

The helper has not attached to the current WhatsApp WebView, or a WhatsApp update changed the microphone UI.

1. Completely quit WhatsApp.
2. Run `STOP.cmd`, then `AVVIA.cmd`.
3. Reopen WhatsApp and wait 5–10 seconds.
4. Confirm the WA-HQ-PTT recording status and cancel/trash control appear when you click the microphone.
5. Check `helper.log` for `WA HQ UI injected`.
6. Run `INSTALLA.cmd` again to repair the local installation.

If the normal WhatsApp recorder appears, do not use that recording as an HQ quality test: the custom WA-HQ-PTT path is not active.

## Cancelling a recording

While the WA-HQ-PTT recording indicator is visible, click the trash/cancel button or press **Escape**. The microphone stream is stopped, captured audio is discarded, and nothing is converted or sent.

If the cancel control is not visible, completely restart WhatsApp and verify that `WA HQ UI injected` appears in `helper.log`.

## Microphone permission denied

Allow microphone access for desktop applications in Windows Settings under **Privacy & security > Microphone**, then restart WhatsApp. Also close applications that may be holding the microphone exclusively.

## No active chat

Open a person or group chat before pressing the microphone. WA-HQ-PTT records the destination chat when recording starts.

## FFmpeg missing

Run `INSTALLA.cmd` again. It verifies FFmpeg and attempts to install `Gyan.FFmpeg` with `winget` when needed.

If `winget` is unavailable, install FFmpeg manually, ensure `ffmpeg.exe` is on `PATH`, open a new terminal, and rerun the installer.

## WA-JS missing or failed integrity verification

Run `AGGIORNA-WA-JS.cmd`.

v2.0.5 pins the tested WA-JS nightly generated on 2026-09-24 from upstream commit:

```text
744e3d809f046059744f3cee035eed2bc516d6cd
```

Expected bundle SHA-256:

```text
624F910B6A360C8B34C8962C82826E5539765F4AC0BA427D351D224DE29BFDEC
```

A failed hash check is rejected rather than installed.

## Conversion failed

Confirm that `ffmpeg -version` works, then check `helper.log`. v2.0.5 encodes the outgoing PTT as canonical OGG/Opus at 48 kHz mono, 20 ms frames, with a 128 kbps default bitrate. Temporary files are removed after processing or failure.

## Audio quality became poor again

First confirm that the WA-HQ-PTT overlay and cancel control appear while recording. If they do not, WhatsApp's normal recorder is being used instead of the HQ path.

The validated v2.0.5 profile is:

```text
OGG/Opus
48 kHz
mono
20 ms frames
128 kbps default
VBR on
Opus application=audio
waveform enabled
```

Do not intentionally switch the output to the superseded v2.0.4 experimental 64 kbps / `application=voip` profile if the goal is to preserve the tested HQ quality.

## Voice message is audible on Android but silent on iPhone

This was the main compatibility issue fixed by v2.0.5. Re-run `INSTALLA.cmd` and `AGGIORNA-WA-JS.cmd`, completely restart WhatsApp Desktop, then confirm the pinned WA-JS bundle hash matches the value above.

If the problem returns after a future WhatsApp update, include `helper.log` and `bootstrap.log` when reporting it.

## Playback-speed button changes but playback does not speed up

v2.0.5 sends PTT as OGG/Opus rather than the older AAC/M4A compatibility path. Reinstall the current version and confirm the HQ path is active before retesting 1x / 1.5x / 2x on the recipient device.

## Sending failed

Check the network connection and try again in the same chat. If failures began immediately after a WhatsApp update, WA-JS or WhatsApp internals may have changed. Check this repository for a newer compatibility update.

## Uninstall

Run `DISINSTALLA.cmd`. It stops the helper, removes its Startup shortcut, restores the registry value saved during the first installation, and removes `%LOCALAPPDATA%\WA-HQ-PTT`.

The uninstaller does not delete WhatsApp data or the WhatsApp user profile. FFmpeg remains installed.
