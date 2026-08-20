$ErrorActionPreference = "Stop"

$AppDir = Join-Path $env:LOCALAPPDATA "WA-HQ-PTT"
$BackupPath = Join-Path $AppDir "registry-backup.json"
$StartupDir = [Environment]::GetFolderPath("Startup")
$StartupLink = Join-Path $StartupDir "WA HQ PTT.lnk"
$RegPath = "HKCU:\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments"
$RegName = "WhatsApp.Root.exe"

function Remove-WaHqDebugArguments {
    $current = ""
    try {
        $item = Get-ItemProperty -Path $RegPath -Name $RegName -ErrorAction Stop
        $current = [string]$item.PSObject.Properties[$RegName].Value
    } catch {
        return
    }

    $current = $current -replace "--remote-debugging-port(?:=|\s+)\S+", ""
    $current = $current -replace "--remote-debugging-address(?:=|\s+)\S+", ""
    $current = ($current -replace "\s+", " ").Trim()

    if ($current) {
        New-ItemProperty -Path $RegPath -Name $RegName -Value $current -PropertyType String -Force | Out-Null
    } else {
        Remove-ItemProperty -Path $RegPath -Name $RegName -ErrorAction SilentlyContinue
    }
}

try {
    Write-Host "WA-HQ-PTT - UNINSTALL"
    Write-Host "====================="

    $stopScript = Join-Path $AppDir "stop.ps1"
    if (Test-Path -LiteralPath $stopScript) {
        & $stopScript -Quiet
        Start-Sleep -Milliseconds 600
    }

    Remove-Item -LiteralPath $StartupLink -Force -ErrorAction SilentlyContinue

    $restored = $false
    if (Test-Path -LiteralPath $BackupPath) {
        try {
            $backup = Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json
            New-Item -Path $RegPath -Force | Out-Null
            if ([bool]$backup.HadValue) {
                New-ItemProperty -Path $RegPath -Name $RegName -Value ([string]$backup.Value) -PropertyType String -Force | Out-Null
            } else {
                Remove-ItemProperty -Path $RegPath -Name $RegName -ErrorAction SilentlyContinue
            }
            $restored = $true
            Write-Host "The original WebView2 registry value was restored."
        } catch {
            Write-Host "WARNING: The backup could not be read; removing only WA-HQ-PTT debugging arguments."
        }
    }

    if (-not $restored) {
        Remove-WaHqDebugArguments
    }

    $expectedAppDir = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA "WA-HQ-PTT"))
    $resolvedAppDir = [System.IO.Path]::GetFullPath($AppDir)
    if ($resolvedAppDir -ne $expectedAppDir) {
        throw "Refusing to remove an unexpected path: $resolvedAppDir"
    }

    if (Test-Path -LiteralPath $resolvedAppDir) {
        Remove-Item -LiteralPath $resolvedAppDir -Recurse -Force
    }

    Write-Host ""
    Write-Host "Uninstallation complete." -ForegroundColor Green
    Write-Host "WhatsApp data and the WhatsApp user profile were not modified or deleted."
    Write-Host "FFmpeg was left installed because other applications may use it."
    Write-Host "Completely restart WhatsApp Desktop."
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

exit 0
