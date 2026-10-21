param(
    [switch]$Restore,
    [switch]$CheckOnly,
    [switch]$NoRestart,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA "WA-HQ-PTT")
)

$ErrorActionPreference = "Stop"
$FixId = "media-prep-4.7.1-20261021"
$WajsVersion = "4.7.1"
$ExpectedHash = "ED4CC6B17CE18D726B0BD89C0B30021C5B8266F823F13509C08170B7ACE96126"
$ExpectedLicenseHash = "5A2448A164170355F95E2E7C7A88B48C73EC7FE2DD07162D4A201F2B06257525"
$AppDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd([IO.Path]::DirectorySeparatorChar)
$BackupDir = Join-Path $AppDir "compat-backups\$FixId"
$ManifestPath = Join-Path $BackupDir "manifest.json"
$Names = @("start.ps1", "update-wajs.ps1", "wppconnect-wa.js", "wppconnect-wa.js.LICENSE.txt")
$stage = $null
$stopped = $false
$modified = $false

function Read-Utf8([string]$Path) {
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
}

function Write-Utf8([string]$Path, [string]$Content) {
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function Get-Hash([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Assert-Script([string]$Text, [string]$Label) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Sintassi non valida in ${Label}: $($errors[0].Message)" }
}

function Replace-One([string]$Text, [string]$Old, [string]$New) {
    $index = $Text.IndexOf($Old, [StringComparison]::Ordinal)
    if ($index -lt 0 -or $Text.IndexOf($Old, $index + $Old.Length, [StringComparison]::Ordinal) -ge 0) {
        throw "Installazione diversa da quella supportata. Nessun file e' stato sostituito."
    }
    return $Text.Substring(0, $index) + $New + $Text.Substring($index + $Old.Length)
}

function Download-Verified([string[]]$Urls, [string]$Destination, [string]$Hash) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    foreach ($url in $Urls) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Destination -TimeoutSec 45
            if ((Get-Hash $Destination) -ne $Hash) { throw "SHA-256 non corrispondente" }
            return
        } catch {
            Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        }
    }
    throw "Download non riuscito o integrita' non verificata. Controlla Internet e riprova."
}

function Stop-Helper {
    $pidPath = Join-Path $AppDir "helper.pid"
    if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) { return }
    $helperId = 0
    if (-not [int]::TryParse((Read-Utf8 $pidPath).Trim(), [ref]$helperId)) {
        throw "helper.pid non valido. Chiudi il helper e riprova."
    }
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $helperId" -ErrorAction Stop
    if (-not $process) { return }
    $startPath = Join-Path $AppDir "start.ps1"
    if ($process.Name -notmatch "^(powershell|pwsh)(\.exe)?$" -or
        $process.CommandLine.IndexOf($startPath, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
        throw "Il processo nel PID file non corrisponde al helper. Nessun processo e' stato terminato."
    }
    Stop-Process -Id $helperId -Force -ErrorAction Stop
    Wait-Process -Id $helperId -Timeout 10 -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
}

function Start-Helper {
    if ($NoRestart) { return }
    $launcher = Join-Path $AppDir "launch-hidden.vbs"
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        throw "Launcher assente. I file sono corretti; usa AVVIA.cmd dopo la riparazione dell'installazione."
    }
    Start-Process -FilePath (Join-Path $env:WINDIR "System32\wscript.exe") -ArgumentList ('"' + $launcher + '"') -WindowStyle Hidden
}

function Assert-Backup {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Backup originale non disponibile." }
    $manifest = Read-Utf8 $ManifestPath | ConvertFrom-Json
    if ($manifest.FixId -ne $FixId) { throw "Backup non riconosciuto." }
    if (@($manifest.Files).Count -ne $Names.Count) { throw "Backup incompleto." }
    foreach ($name in $Names) {
        $entry = @($manifest.Files | Where-Object { $_.Name -eq $name })
        if ($entry.Count -ne 1) { throw "Backup non valido: $name" }
        if ($entry[0].Exists) {
            $path = Join-Path $BackupDir $name
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Hash $path) -ne $entry[0].Hash) {
                throw "Backup danneggiato: $name. Ripristino interrotto."
            }
        }
    }
    return $manifest
}

function Restore-Backup {
    $manifest = Assert-Backup
    foreach ($entry in $manifest.Files) {
        $destination = Join-Path $AppDir $entry.Name
        if ($entry.Exists) {
            Copy-Item -LiteralPath (Join-Path $BackupDir $entry.Name) -Destination $destination -Force
        } else {
            Remove-Item -LiteralPath $destination -Force -ErrorAction SilentlyContinue
        }
    }
}

