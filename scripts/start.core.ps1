$ErrorActionPreference = "Stop"

$AppDir = Join-Path $env:LOCALAPPDATA "WA-HQ-PTT"
$ConfigPath = Join-Path $AppDir "config.json"
$WajsPath = Join-Path $AppDir "wppconnect-wa.js"
$UiPath = Join-Path $AppDir "ui.js"
$LogDir = Join-Path $AppDir "logs"
$LogPath = Join-Path $LogDir "helper.log"
$PidPath = Join-Path $AppDir "helper.pid"
$LockPath = Join-Path $AppDir "helper.lock"
$WajsVersion = "4.6.0"
$ExpectedWajsSha256 = "5BFB88027F14A4D8C9E319374E8BB4083201906881CF8C74F75789B32E4106BD"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

if (Test-Path $LogPath) {
    try {
        if ((Get-Item $LogPath).Length -gt 2MB) {
            $Prev = Join-Path $LogDir "helper.prev.log"
            Remove-Item $Prev -Force -ErrorAction SilentlyContinue
            Move-Item $LogPath $Prev -Force
        }
    } catch {}
}

function Write-Log([string]$Message) {
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"), $Message
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

try {
    $lockStream = [System.IO.File]::Open($LockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
} catch {
    exit 0
}

Set-Content -Path $PidPath -Value $PID -Encoding ASCII

try {
    $staleBefore = (Get-Date).AddDays(-1)
    Get-ChildItem -LiteralPath $env:TEMP -Filter "WAHQ-*" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $staleBefore -and $_.Extension -in @(".webm", ".m4a") } |
        Remove-Item -Force -ErrorAction SilentlyContinue
} catch {}

$script:ws = $null
$script:nextId = 1
$script:uploads = @{}
$script:isInitializing = $false
$script:ffmpeg = $null
$script:maxRecordingBytes = 67108864

function Find-FFmpeg {
    $cmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $roots = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"),
        "C:\ffmpeg",
        "C:\Program Files\ffmpeg"
    ) | Where-Object { $_ -and (Test-Path $_) }

    foreach ($root in $roots) {
        try {
            $hit = Get-ChildItem -Path $root -Filter ffmpeg.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { return $hit.FullName }
        } catch {}
    }

    return $null
}

function Get-Sha256([string]$Path) {
    $stream = [System.IO.File]::OpenRead($Path)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha256.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") }) -join "").ToUpperInvariant()
    } finally {
        $sha256.Dispose()
        $stream.Dispose()
    }
}

function Test-WajsBundle([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $Path).Length -lt 100000) { return $false }
    return (Get-Sha256 $Path) -eq $ExpectedWajsSha256
}

function Download-Wajs {
    $tmp = "$WajsPath.download"
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $urls = @(
        "https://cdn.jsdelivr.net/npm/@wppconnect/wa-js@$WajsVersion/dist/wppconnect-wa.js",
        "https://unpkg.com/@wppconnect/wa-js@$WajsVersion/dist/wppconnect-wa.js"
    )

    foreach ($url in $urls) {
        try {
            Write-Log "Downloading pinned WA-JS v$WajsVersion"
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp -TimeoutSec 45
            if (Test-WajsBundle $tmp) {
                Move-Item -LiteralPath $tmp -Destination $WajsPath -Force
                Write-Log "WA-JS v$WajsVersion downloaded and SHA-256 verified"
                return $true
            }
            Write-Log "WA-JS download rejected: version or SHA-256 mismatch"
        } catch {
            Write-Log "WA-JS download failed: $($_.Exception.Message)"
        }
    }

    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    return $false
}

function Send-CdpObject($Object) {
    if (-not $script:ws -or $script:ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
        throw "CDP WebSocket is not open"
    }

    $json = $Object | ConvertTo-Json -Compress -Depth 12
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $segment = [System.ArraySegment[byte]]::new($bytes)
    $script:ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
}

function Receive-CdpObject {
    if (-not $script:ws) { return $null }

    $buffer = New-Object byte[] 65536
    $ms = New-Object System.IO.MemoryStream
    try {
        do {
            $segment = [System.ArraySegment[byte]]::new($buffer)
            $result = $script:ws.ReceiveAsync($segment, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                return $null
            }

            if ($result.Count -gt 0) {
                $ms.Write($buffer, 0, $result.Count)
            }
        } while (-not $result.EndOfMessage)

        $text = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
        if (-not $text) { return $null }
        return $text | ConvertFrom-Json
    } finally {
        $ms.Dispose()
    }
}

