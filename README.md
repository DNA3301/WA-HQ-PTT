# WA-HQ-PTT

High-quality voice messages for WhatsApp Desktop on Windows

Some WhatsApp Desktop users experience noticeably degraded microphone quality when recording native voice messages, even though the same microphone sounds clean in other Windows applications.

WA-HQ-PTT is a workaround for those users. It uses an alternate local recording and encoding pipeline while keeping the normal WhatsApp voice-message workflow. There is no separate HQ button: the normal microphone icon remains visible and is used to start and stop recording.

## How it works

```text
Microphone
    ↓
Clean local capture
    ↓
High-quality temporary recording
    ↓
FFmpeg AAC/M4A conversion
    ↓
WA-JS
    ↓
WhatsApp PTT
```

In more detail, WA-HQ-PTT:

- intercepts the normal WhatsApp microphone button;
- captures locally with browser audio processing such as echo cancellation, noise suppression, and automatic gain control requested off;
- records a temporary WebM/Opus file at a high bitrate;
- converts it locally with FFmpeg to AAC/M4A at 48 kHz;
- sends it through `@wppconnect/wa-js` using `sendFileMessage(..., { type: "audio", isPtt: true })`;
- presents the result to the recipient as a normal WhatsApp voice message/PTT.

You do not need to record with Windows Sound Recorder or attach a file manually. Conversion and sending are automatic after the second click on the microphone.

This does not claim that WhatsApp voice recording is poor on every PC. It is intended for Windows users whose microphone sounds clean elsewhere but noticeably compressed, muffled, or artifact-heavy in native WhatsApp Desktop voice messages.

## Installation

1. Download `WA-HQ-PTT-v2.0.0.zip` from the [latest release](https://github.com/DNA3301/WA-HQ-PTT/releases/latest).
2. Extract the ZIP completely.
3. Run `INSTALLA.cmd`.
4. Completely quit and restart WhatsApp Desktop.
5. Open a chat and use the normal microphone button.

### Requirements

- Windows 10 or Windows 11
- The WebView2-based WhatsApp Desktop app
- Windows PowerShell 5.1 or newer
- Internet access during installation to download the pinned WA-JS bundle
- FFmpeg

The installer checks `ffmpeg -version`. If FFmpeg is missing, it attempts:

```text
winget install --id Gyan.FFmpeg -e --accept-package-agreements --accept-source-agreements
```

If `winget` is unavailable, the installer stops with a clear message and asks you to install FFmpeg manually, make `ffmpeg.exe` available on `PATH`, and rerun `INSTALLA.cmd`.

No administrator permission is normally needed for WA-HQ-PTT itself. The FFmpeg package installer may display its own prompt depending on the system configuration.

## Usage

1. Open the destination chat.
2. Click WhatsApp's normal microphone icon to start HQ recording.
3. Speak normally.
4. Click the same icon again to stop.
5. Wait for local conversion and automatic sending.

The destination chat is captured when recording starts, which helps prevent an accidental send to a different chat if the UI changes during recording. A small recording or processing status appears beside the normal microphone icon.

## What the installer changes

WA-HQ-PTT is installed for the current Windows user in:

```text
%LOCALAPPDATA%\WA-HQ-PTT
```

The installer:

- copies only the helper's runtime files;
- downloads the tested `@wppconnect/wa-js` v4.6.0 bundle and verifies its SHA-256 hash;
- adds WebView2 remote-debugging arguments for `WhatsApp.Root.exe`, bound to `127.0.0.1`;
- saves the previous registry value before its first change;
- creates a per-user Startup shortcut for the helper.

Re-running `INSTALLA.cmd` is supported. Existing user configuration and the original registry backup are preserved.

The helper connects locally to WhatsApp's WebView through the Chrome DevTools Protocol. Local remote debugging is powerful: another process running as your Windows user may be able to inspect that WebView while WhatsApp is open. See [Security](docs/SECURITY.md) for the exact trade-off.

## Commands

- `INSTALLA.cmd` — install or repair WA-HQ-PTT
- `AVVIA.cmd` — start the installed helper
- `STOP.cmd` — stop the installed helper
- `AGGIORNA-WA-JS.cmd` — re-download and verify the tested WA-JS version
- `DISINSTALLA.cmd` — remove WA-HQ-PTT and restore the backed-up registry value

The uninstaller does not delete WhatsApp, chats, WhatsApp cache, or the WhatsApp user profile. FFmpeg is intentionally left installed because other applications may use it.

## Configuration and logs

Runtime configuration:

```text
%LOCALAPPDATA%\WA-HQ-PTT\config.json
```

Technical log:

```text
%LOCALAPPDATA%\WA-HQ-PTT\logs\helper.log
```

The default audio settings are WebM/Opus at 128 kbps followed by AAC/M4A at 192 kbps and 48 kHz. Technical logs rotate locally and are not part of the repository or release archive.

For common errors—including microphone permission, FFmpeg, WA-JS, active-chat, conversion, sending, and compatibility issues—see [Troubleshooting](docs/TROUBLESHOOTING.md).

## Privacy

- Recording occurs locally in the WhatsApp WebView.
- Temporary audio is processed locally.
- FFmpeg conversion occurs locally.
- The resulting media is handed to WhatsApp for normal message transmission.
- WA-HQ-PTT itself does not intentionally upload recordings to a separate third-party server.
- Temporary WebM and M4A files are removed after processing; stale helper-created temporary media is cleaned on later starts.

During installation or repair, the helper downloads WA-JS from the pinned public npm package through a CDN. Normal WhatsApp message delivery remains subject to WhatsApp's own privacy practices and terms.

## Third-party software

WA-HQ-PTT uses [@wppconnect/wa-js](https://github.com/wppconnect-team/wa-js), maintained by the WPPConnect team. WA-JS was not developed by DNA3301. Version 4.6.0 is pinned for this release and remains subject to its Apache-2.0 license.

WA-HQ-PTT also invokes [FFmpeg](https://ffmpeg.org/) for local conversion. FFmpeg and its installed build remain subject to their own licenses. No WA-JS or FFmpeg binary is committed to this repository or bundled in the release ZIP.

See [Third-party notices](docs/THIRD_PARTY_NOTICES.md).

## Support / Donations

WA-HQ-PTT is free and open source.

If this project fixed your WhatsApp voice-message quality and you'd like to support its development, donations are completely optional.

EVM-compatible wallet:

```text
0x9FAA94cE4eD7A2d38F45D711694C6EC2E49ad99a
```

Only send assets using an EVM-compatible network supported by your wallet. Always verify network compatibility before sending funds. Donations are never required to download, install, or use any feature.

## Disclaimer

WA-HQ-PTT is an unofficial community project.

It is not affiliated with, endorsed by, or sponsored by WhatsApp or Meta.

WhatsApp Desktop/Web internals may change at any time and future updates may temporarily break compatibility.

Users use the software at their own risk.

## License

Original WA-HQ-PTT code is released under the [MIT License](LICENSE), copyright 2026 DNA3301. Third-party software remains under its respective license and is not relicensed as part of WA-HQ-PTT.

---

### Nota in italiano

WA-HQ-PTT è un workaround per gli utenti Windows che sentono i vocali di WhatsApp Desktop molto più compressi o ovattati rispetto allo stesso microfono usato in altre applicazioni. Usa il normale pulsante microfono, registra e converte localmente, quindi invia automaticamente un vero messaggio vocale/PTT. Le donazioni sono del tutto facoltative; usare l'indirizzo indicato solo su reti EVM compatibili.
