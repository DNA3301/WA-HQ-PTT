# WA-HQ-PTT

## Fix poor, muffled or compressed WhatsApp Desktop voice-message quality on Windows

WA-HQ-PTT is a free, open-source workaround for Windows users whose microphone sounds clean in Windows Sound Recorder, OBS, Discord or other applications but noticeably worse in WhatsApp Desktop voice messages.

The project keeps the familiar WhatsApp voice-message workflow while replacing the problematic recording/encoding path with a local HQ pipeline.

**Current validated version: v2.0.5**

[Download current v2.0.5 source ZIP](https://github.com/DNA3301/WA-HQ-PTT/archive/refs/heads/main.zip) · [Project website](https://dna3301.github.io/WA-HQ-PTT/) · [Repository](https://github.com/DNA3301/WA-HQ-PTT)

## What is fixed in v2.0.5

- HQ recording remains active on Android recipients instead of falling back to WhatsApp's lower-quality native recording path.
- Voice notes are sent as canonical OGG/Opus PTT media at 48 kHz mono with a 128 kbps default bitrate.
- Recipient playback-speed controls remain usable at 1x / 1.5x / 2x.
- Silent playback on WhatsApp for iOS was fixed by moving the compatibility change to the WA-JS media layer instead of degrading the audio profile.
- The validated WA-JS nightly build from 2026-09-24 is pinned by SHA-256.

The final v2.0.5 path was verified on real Android and iPhone recipients before being promoted to `main`.

## Features

- Uses the normal WhatsApp microphone button through a transparent HQ overlay.
- No separate permanent HQ button.
- Clean local microphone capture.
- Browser echo cancellation requested off.
- Browser noise suppression requested off.
- Browser automatic gain control requested off.
- High-quality WebM/Opus capture.
- Canonical OGG/Opus output at 48 kHz mono.
- 128 kbps default Opus bitrate.
- Sends as a normal WhatsApp voice message/PTT.
- Waveform support.
- Recipient 1x / 1.5x / 2x playback-speed support.
- Cancel button during recording.
- Escape key cancels recording.
- Automatic re-hooking after WhatsApp UI changes.
- Local processing; no project-owned audio upload service.
- Free and open source.

## How it works

```text
Microphone
    ↓
Clean local capture
    ↓
High-quality WebM/Opus recording
    ↓
FFmpeg canonical OGG/Opus encode
48 kHz · mono · 20 ms frames · 128 kbps default
    ↓
Pinned WA-JS media pipeline
    ↓
WhatsApp PTT
```

WA-HQ-PTT intercepts the normal microphone control with a transparent overlay and records with `getUserMedia`. It requests echo cancellation, noise suppression and automatic gain control to be disabled, then records Opus locally.

The recording is normalized by FFmpeg into a WhatsApp-friendly OGG/Opus voice-note stream. The prepared file is handed to WA-JS using the PTT path:

```javascript
WPP.chat.sendFileMessage(chatId, file, {
    type: "audio",
    isPtt: true,
    mimetype: "audio/ogg; codecs=opus",
    waveform: true
})
```

The current compatibility build uses the WA-JS nightly generated on 2026-09-24 from upstream commit `744e3d809f046059744f3cee035eed2bc516d6cd`.

Pinned bundle SHA-256:

```text
624F910B6A360C8B34C8962C82826E5539765F4AC0BA427D351D224DE29BFDEC
```

## Installation

1. [Download the current main ZIP](https://github.com/DNA3301/WA-HQ-PTT/archive/refs/heads/main.zip).
2. Extract the ZIP completely.
3. Run `INSTALLA.cmd`.
4. Completely quit WhatsApp Desktop, including the tray process.
5. Reopen WhatsApp Desktop.
6. Open a chat and use the normal microphone button.

When WA-HQ-PTT is attached correctly, the normal microphone remains visible but the custom HQ overlay handles the click. During recording you will see the WA-HQ-PTT recording status and the cancel control.

### Requirements

- Windows 10 or Windows 11.
- WebView2-based WhatsApp Desktop.
- Windows PowerShell 5.1 or newer.
- Internet access during installation to download the pinned WA-JS bundle.
- FFmpeg.

The installer checks `ffmpeg -version`. If FFmpeg is missing, it attempts:

```text
winget install --id Gyan.FFmpeg -e --accept-package-agreements --accept-source-agreements
```

If `winget` is unavailable, install FFmpeg manually, make sure `ffmpeg.exe` is available on `PATH`, then run `INSTALLA.cmd` again.

## Usage

1. Open a WhatsApp chat.
2. Click the normal microphone button.
3. Speak.
4. Click the microphone again to send.
5. To cancel, click the trash/cancel button or press **Escape**.

Cancelled recordings are discarded locally and are never converted or sent.

The destination chat is captured when recording starts to reduce the risk of sending a finished recording to a different chat after a UI change.

## How to confirm HQ mode is active

Before testing audio quality, verify that the custom WA-HQ-PTT recording behavior appears when you click the microphone:

- the WA-HQ-PTT recording status appears;
- the custom cancel/trash control appears;
- pressing Escape cancels the recording;
- after stopping, the helper briefly shows local encoding/sending status.

If the normal WhatsApp recorder appears instead, the helper is not attached. See [Troubleshooting](docs/TROUBLESHOOTING.md).

## Configuration

Default configuration:

```json
{
  "DebugPort": 9223,
  "RecordBitrate": 128000,
  "AacBitrate": "192k",
  "SampleRate": 48000,
  "MicOverlayPaddingPx": 2,
  "MaxRecordingBytes": 67108864
}
```

`AacBitrate` remains in the configuration for backward compatibility with older installs, but the current v2.0.5 send path uses canonical OGG/Opus rather than AAC/M4A.

Installed configuration:

```text
%LOCALAPPDATA%\WA-HQ-PTT\config.json
```

Technical logs:

```text
%LOCALAPPDATA%\WA-HQ-PTT\logs\helper.log
%LOCALAPPDATA%\WA-HQ-PTT\logs\bootstrap.log
```

## WA-JS compatibility

v2.0.5 intentionally pins the tested upstream WA-JS nightly rather than automatically following the newest available build.

The installer and `AGGIORNA-WA-JS.cmd` verify the exact SHA-256 before accepting the bundle. This prevents a later upstream nightly from silently replacing the build that was validated with WA-HQ-PTT.

The current pinned upstream build is:

```text
WA-JS 4.6.1-alpha.0 nightly
Upstream commit: 744e3d809f046059744f3cee035eed2bc516d6cd
Bundle date: 2026-09-24
SHA-256: 624F910B6A360C8B34C8962C82826E5539765F4AC0BA427D351D224DE29BFDEC
```

## Commands

- `INSTALLA.cmd` — install or repair WA-HQ-PTT.
- `AVVIA.cmd` — start the installed helper.
- `STOP.cmd` — stop the installed helper.
- `AGGIORNA-WA-JS.cmd` — re-download and verify the pinned tested WA-JS bundle.
- `DISINSTALLA.cmd` — remove WA-HQ-PTT and restore the backed-up registry value.

The uninstaller does not delete WhatsApp chats, the WhatsApp profile or FFmpeg.

## What the installer changes

WA-HQ-PTT is installed for the current Windows user in:

```text
%LOCALAPPDATA%\WA-HQ-PTT
```

The installer:

- copies the helper runtime files;
- downloads and verifies the pinned WA-JS bundle;
- adds WebView2 remote-debugging arguments for `WhatsApp.Root.exe`, bound to `127.0.0.1`;
- saves the previous registry value before the first change;
- creates a per-user Startup shortcut for the helper.

Re-running `INSTALLA.cmd` is supported. Existing user configuration and the original registry backup are preserved.

The helper connects locally to WhatsApp's WebView through the Chrome DevTools Protocol. Local remote debugging is powerful: another process running as your Windows user may be able to inspect that WebView while WhatsApp is open. See [Security](docs/SECURITY.md) for the exact trade-off.

## Privacy

- Microphone capture occurs locally in the WhatsApp WebView.
- Temporary recordings are processed locally.
- FFmpeg conversion occurs locally.
- WA-HQ-PTT does not intentionally upload recordings to its own server.
- The final media is handed to WhatsApp for normal delivery.
- Temporary helper-created media is cleaned after processing or cancellation.

Normal WhatsApp message delivery remains subject to WhatsApp's own privacy practices and terms.

## Third-party software

WA-HQ-PTT uses [@wppconnect/wa-js](https://github.com/wppconnect-team/wa-js), maintained by the WPPConnect team. WA-JS was not created by DNA3301 and remains subject to its own Apache-2.0 license.

WA-HQ-PTT also invokes [FFmpeg](https://ffmpeg.org/) for local conversion. FFmpeg remains subject to its own applicable license.

See [Third-party notices](docs/THIRD_PARTY_NOTICES.md).

## Support / Donations

WA-HQ-PTT is free and open source. Donations are optional and never unlock features.

EVM-compatible wallet:

```text
0x9FAA94cE4eD7A2d38F45D711694C6EC2E49ad99a
```

Only send assets using an EVM-compatible network supported by your wallet. Always verify network compatibility before sending funds.

## Disclaimer

WA-HQ-PTT is an unofficial community project. It is not affiliated with, endorsed by or sponsored by WhatsApp or Meta.

WhatsApp Desktop/Web internals may change at any time and a future update may temporarily break compatibility.

## License

Original WA-HQ-PTT code is released under the [MIT License](LICENSE), copyright 2026 DNA3301. Third-party software remains under its respective license.

---

## Italiano

WA-HQ-PTT è un workaround gratuito e open source per chi sente i vocali WhatsApp Desktop su PC molto più ovattati, compressi o gracchianti rispetto allo stesso microfono usato in altre applicazioni.

La v2.0.5 mantiene la registrazione HQ a 128 kbps e usa OGG/Opus 48 kHz mono per l'invio PTT. La compatibilità iPhone è stata risolta mantenendo intatta la qualità audio e aggiornando il livello WA-JS usato per preparare e inviare il media.

Per verificare che sia attivo il percorso HQ, durante la registrazione devono comparire l'indicatore WA-HQ-PTT e il pulsante cestino/annulla. Se parte il registratore standard di WhatsApp, consulta la guida di troubleshooting.