function Send-CdpNoWait([string]$Method, $Params) {
    $id = $script:nextId
    $script:nextId++
    Send-CdpObject @{ id = $id; method = $Method; params = $Params }
    return $id
}

function Handle-CdpEvent($Message) {
    if (-not $Message -or -not $Message.method) { return }

    if ($Message.method -eq "Runtime.bindingCalled" -and $Message.params.name -eq "waHQBridge") {
        Handle-BridgePayload $Message.params.payload
        return
    }

    if ($Message.method -eq "Runtime.executionContextsCleared") {
        if (-not $script:isInitializing) {
            Write-Log "Execution contexts cleared; reinjecting"
            Start-Sleep -Seconds 3
            try { Initialize-Page } catch { Write-Log "Reinject failed: $($_.Exception.Message)" }
        }
    }
}

function Send-CdpWait([string]$Method, $Params) {
    $id = $script:nextId
    $script:nextId++
    Send-CdpObject @{ id = $id; method = $Method; params = $Params }

    while ($true) {
        $msg = Receive-CdpObject
        if ($null -eq $msg) { throw "CDP connection closed" }
        if ($msg.id -eq $id) { return $msg }
        Handle-CdpEvent $msg
    }
}

function Invoke-JsNoWait([string]$Expression) {
    Send-CdpNoWait "Runtime.evaluate" @{
        expression = $Expression
        awaitPromise = $false
        returnByValue = $false
        userGesture = $true
    } | Out-Null
}

function Js-String([string]$Value) {
    if ($null -eq $Value) { return "null" }
    return ($Value | ConvertTo-Json -Compress)
}

function Set-NativeStatus([string]$Mode, [string]$Text) {
    $m = Js-String $Mode
    $t = Js-String $Text
    Invoke-JsNoWait "window.__WAHQ && window.__WAHQ.setStatus($m,$t);"
}

function Fail-Native([string]$Text) {
    Write-Log "Native failure: $Text"
    $t = Js-String $Text
    try {
        Invoke-JsNoWait "window.__WAHQ && window.__WAHQ.nativeFail($t);"
    } catch {
        Write-Log "Unable to display the error in WhatsApp: $($_.Exception.Message)"
    }
}

function Clear-Upload([string]$Session) {
    if (-not $Session -or -not $script:uploads.ContainsKey($Session)) { return }

    $uploadToClear = $script:uploads[$Session]
    try { if ($uploadToClear.Stream) { $uploadToClear.Stream.Dispose() } } catch {}
    try { Remove-Item -LiteralPath $uploadToClear.WebmPath -Force -ErrorAction SilentlyContinue } catch {}
    try { Remove-Item -LiteralPath $uploadToClear.M4aPath -Force -ErrorAction SilentlyContinue } catch {}
    $script:uploads.Remove($Session)
}

function Convert-And-Send($Upload) {
    try {
        if ($Upload.Stream) {
            $Upload.Stream.Flush()
            $Upload.Stream.Dispose()
            $Upload.Stream = $null
        }

        Set-NativeStatus "processing" "Converting to M4A..."
        Write-Log "Converting $($Upload.WebmPath) -> $($Upload.M4aPath)"

        $args = @(
            "-hide_banner",
            "-loglevel", "error",
            "-y",
            "-i", $Upload.WebmPath,
            "-vn",
            "-c:a", "aac",
            "-b:a", [string]$script:config.AacBitrate,
            "-ar", [string]$script:config.SampleRate,
            "-movflags", "+faststart",
            $Upload.M4aPath
        )

        $output = & $script:ffmpeg @args 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0 -or -not (Test-Path $Upload.M4aPath)) {
            throw "FFmpeg exit $exitCode - $($output -join ' ')"
        }

        $bytes = [System.IO.File]::ReadAllBytes($Upload.M4aPath)
        if (-not $bytes -or $bytes.Length -lt 100) { throw "Converted M4A is empty" }

        Write-Log "M4A ready: $($bytes.Length) bytes"
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
        Write-Log "M4A transferred back to page for WPP send"
    } catch {
        Write-Log "Audio conversion/transfer failed: $($_.Exception.Message)"
        Fail-Native "Audio conversion failed. See helper.log."
    } finally {
        Clear-Upload $Upload.Session
    }
}

