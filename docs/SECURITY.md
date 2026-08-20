# Security

## Local WebView debugging

WA-HQ-PTT needs Chrome DevTools Protocol access to inject its helper into the WhatsApp Desktop WebView. The installer configures the endpoint on `127.0.0.1` only; it is not intentionally exposed to the local network.

Remote debugging is nevertheless a powerful capability. Another process running under your Windows account may be able to inspect or control the WhatsApp WebView while the debugging endpoint is enabled. Only install software you trust and use `DISINSTALLA.cmd` when you no longer need WA-HQ-PTT.

## Downloads and integrity

The repository and release ZIP do not bundle WA-JS or FFmpeg binaries.

- WA-JS v4.6.0 is downloaded over HTTPS from pinned npm CDN paths and checked against a pinned SHA-256 digest before installation.
- FFmpeg is discovered locally or installed through the `Gyan.FFmpeg` winget package.

## Data handling

Recordings and FFmpeg conversion remain local until the converted media is handed to WhatsApp. Temporary media uses random session names and is removed after processing. Runtime logs, configuration, registry backups, downloaded bundles, and temporary media are ignored by Git.

## Reporting a vulnerability

Please open a GitHub issue containing a minimal description and reproduction steps. Do not include WhatsApp session data, phone numbers, chat content, recordings, tokens, cookies, or other personal information.
