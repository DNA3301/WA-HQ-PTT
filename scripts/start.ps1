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

    # Patch the installed UI once. The source file stays pinned to the tested 2.0.1 core,
    # while the runtime file becomes 2.0.2 and sends a genuine OGG/Opus PTT.
    # Backend compatibility revision: v2.0.3 normalizes Opus for Android + iOS.
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
        Write-BootstrapLog "Patched ui.js to runtime v2.0.2 OGG/Opus PTT"
    } elseif (-not ($ui.Contains('const VERSION = "2.0.2";') -and $ui.Contains('audio/ogg; codecs=opus'))) {
        throw "Unsupported ui.js version; refusing to apply the PTT speed patch"
    }

    $core = [System.IO.File]::ReadAllText($CorePath, [System.Text.Encoding]::UTF8)

    # Keep removing old M4A leftovers as well, but add the new OGG temp files.
    $core = Replace-Once $core '@(".webm", ".m4a")' '@(".webm", ".ogg", ".m4a")' "stale-temp-extensions"

    $newConvert = @'
function Convert-And-Send($Upload) {
    try {
        if ($Upload.Stream) {
            $Upload.Stream.Flush()
            $Upload.Stream.Dispose()
            $Upload.Stream = $null
        }

        Set-NativeStatus "processing" "Encoding iOS-safe OGG/Opus..."
        Write-Log "Normalizing $($Upload.WebmPath) -> $($Upload.OggPath) as Opus 48 kHz mono"

        # Do not stream-copy the browser Opus bitstream. Android accepts that form,
        # but iOS WhatsApp can receive a PTT that is present yet silent. Re-encoding
        # rebuilds the Opus headers/timestamps and forces the native voice-note shape.
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
            throw "FFmpeg canonical OGG/Opus exit $encodeExitCode - $($encodeOutput -join ' ')"
        }

        $bytes = [System.IO.File]::ReadAllBytes($Upload.OggPath)
        if (-not $bytes -or $bytes.Length -lt 100) { throw "Converted OGG/Opus is empty" }

        Write-Log "OGG/Opus ready: $($bytes.Length) bytes"
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
        Write-Log "OGG/Opus transferred back to page for WPP send"
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

    Write-BootstrapLog "Starting patched OGG/Opus runtime v2.0.3 (48 kHz mono canonical encode)"
    & ([ScriptBlock]::Create($core))
} catch {
    Write-BootstrapLog "FATAL: $($_.Exception.Message)"
    throw
}