try {
    Write-Host "WA-HQ-PTT - correzione invio audio / MediaPrep" -ForegroundColor Cyan
    if ([IO.Path]::GetFileName($AppDir) -ne "WA-HQ-PTT") { throw "Cartella di installazione non valida." }
    foreach ($name in @("start.ps1", "start.core.ps1", "ui.js", "update-wajs.ps1")) {
        if (-not (Test-Path -LiteralPath (Join-Path $AppDir $name) -PathType Leaf)) {
            throw "Questa patch richiede la versione locale WA-HQ-PTT 2.0.2 con start.core.ps1. File mancante: $name"
        }
    }

    if ($Restore) {
        [void](Assert-Backup)
        if ($CheckOnly) { Write-Host "Backup verificato: ripristino disponibile."; exit 0 }
        Stop-Helper
        $stopped = $true
        Restore-Backup
        Start-Helper
        $stopped = $false
        Write-Host "Backup ripristinato. Chiudi COMPLETAMENTE WhatsApp e riaprilo." -ForegroundColor Green
        exit 0
    }

    $uiPath = Join-Path $AppDir "ui.js"
    $corePath = Join-Path $AppDir "start.core.ps1"
    $uiHash = Get-Hash $uiPath
    $coreHash = Get-Hash $corePath
    $ui = Read-Utf8 $uiPath
    if (-not $ui.Contains('const VERSION = "2.0.2";') -or -not $ui.Contains('audio/ogg; codecs=opus')) {
        throw "Runtime audio non riconosciuto. La patch non modifica codec, recorder o interfaccia."
    }

    $startPath = Join-Path $AppDir "start.ps1"
    $updaterPath = Join-Path $AppDir "update-wajs.ps1"
    $start = Read-Utf8 $startPath
    $updater = Read-Utf8 $updaterPath
    if ($start.Contains("# Compatibility fix: $FixId")) {
        if (-not $updater.Contains('$WajsVersion = "4.7.1"') -or -not $updater.Contains($ExpectedHash)) {
            throw "Patch parziale: updater diverso da quello previsto. Usa RIPRISTINA.cmd e riprova."
        }
        $newStart = $start
        $newUpdater = $updater
    } else {
        $begin = $start.IndexOf("    # iOS isolation test:", [StringComparison]::Ordinal)
        $end = $start.IndexOf('    $core = Replace-Once $core ''@(".webm", ".m4a")''', [StringComparison]::Ordinal)
        if ($begin -lt 0 -or $end -le $begin) { throw "Bootstrap non riconosciuto. Nessun file modificato." }
        $oldBlock = $start.Substring($begin, $end - $begin)
        if (-not $oldBlock.Contains("4.6.1-alpha.0-nightly-2026-09-24") -or -not $oldBlock.Contains("624F910B6A360C8B34C8962C82826E5539765F4AC0BA427D351D224DE29BFDEC")) {
            throw "Versione del bootstrap non supportata. Nessun file modificato."
        }
        $replacement = @'
    # Compatibility fix: media-prep-4.7.1-20261021
    # WhatsApp split prepRawMedia into a separate module; WA-JS 4.7.1 handles it.
    $core = Replace-Once $core '$WajsVersion = "4.6.0"' '$WajsVersion = "4.7.1"' "wajs-version"
    $core = Replace-Once $core '$ExpectedWajsSha256 = "5BFB88027F14A4D8C9E319374E8BB4083201906881CF8C74F75789B32E4106BD"' '$ExpectedWajsSha256 = "ED4CC6B17CE18D726B0BD89C0B30021C5B8266F823F13509C08170B7ACE96126"' "wajs-sha256"
    Write-BootstrapLog "MediaPrep fix: WA-JS 4.7.1 SHA-256 pinned; existing HQ audio/UI retained"


'@
        $newStart = $start.Substring(0, $begin) + $replacement + $start.Substring($end)
        $newStart = Replace-One $newStart 'Starting HQ runtime with isolated WA-JS nightly iOS test (128k default, 48 kHz mono)' 'Starting HQ runtime with WA-JS 4.7.1 (existing HQ Opus profile)'
        if ($updater.Contains('$WajsVersion = "4.6.0"')) {
            $newUpdater = Replace-One $updater '$WajsVersion = "4.6.0"' '$WajsVersion = "4.7.1"'
            $newUpdater = Replace-One $newUpdater '$ExpectedSha256 = "5BFB88027F14A4D8C9E319374E8BB4083201906881CF8C74F75789B32E4106BD"' ('$ExpectedSha256 = "' + $ExpectedHash + '"')
        } elseif ($updater.Contains('$WajsVersion = "4.6.1-alpha.0-nightly-2026-09-24"')) {
            $newUpdater = Replace-One $updater '$WajsVersion = "4.6.1-alpha.0-nightly-2026-09-24"' '$WajsVersion = "4.7.1"'
            $newUpdater = Replace-One $newUpdater '$ExpectedSha256 = "624F910B6A360C8B34C8962C82826E5539765F4AC0BA427D351D224DE29BFDEC"' ('$ExpectedSha256 = "' + $ExpectedHash + '"')
            $newUpdater = Replace-One $newUpdater '"https://github.com/wppconnect-team/wa-js/releases/download/nightly/wppconnect-wa.js"' '"https://github.com/wppconnect-team/wa-js/releases/download/v$WajsVersion/wppconnect-wa.js"'
            $newUpdater = Replace-One $newUpdater '"https://raw.githubusercontent.com/wppconnect-team/wa-js/744e3d809f046059744f3cee035eed2bc516d6cd/LICENSE"' '"https://cdn.jsdelivr.net/npm/@wppconnect/wa-js@$WajsVersion/dist/wppconnect-wa.js.LICENSE.txt"'
        } else {
            throw "Updater non riconosciuto. Nessun file modificato."
        }
    }

    Assert-Script $newStart "start.ps1"
    Assert-Script $newUpdater "update-wajs.ps1"
    if ($CheckOnly) {
        Write-Host "Installazione compatibile. Bootstrap e updater corretti superano il controllo sintattico." -ForegroundColor Green
        Write-Host "Nessun file modificato."
        exit 0
    }

    $stage = Join-Path ([IO.Path]::GetTempPath()) ("WAHQ-send-fix-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $stage | Out-Null
    Write-Host "Scarico WA-JS 4.7.1 e verifico SHA-256..."
    Download-Verified @(
        "https://github.com/wppconnect-team/wa-js/releases/download/v4.7.1/wppconnect-wa.js",
        "https://cdn.jsdelivr.net/npm/@wppconnect/wa-js@4.7.1/dist/wppconnect-wa.js",
        "https://unpkg.com/@wppconnect/wa-js@4.7.1/dist/wppconnect-wa.js"
    ) (Join-Path $stage "wppconnect-wa.js") $ExpectedHash
    Download-Verified @(
        "https://cdn.jsdelivr.net/npm/@wppconnect/wa-js@4.7.1/dist/wppconnect-wa.js.LICENSE.txt",
        "https://unpkg.com/@wppconnect/wa-js@4.7.1/dist/wppconnect-wa.js.LICENSE.txt"
    ) (Join-Path $stage "wppconnect-wa.js.LICENSE.txt") $ExpectedLicenseHash
    $bundle = Read-Utf8 (Join-Path $stage "wppconnect-wa.js")
    if (-not $bundle.Contains("wppconnect-team/wa-js v4.7.1")) { throw "Versione bundle non valida." }
    Write-Utf8 (Join-Path $stage "start.ps1") $newStart
    Write-Utf8 (Join-Path $stage "update-wajs.ps1") $newUpdater

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        if (Test-Path -LiteralPath $BackupDir) { throw "Backup incompleto gia' presente. Nessun file installato e' stato modificato." }
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
        $entries = @()
        foreach ($name in $Names) {
            $path = Join-Path $AppDir $name
            $exists = Test-Path -LiteralPath $path -PathType Leaf
            $hash = $null
            if ($exists) {
                Copy-Item -LiteralPath $path -Destination (Join-Path $BackupDir $name)
                $hash = Get-Hash $path
            }
            $entries += @{ Name = $name; Exists = $exists; Hash = $hash }
        }
        Write-Utf8 $ManifestPath (@{ FixId = $FixId; Files = $entries } | ConvertTo-Json -Depth 5)
    }
    [void](Assert-Backup)

    Stop-Helper
    $stopped = $true
    $modified = $true
    foreach ($name in $Names) {
        Copy-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $AppDir $name) -Force
    }
    if ((Get-Hash (Join-Path $AppDir "wppconnect-wa.js")) -ne $ExpectedHash) { throw "Verifica finale bundle fallita." }
    if ((Get-Hash $uiPath) -ne $uiHash -or (Get-Hash $corePath) -ne $coreHash) { throw "Verifica runtime audio fallita." }
    $modified = $false
    Start-Helper
    $stopped = $false
    Write-Host "Correzione applicata: WA-JS 4.7.1 verificata, bootstrap e updater aggiornati." -ForegroundColor Green
    Write-Host "IMPORTANTE: chiudi COMPLETAMENTE WhatsApp Beta e riaprilo."
    Write-Host "La finestra gia' aperta mantiene la vecchia WA-JS fino al riavvio."
    Write-Host "Recorder, codec, bitrate, cancel e configurazione audio sono invariati."
    Write-Host "Per tornare ai file precedenti usa RIPRISTINA.cmd."
} catch {
    $message = $_.Exception.Message
    if ($modified) {
        try { Restore-Backup; $modified = $false; Write-Host "File originali ripristinati automaticamente." }
        catch { Write-Host "Ripristino automatico non riuscito. Conserva il backup e usa RIPRISTINA.cmd." -ForegroundColor Red }
    }
    if ($stopped -and -not $modified) {
        try { Start-Helper } catch {}
    }
    Write-Host "ERRORE: $message" -ForegroundColor Red
    exit 1
} finally {
    if ($stage -and (Test-Path -LiteralPath $stage -PathType Container)) {
        $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $fullStage = [IO.Path]::GetFullPath($stage)
        if ($fullStage.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($fullStage).StartsWith("WAHQ-send-fix-")) {
            Remove-Item -LiteralPath $fullStage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

exit 0
