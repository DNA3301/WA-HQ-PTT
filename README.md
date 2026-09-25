# WA-HQ-PTT

## Fix poor, muffled or compressed WhatsApp Desktop voice-message quality on Windows

Some Windows users find that their microphone sounds clean in Windows Sound Recorder, OBS, Discord or other applications, but WhatsApp Desktop voice messages sound muffled, heavily compressed, crackly, or like low-quality radio audio.

WA-HQ-PTT is a free, open-source workaround for those users. It bypasses the problematic voice-message recording and encoding path with a clean local recording pipeline while preserving the normal WhatsApp PTT experience. It does not claim that every WhatsApp Desktop installation has this issue.

[Download the latest release](https://github.com/DNA3301/WA-HQ-PTT/releases/latest) · [Project website](https://dna3301.github.io/WA-HQ-PTT/)

## Features

- Uses WhatsApp's normal microphone button
- No separate HQ button
- Clean local microphone recording
- Automatic AAC/M4A conversion
- Sends as a normal WhatsApp voice message/PTT
- Cancel button during recording
- Escape key cancels recording
- No manual audio attachment required
- Automatic re-hooking after WhatsApp UI changes
- Local audio processing
- Free and open source

## How it works

```text
Microphone
    ↓
Clean local capture
    ↓
High-quality WebM/Opus recording
    ↓
FFmpeg AAC/M4A conversion
    ↓
WA-JS
    ↓
WhatsApp PTT
```

The issue was isolated by comparing audio captured locally with audio produced after the normal WhatsApp voice-message path. On affected configurations, the local recording can be clean while the final native voice message is noticeably more compressed or distorted.

WA-HQ-PTT intercepts the normal microphone button and asks `getUserMedia` to disable echo cancellation, noise suppression and automatic gain control. It records high-quality WebM/Opus locally, converts it with FFmpeg to AAC/M4A at 48 kHz, and gives the prepared media to `@wppconnect/wa-js` using:

```javascript
sendFileMessage(chatId, file, {
    type: "audio",
    isPtt: true
})
```

The recipient receives a normal WhatsApp voice message/PTT. There is no need to record first with Windows Sound Recorder or attach an audio file manually.

## Installation

1. [Download the latest release](https://github.com/DNA3301/WA-HQ-PTT/releases/latest).
2. Extract the ZIP completely.
3. Run `INSTALLA.cmd`.
4. Completely quit and restart WhatsApp Desktop.
5. Use the normal microphone button.

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

If `winget` is unavailable, the installer explains that FFmpeg must be installed manually and made available on `PATH` before running `INSTALLA.cmd` again. WA-HQ-PTT itself normally does not require administrator permission; the FFmpeg package installer may show its own prompt.

## Usage

1. Open a WhatsApp chat.
2. Click the normal microphone button.
3. Speak.
4. To send, click the microphone again.
5. To cancel, click the trash/cancel button or press **Escape**.
6. WA-HQ-PTT converts the audio locally and sends it automatically as a normal voice message.

**Cancelled recordings are discarded and never converted or sent.** The microphone stream is closed, captured data is cleared, and the interface returns to idle.

The destination chat is captured when recording starts. This helps prevent an accidental send to a different chat if the UI changes during recording.

## FAQ

### Why does my microphone sound good in Windows but bad in WhatsApp Desktop?

Different applications can use different capture, processing and encoding paths. On some Windows configurations, the WhatsApp Desktop voice-message recorder produces a more muffled, compressed or crackly result than the same microphone in other applications. WA-HQ-PTT is intended for that specific situation.

### How do I fix muffled WhatsApp Desktop voice messages?

WA-HQ-PTT records the microphone locally, converts the clean recording to AAC/M4A with FFmpeg, and sends it as a WhatsApp PTT. This avoids the native voice-message recording path that causes poor quality on some PCs.

### Does this improve WhatsApp Desktop microphone quality?

It changes the recording and encoding pipeline used for voice messages; it does not change or repair the microphone hardware. Results still depend on the input device, Windows settings and the WhatsApp version.

### Does it work with USB microphones?

WA-HQ-PTT uses the input device available to WhatsApp's Chromium/WebView2 environment. It should work with ordinary built-in, USB and audio-interface microphones that Windows and WhatsApp can access.

### Are recordings uploaded to another server?

Recording and FFmpeg conversion occur locally. WA-HQ-PTT does not intentionally upload recordings to its own server. The resulting media is handed to WhatsApp for normal message delivery.

### How do I cancel a voice message?

While recording, click the visible trash/cancel button or press **Escape**. The recording is immediately discarded and is not converted or sent.

### Is this official WhatsApp software?

No. WA-HQ-PTT is an unofficial community project and is not affiliated with WhatsApp or Meta.

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

The uninstaller does not delete WhatsApp, chats, WhatsApp cache or the WhatsApp user profile. FFmpeg is intentionally left installed because other applications may use it.

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

For microphone permissions, FFmpeg, WA-JS, active-chat, conversion, sending and compatibility errors, see [Troubleshooting](docs/TROUBLESHOOTING.md).

## Privacy

- Microphone recording occurs locally in the WhatsApp WebView.
- Temporary recordings are processed locally.
- FFmpeg conversion occurs locally.
- WA-HQ-PTT does not intentionally upload recordings to its own server.
- The final media is handed to WhatsApp for normal message delivery.
- Temporary helper-created media is cleaned after processing or cancellation.

During installation or repair, the helper downloads WA-JS from the pinned public npm package through a CDN. Normal WhatsApp message delivery remains subject to WhatsApp's own privacy practices and terms.

## Third-party software

WA-HQ-PTT uses [@wppconnect/wa-js](https://github.com/wppconnect-team/wa-js), maintained by the WPPConnect team. WA-JS was not created by DNA3301. Version 4.6.0 is pinned for this release and remains subject to its Apache-2.0 license.

WA-HQ-PTT also invokes [FFmpeg](https://ffmpeg.org/) for local conversion. FFmpeg and its installed build remain subject to their own licenses. No WA-JS or FFmpeg binary is committed to this repository.

See [Third-party notices](docs/THIRD_PARTY_NOTICES.md).

## Support / Donations

WA-HQ-PTT is free and open source.

If WA-HQ-PTT fixed your WhatsApp Desktop voice-message quality and you'd like to support development, donations are completely optional.

EVM-compatible wallet:

```text
0x9FAA94cE4eD7A2d38F45D711694C6EC2E49ad99a
```

Only send assets using an EVM-compatible network supported by your wallet. Always verify network compatibility before sending funds. Donations are never required to download, install or use any feature.

## Disclaimer

WA-HQ-PTT is an unofficial community project.

It is not affiliated with, endorsed by, or sponsored by WhatsApp or Meta.

WhatsApp Desktop/Web internals may change at any time and future updates may temporarily break compatibility.

Users use the software at their own risk.

## License

Original WA-HQ-PTT code is released under the [MIT License](LICENSE), copyright 2026 DNA3301. Third-party software remains under its respective license and is not relicensed as part of WA-HQ-PTT.

---

## Italiano

WA-HQ-PTT è un workaround gratuito e open source per chi sente i vocali WhatsApp Desktop su PC molto più ovattati, compressi o gracchianti rispetto allo stesso microfono usato in altre applicazioni. Usa il normale pulsante del microfono, registra e converte localmente e invia automaticamente un vero messaggio vocale/PTT.

### Perché il microfono su WhatsApp Desktop si sente ovattato?

Su alcune configurazioni Windows, il percorso usato dal registratore dei vocali può produrre un risultato diverso e più compresso rispetto ad altre applicazioni. Il problema non riguarda necessariamente tutti gli utenti.

### Come migliorare la qualità dei vocali WhatsApp su PC?

Installa WA-HQ-PTT, riavvia completamente WhatsApp Desktop e usa il normale pulsante microfono. Il programma usa una registrazione locale pulita e la converte automaticamente prima dell'invio.

### Posso annullare un vocale?

Sì. Durante la registrazione, premi il pulsante cestino/annulla oppure **Esc**. Il vocale annullato viene eliminato e non viene convertito né inviato.
