$ErrorActionPreference = "Stop"

$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$CorePath = Join-Path $AppDir "start.core.ps1"
$UiPath = Join-Path $AppDir "ui.js"
$BootstrapLog = Join-Path $AppDir "logs\bootstrap.log"

function Write-BootstrapLog([string]$Message) {
    try {
        $dir = Split-Path -Parent $BootstrapLog
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Add-Content -LiteralPath $BootstrapLog -Value ("{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Message) -Encoding UTF8
    } catch {}
}

function Replace-Once([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $first = $Text.IndexOf($Old, [System.StringComparison]::Ordinal)
    if ($first -lt 0) { throw "PTT speed patch: missing marker '$Label'" }
    $second = $Text.IndexOf($Old, $first + $Old.Length, [System.StringComparison]::Ordinal)
    if ($second -ge 0) { throw "PTT speed patch: marker '$Label' is not unique" }
    return $Text.Substring(0, $first) + $New + $Text.Substring($first + $Old.Length)
}

function Replace-AllExpected([string]$Text, [string]$Old, [string]$New, [int]$Expected, [string]$Label) {
    $count = ([regex]::Matches($Text, [regex]::Escape($Old))).Count
    if ($count -ne $Expected) { throw "PTT speed patch: marker '$Label' count is $count, expected $Expected" }
    return $Text.Replace($Old, $New)
}

function Replace-Function([string]$Text, [string]$StartMarker, [string]$NextMarker, [string]$Replacement, [string]$Label) {
    $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { throw "PTT speed patch: missing function '$Label'" }
    $finish = $Text.IndexOf($NextMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
    if ($finish -lt 0) { throw "PTT speed patch: missing end marker for '$Label'" }
    return $Text.Substring(0, $start) + $Replacement + "`r`n`r`n" + $Text.Substring($finish)
}

try {
    if (-not (Test-Path -LiteralPath $CorePath -PathType Leaf)) {
        throw "Missing runtime core: $CorePath. Run INSTALLA.cmd again from the complete package."
    }
    if (-not (Test-Path -LiteralPath $UiPath -PathType Leaf)) {
        throw "Missing ui.js: $UiPath. Run INSTALLA.cmd again."
    }

    # Keep the last known-good HQ UI/recording path unchanged.
    $ui = [System.IO.File]::ReadAllText($UiPath, [System.Text.Encoding]::UTF8)
    if ($ui.Contains('const VERSION = "2.0.1";')) {
        $ui = Replace-Once $ui 'const VERSION = "2.0.1";' 'const VERSION = "2.0.2";' "ui-version"

        $newNativeFinish = @'
    async function nativeFinish(session, chatId) {
        try {
            const parts = state.nativeParts[session];
            if (!parts || !parts.length) throw new Error("No OGG data");

            setStatus("sending", "Sending HQ voice message...");
            const file = new File(parts, `WA-HQ-${Date.now()}.ogg`, { type: "audio/ogg; codecs=opus" });
            delete state.nativeParts[session];

            await WPP.chat.sendFileMessage(chatId, file, {
                type: "audio",
                isPtt: true,
                mimetype: "audio/ogg; codecs=opus",
                waveform: true
            });

            state.session = null;
            state.chatId = null;
            setStatus("idle", "Sent");
            scheduleUi(() => {
                if (state.mode === "idle") setStatus("idle");
            }, 1400);
        } catch (e) {
            console.error("WA HQ send error", e);
            delete state.nativeParts[session];
            state.session = null;
            state.chatId = null;
            reportClientError("send", e);
            setStatus("error", "Send failed");
            scheduleUi(() => setStatus("idle"), 4000);
        }
    }
'@
        $ui = Replace-Function $ui '    async function nativeFinish(session, chatId) {' '    function nativeFail(message) {' $newNativeFinish "nativeFinish"
        [System.IO.File]::WriteAllText($UiPath, $ui, [System.Text.UTF8Encoding]::new($false))
        Write-BootstrapLog "Restored known-good HQ UI/runtime v2.0.3"
    } elseif (-not ($ui.Contains('const VERSION = "2.0.2";') -and $ui.Contains('audio/ogg; codecs=opus') -and $ui.Contains('waveform: true'))) {
        throw "Unsupported ui.js version; reinstall from the complete package to restore HQ mode"
    }

    $core = [System.IO.File]::ReadAllText($CorePath, [System.Text.Encoding]::UTF8)

    # iOS isolation test: only swap the injected WA-JS engine. Recorder, overlay,
    # FFmpeg profile, bitrate and send options below remain identical to the
    # restored Android-good HQ build.
    $core = Replace-Once $core '$WajsVersion = "4.6.0"' '$WajsVersion = "4.6.1-alpha.0-nightly-2026-09-24"' "wajs-nightly-version"
    $core = Replace-Once $core '$ExpectedWajsSha256 = "5BFB88027F14A4D8C9E319374E8BB4083201906881CF8C74F75789B32E4106BD"' '$ExpectedWajsSha256 = "624F910B6A360C8B34C8962C82826E5539765F4AC0BA427D351D224DE29BFDEC"' "wajs-nightly-sha"
    $core = Replace-Once $core '"https://cdn.jsdelivr.net/npm/@wppconnect/wa-js@$WajsVersion/dist/wppconnect-wa.js",' '"https://github.com/wppconnect-team/wa-js/releases/download/nightly/wppconnect-wa.js",' "wajs-nightly-url-primary"
    $core = Replace-Once $core '"https://unpkg.com/@wppconnect/wa-js@$WajsVersion/dist/wppconnect-wa.js"' '"https://github.com/wppconnect-team/wa-js/releases/download/nightly/wppconnect-wa.js"' "wajs-nightly-url-fallback"
    Write-BootstrapLog "iOS isolation test: WA-JS nightly 2026-09-24 SHA-256 pinned; HQ audio/UI unchanged"

    $core = Replace-Once $core '@(".webm", ".m4a")' '@(".webm", ".ogg", ".m4a")' "stale-temp-extensions"

    $newConvert = @'
function Convert-And-Send($Upload) {
    try {
        if ($Upload.Stream) {
            $Upload.Stream.Flush()
            $Upload.Stream.Dispose()
            $Upload.Stream = $null
        }

        Set-NativeStatus "processing" "Encoding HQ OGG/Opus..."
        Write-Log "Encoding $($Upload.WebmPath) -> $($Upload.OggPath) as HQ Opus 48 kHz mono"

        Remove-Item -LiteralPath $Upload.OggPath -Force -ErrorAction SilentlyContinue
        $encodeArgs = @(
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", $Upload.WebmPath,
            "-vn",
            "-map", "0:a:0",
            "-af", "aresample=async=1:first_pts=0",
            "-c:a", "libopus",
            "-b:a", [string]$script:config.RecordBitrate,
            "-ar", "48000",
            "-ac", "1",
            "-application", "audio",
            "-frame_duration", "20",
            "-vbr", "on",
            "-compression_level", "10",
            "-f", "ogg",
            $Upload.OggPath
        )

        $encodeOutput = & $script:ffmpeg @encodeArgs 2>&1
        $encodeExitCode = $LASTEXITCODE
        if ($encodeExitCode -ne 0 -or -not (Test-Path -LiteralPath $Upload.OggPath)) {
            throw "FFmpeg HQ OGG/Opus exit $encodeExitCode - $($encodeOutput -join ' ')"
        }

        $bytes = [System.IO.File]::ReadAllBytes($Upload.OggPath)
        if (-not $bytes -or $bytes.Length -lt 100) { throw "Converted OGG/Opus is empty" }

        Write-Log "HQ OGG/Opus ready: $($bytes.Length) bytes"
        Set-NativeStatus "sending" "Sending HQ voice message..."

        $sessionJs = Js-String $Upload.Session
        $chatJs = Js-String $Upload.ChatId
        Invoke-JsNoWait "window.__WAHQ && window.__WAHQ.nativeStart($sessionJs);"

        $chunkSize = 180 * 1024
        for ($offset = 0; $offset -lt $bytes.Length; $offset += $chunkSize) {
            $count = [Math]::Min($chunkSize, $bytes.Length - $offset)
            $part = New-Object byte[] $count
            [Array]::Copy($bytes, $offset, $part, 0, $count)
            $b64 = [Convert]::ToBase64String($part)
            $b64Js = Js-String $b64
            Invoke-JsNoWait "window.__WAHQ && window.__WAHQ.nativeChunk($sessionJs,$b64Js);"
        }

        Invoke-JsNoWait "window.__WAHQ && window.__WAHQ.nativeFinish($sessionJs,$chatJs);"
        Write-Log "HQ OGG/Opus transferred back to page for WPP send"
    } catch {
        Write-Log "Audio conversion/transfer failed: $($_.Exception.Message)"
        Fail-Native "Audio conversion failed. See helper.log."
    } finally {
        Clear-Upload $Upload.Session
    }
}
'@

    $core = Replace-Function $core 'function Convert-And-Send($Upload) {' 'function Handle-BridgePayload([string]$Payload) {' $newConvert "Convert-And-Send"
    $core = Replace-AllExpected $core 'M4aPath' 'OggPath' 3 "M4aPath"
    $core = Replace-Once $core '$m4a = $tempBase + ".m4a"' '$ogg = $tempBase + ".ogg"' "ogg-temp-path"
    $core = Replace-Once $core 'Remove-Item $webm, $m4a -Force -ErrorAction SilentlyContinue' 'Remove-Item $webm, $ogg -Force -ErrorAction SilentlyContinue' "ogg-temp-remove"
    $core = Replace-Once $core 'OggPath = $m4a' 'OggPath = $ogg' "ogg-upload-property"

    Write-BootstrapLog "Starting HQ runtime with isolated WA-JS nightly iOS test (128k default, 48 kHz mono)"
    & ([ScriptBlock]::Create($core))
} catch {
    Write-BootstrapLog "FATAL: $($_.Exception.Message)"
    throw
}
