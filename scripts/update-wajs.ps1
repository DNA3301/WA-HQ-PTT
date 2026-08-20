param(
    [switch]$NoRestart
)

$ErrorActionPreference = "Stop"
$AppDir = Join-Path $env:LOCALAPPDATA "WA-HQ-PTT"
$WajsPath = Join-Path $AppDir "wppconnect-wa.js"
$WajsLicensePath = Join-Path $AppDir "wppconnect-wa.js.LICENSE.txt"
$TempPath = "$WajsPath.download"
$TempLicensePath = "$WajsLicensePath.download"
$WajsVersion = "4.6.0"
$ExpectedSha256 = "5BFB88027F14A4D8C9E319374E8BB4083201906881CF8C74F75789B32E4106BD"

$BundleUrls = @(
    "https://cdn.jsdelivr.net/npm/@wppconnect/wa-js@$WajsVersion/dist/wppconnect-wa.js",
    "https://unpkg.com/@wppconnect/wa-js@$WajsVersion/dist/wppconnect-wa.js"
)

$LicenseUrls = @(
    "https://cdn.jsdelivr.net/npm/@wppconnect/wa-js@$WajsVersion/dist/wppconnect-wa.js.LICENSE.txt",
    "https://unpkg.com/@wppconnect/wa-js@$WajsVersion/dist/wppconnect-wa.js.LICENSE.txt"
)

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

    $actualHash = Get-Sha256 $Path
    if ($actualHash -ne $ExpectedSha256) { return $false }

    $contents = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    return $contents.StartsWith("/*! For license information") -and $contents.Contains("wppconnect-team/wa-js v$WajsVersion")
}

function Download-TestedWajs {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue

    $downloaded = $false
    foreach ($url in $BundleUrls) {
        try {
            Write-Host "Downloading WA-JS v$WajsVersion from $url"
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $TempPath -TimeoutSec 45
            if (-not (Test-WajsBundle $TempPath)) {
                throw "The downloaded bundle failed its version or SHA-256 verification."
            }

            Move-Item -LiteralPath $TempPath -Destination $WajsPath -Force
            $downloaded = $true
            break
        } catch {
            Write-Host "Download attempt failed: $($_.Exception.Message)"
            Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $downloaded) {
        throw "Unable to download and verify the tested WA-JS v$WajsVersion bundle. Check the internet connection and try again."
    }

    Remove-Item -LiteralPath $TempLicensePath -Force -ErrorAction SilentlyContinue
    foreach ($url in $LicenseUrls) {
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $TempLicensePath -TimeoutSec 30
            if ((Get-Item -LiteralPath $TempLicensePath).Length -gt 100) {
                Move-Item -LiteralPath $TempLicensePath -Destination $WajsLicensePath -Force
                break
            }
        } catch {
            Remove-Item -LiteralPath $TempLicensePath -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Host "WA-JS v$WajsVersion installed and SHA-256 verified."
}

try {
    if (-not (Test-Path -LiteralPath $AppDir -PathType Container)) {
        throw "WA-HQ-PTT is not installed. Run INSTALLA.cmd first."
    }

    Download-TestedWajs

    if (-not $NoRestart) {
        $stopScript = Join-Path $AppDir "stop.ps1"
        if (Test-Path -LiteralPath $stopScript) {
            & $stopScript -Quiet
        }

        $launcher = Join-Path $AppDir "launch-hidden.vbs"
        if (-not (Test-Path -LiteralPath $launcher)) {
            throw "The helper launcher is missing. Run INSTALLA.cmd to repair the installation."
        }

        Start-Process "$env:WINDIR\System32\wscript.exe" -ArgumentList ('"' + $launcher + '"') -WindowStyle Hidden
        Write-Host "Helper restarted. Completely restart WhatsApp Desktop if compatibility problems persist."
    }
} catch {
    Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $TempLicensePath -Force -ErrorAction SilentlyContinue
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

exit 0