function Handle-BridgePayload([string]$Payload) {
    $sessionForCleanup = $null
    try {
        $p = $Payload | ConvertFrom-Json
        if (-not $p.action) { return }

        switch ([string]$p.action) {
            "upload-start" {
                $session = [string]$p.session
                $sessionForCleanup = $session
                if ($session -notmatch "^[A-Za-z0-9-]{8,64}$") { throw "Invalid upload session" }

                $chatId = [string]$p.chatId
                if ([string]::IsNullOrWhiteSpace($chatId)) { throw "No active destination chat" }

                $expectedBytes = [int64]$p.totalBytes
                $expectedChunks = [int]$p.totalChunks
                if ($expectedBytes -le 0) { throw "The recording is empty" }
                if ($expectedBytes -gt $script:maxRecordingBytes) { throw "The recording exceeds the configured size limit" }
                if ($expectedChunks -le 0) { throw "Invalid upload chunk count" }

                if ($script:uploads.ContainsKey($session)) {
                    Clear-Upload $session
                }

                $tempBase = Join-Path $env:TEMP ("WAHQ-" + $session)
                $webm = $tempBase + ".webm"
                $m4a = $tempBase + ".m4a"
                Remove-Item $webm, $m4a -Force -ErrorAction SilentlyContinue

                $fs = [System.IO.File]::Open($webm, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                $upload = [pscustomobject]@{
                    Session = $session
                    ChatId = $chatId
                    MimeType = [string]$p.mimeType
                    WebmPath = $webm
                    M4aPath = $m4a
                    Stream = $fs
                    ReceivedBytes = [int64]0
                    Chunks = 0
                    ExpectedBytes = $expectedBytes
                    ExpectedChunks = $expectedChunks
                    NextSequence = 0
                }
                $script:uploads[$session] = $upload
                Write-Log "Upload start session=$session expected=$expectedBytes chunks=$expectedChunks"
            }

            "upload-chunk" {
                $session = [string]$p.session
                $sessionForCleanup = $session
                if (-not $script:uploads.ContainsKey($session)) { throw "Unknown upload session" }
                $upload = $script:uploads[$session]
                $sequence = [int]$p.seq
                if ($sequence -ne $upload.NextSequence) { throw "Unexpected upload chunk sequence" }
                $bytes = [Convert]::FromBase64String([string]$p.data)
                if ($upload.ReceivedBytes + $bytes.Length -gt $upload.ExpectedBytes -or
                    $upload.ReceivedBytes + $bytes.Length -gt $script:maxRecordingBytes) {
                    throw "Upload data exceeds the declared size"
                }
                $upload.Stream.Write($bytes, 0, $bytes.Length)
                $upload.ReceivedBytes += $bytes.Length
                $upload.Chunks++
                $upload.NextSequence++
            }

            "upload-finish" {
                $session = [string]$p.session
                $sessionForCleanup = $session
                if (-not $script:uploads.ContainsKey($session)) { throw "Unknown upload session" }
                $upload = $script:uploads[$session]
                if ($upload.ReceivedBytes -ne $upload.ExpectedBytes -or $upload.Chunks -ne $upload.ExpectedChunks) {
                    throw "Incomplete audio upload"
                }
                Write-Log "Upload finish session=$session received=$($upload.ReceivedBytes) chunks=$($upload.Chunks)"
                Convert-And-Send $upload
            }

            "client-error" {
                $area = ([string]$p.area -replace "[\r\n]", " ").Substring(0, [Math]::Min(32, ([string]$p.area).Length))
                $message = ([string]$p.message -replace "[\r\n]", " ")
                if ($message.Length -gt 300) { $message = $message.Substring(0, 300) }
                Write-Log "Client error area=$area message=$message"
            }
        }
    } catch {
        Write-Log "Audio bridge failure: $($_.Exception.Message)"
        if ($sessionForCleanup) { Clear-Upload $sessionForCleanup }
        Fail-Native "Audio transfer failed. See helper.log."
    }
}

function Initialize-Page {
    if ($script:isInitializing) { return }
    $script:isInitializing = $true
    try {
        Write-Log "Initializing WhatsApp page"

        Send-CdpWait "Runtime.enable" @{} | Out-Null
        Send-CdpWait "Runtime.addBinding" @{ name = "waHQBridge" } | Out-Null

        $probe = Send-CdpWait "Runtime.evaluate" @{
            expression = "typeof WPP"
            returnByValue = $true
        }

        $wppType = $probe.result.result.value
        if ($wppType -ne "object") {
            if (-not (Test-WajsBundle $WajsPath)) {
                if (-not (Download-Wajs)) { throw "WA-JS bundle missing and download failed" }
            }

            Write-Log "Injecting WA-JS bundle"
            $wajs = [System.IO.File]::ReadAllText($WajsPath, [System.Text.Encoding]::UTF8)
            Send-CdpWait "Runtime.evaluate" @{
                expression = $wajs
                awaitPromise = $false
                returnByValue = $false
                userGesture = $true
            } | Out-Null

            for ($i = 0; $i -lt 30; $i++) {
                Start-Sleep -Milliseconds 500
                $probe = Send-CdpWait "Runtime.evaluate" @{
                    expression = "typeof WPP"
                    returnByValue = $true
                }
                if ($probe.result.result.value -eq "object") { break }
            }

            if ($probe.result.result.value -ne "object") { throw "WA-JS did not expose WPP" }
        }

        $apiProbe = Send-CdpWait "Runtime.evaluate" @{
            expression = "Boolean(WPP && WPP.chat && typeof WPP.chat.getActiveChat === 'function' && typeof WPP.chat.sendFileMessage === 'function')"
            returnByValue = $true
        }
        if (-not [bool]$apiProbe.result.result.value) {
            throw "Required WA-JS chat APIs are unavailable; this WhatsApp update may be incompatible"
        }

        $configJson = $script:config | ConvertTo-Json -Compress -Depth 5
        $configExpr = "window.__WAHQ_CONFIG__ = $configJson;"
        Send-CdpWait "Runtime.evaluate" @{
            expression = $configExpr
            returnByValue = $false
        } | Out-Null

        $ui = [System.IO.File]::ReadAllText($UiPath, [System.Text.Encoding]::UTF8)
        Send-CdpWait "Runtime.evaluate" @{
            expression = $ui
            awaitPromise = $false
            returnByValue = $false
            userGesture = $true
        } | Out-Null

        Write-Log "WA HQ UI injected"
    } finally {
        $script:isInitializing = $false
    }
}

function Get-WhatsAppTarget([int]$Port) {
    try {
        $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 2
        $target = $targets | Where-Object {
            $_.type -eq "page" -and $_.url -like "https://web.whatsapp.com*" -and $_.webSocketDebuggerUrl
        } | Select-Object -First 1
        return $target
    } catch {
        return $null
    }
}

try {
    if (-not (Test-Path $ConfigPath)) { throw "Missing config.json" }
    if (-not (Test-Path $UiPath)) { throw "Missing ui.js" }

    $script:config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    $configuredMaxBytes = [int64]$script:config.MaxRecordingBytes
    if ($configuredMaxBytes -ge 1048576 -and $configuredMaxBytes -le 536870912) {
        $script:maxRecordingBytes = $configuredMaxBytes
    }
    $script:ffmpeg = Find-FFmpeg
    if (-not $script:ffmpeg) { throw "ffmpeg.exe not found. Run INSTALLA.cmd again." }
    Write-Log "Helper started pid=$PID ffmpeg=$script:ffmpeg"

    if (-not (Test-WajsBundle $WajsPath)) {
        Write-Log "WA-JS bundle missing or invalid; downloading tested v$WajsVersion"
        if (-not (Download-Wajs)) { throw "Unable to download WA-JS" }
    }

    while ($true) {
        $target = $null
        while (-not $target) {
            $target = Get-WhatsAppTarget ([int]$script:config.DebugPort)
            if (-not $target) { Start-Sleep -Seconds 2 }
        }

        Write-Log "WhatsApp CDP target found"
        $script:ws = [System.Net.WebSockets.ClientWebSocket]::new()

        try {
            $uri = [Uri]$target.webSocketDebuggerUrl
            $script:ws.ConnectAsync($uri, [System.Threading.CancellationToken]::None).GetAwaiter().GetResult()
            Write-Log "CDP WebSocket connected"
            Initialize-Page

            while ($script:ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                $msg = Receive-CdpObject
                if ($null -eq $msg) { break }
                Handle-CdpEvent $msg
            }
        } catch {
            Write-Log "CDP session error: $($_.Exception.Message)"
        } finally {
            foreach ($key in @($script:uploads.Keys)) {
                try { $script:uploads[$key].Stream.Dispose() } catch {}
                try { Remove-Item $script:uploads[$key].WebmPath -Force -ErrorAction SilentlyContinue } catch {}
                try { Remove-Item $script:uploads[$key].M4aPath -Force -ErrorAction SilentlyContinue } catch {}
            }
            $script:uploads = @{}
            try { $script:ws.Dispose() } catch {}
            $script:ws = $null
        }

        Start-Sleep -Seconds 2
    }
} catch {
    Write-Log "FATAL: $($_.Exception.Message)"
} finally {
    Remove-Item $PidPath -Force -ErrorAction SilentlyContinue
    try { $lockStream.Dispose() } catch {}
}
