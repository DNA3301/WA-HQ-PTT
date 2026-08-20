$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PackageDir = Split-Path -Parent $ScriptDir
$AppDir = Join-Path $env:LOCALAPPDATA "WA-HQ-PTT"
$ConfigPath = Join-Path $AppDir "config.json"
$BackupPath = Join-Path $AppDir "registry-backup.json"
$StartupDir = [Environment]::GetFolderPath("Startup")
$StartupLink = Join-Path $StartupDir "WA HQ PTT.lnk"
$RegPath = "HKCU:\Software\Policies\Microsoft\Edge\WebView2\AdditionalBrowserArguments"
$RegName = "WhatsApp.Root.exe"

$SourceFiles = @{
    Start = Join-Path $ScriptDir "start.ps1"
    Stop = Join-Path $ScriptDir "stop.ps1"
    Update = Join-Path $ScriptDir "update-wajs.ps1"
    Uninstall = Join-Path $ScriptDir "uninstall.ps1"
    Ui = Join-Path $PackageDir "src\ui.js"
    Config = Join-Path $PackageDir "config\config.default.json"
}

function Find-FFmpeg {
    $command = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $roots = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"),
        "C:\ffmpeg",
        (Join-Path $env:ProgramFiles "ffmpeg")
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    foreach ($root in $roots) {
        try {
            $match = Get-ChildItem -LiteralPath $root -Filter ffmpeg.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($match) { return $match.FullName }
        } catch {}
    }

    return $null
}

function Test-FFmpeg([string]$Path) {
    if (-not $Path) { return $false }
    try {
        & $Path -version *> $null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Merge-DefaultConfig([string]$DefaultPath, [string]$UserPath) {
    $defaults = Get-Content -LiteralPath $DefaultPath -Raw | ConvertFrom-Json

    if (-not (Test-Path -LiteralPath $UserPath)) {
        Copy-Item -LiteralPath $DefaultPath -Destination $UserPath -Force
        return
    }

    try {
        $userConfig = Get-Content -LiteralPath $UserPath -Raw | ConvertFrom-Json
    } catch {
        throw "The existing config.json is invalid. Fix or remove it, then run the installer again."
    }

    $changed = $false
    foreach ($property in $defaults.PSObject.Properties) {
        if ($userConfig.PSObject.Properties.Name -notcontains $property.Name) {
            $userConfig | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
            $changed = $true
        }
    }

    if ($changed) {
        $userConfig | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $UserPath -Encoding UTF8
    }
}

try {
    Write-Host ""
    Write-Host "WA-HQ-PTT v2.0.1 - INSTALLATION"
    Write-Host "================================"
    Write-Host ""

    foreach ($entry in $SourceFiles.GetEnumerator()) {
        if (-not (Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
            throw "Required package file missing: $($entry.Value). Extract the complete ZIP and try again."
        }
    }

    $ffmpeg = Find-FFmpeg
    if (-not (Test-FFmpeg $ffmpeg)) {
        Write-Host "FFmpeg was not found. Attempting installation with winget..."
        $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
        if (-not $winget) {
            throw "FFmpeg is required, but winget is unavailable. Install FFmpeg manually, add ffmpeg.exe to PATH, and run INSTALLA.cmd again."
        }

        & $winget.Source install --id Gyan.FFmpeg -e --accept-package-agreements --accept-source-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "winget could not install FFmpeg (exit code $LASTEXITCODE). Install FFmpeg manually and run INSTALLA.cmd again."
        }

        $ffmpeg = Find-FFmpeg
        if (-not (Test-FFmpeg $ffmpeg)) {
            throw "FFmpeg was installed but is not discoverable yet. Open a new Windows session or terminal, then run INSTALLA.cmd again."
        }
    }
    Write-Host "FFmpeg verified: $ffmpeg"

    New-Item -ItemType Directory -Force -Path $AppDir | Out-Null

    Copy-Item -LiteralPath $SourceFiles.Start -Destination (Join-Path $AppDir "start.ps1") -Force
    Copy-Item -LiteralPath $SourceFiles.Stop -Destination (Join-Path $AppDir "stop.ps1") -Force
    Copy-Item -LiteralPath $SourceFiles.Update -Destination (Join-Path $AppDir "update-wajs.ps1") -Force
    Copy-Item -LiteralPath $SourceFiles.Uninstall -Destination (Join-Path $AppDir "uninstall.ps1") -Force
    Copy-Item -LiteralPath $SourceFiles.Ui -Destination (Join-Path $AppDir "ui.js") -Force
    Copy-Item -LiteralPath $SourceFiles.Config -Destination (Join-Path $AppDir "config.default.json") -Force
    Merge-DefaultConfig $SourceFiles.Config $ConfigPath

    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    $debugPort = [int]$config.DebugPort
    if ($debugPort -lt 1024 -or $debugPort -gt 65535) {
        throw "DebugPort in config.json must be between 1024 and 65535."
    }

    $powershellExe = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
    & $powershellExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $AppDir "update-wajs.ps1") -NoRestart
    if ($LASTEXITCODE -ne 0) { throw "WA-JS installation failed." }

    if (-not (Test-Path -LiteralPath $BackupPath)) {
        $hadValue = $false
        $oldValue = $null
        try {
            $item = Get-ItemProperty -Path $RegPath -Name $RegName -ErrorAction Stop
            $oldValue = [string]$item.PSObject.Properties[$RegName].Value
            $hadValue = $true
        } catch {}

        @{ HadValue = $hadValue; Value = $oldValue } |
            ConvertTo-Json |
            Set-Content -LiteralPath $BackupPath -Encoding UTF8
    } else {
        try {
            Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json | Out-Null
        } catch {
            throw "The registry backup is damaged. It was not overwritten. Restore or remove $BackupPath only after reviewing it."
        }
    }

    New-Item -Path $RegPath -Force | Out-Null
    $current = ""
    try {
        $regItem = Get-ItemProperty -Path $RegPath -Name $RegName -ErrorAction Stop
        $current = [string]$regItem.PSObject.Properties[$RegName].Value
    } catch {}

    $current = $current -replace "--auto-open-devtools-for-tabs", ""
    $current = $current -replace "--remote-debugging-port(?:=|\s+)\S+", ""
    $current = $current -replace "--remote-debugging-address(?:=|\s+)\S+", ""
    $current = ($current -replace "\s+", " ").Trim()

    $debugArgs = "--remote-debugging-port=$debugPort --remote-debugging-address=127.0.0.1"
    $newArgs = if ($current) { "$current $debugArgs" } else { $debugArgs }
    New-ItemProperty -Path $RegPath -Name $RegName -Value $newArgs -PropertyType String -Force | Out-Null

    $launcher = Join-Path $AppDir "launch-hidden.vbs"
    $startPath = (Join-Path $AppDir "start.ps1").Replace('"', '""')
    $vbs = @"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$startPath""", 0, False
"@
    Set-Content -LiteralPath $launcher -Value $vbs -Encoding ASCII

    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($StartupLink)
    $shortcut.TargetPath = "$env:WINDIR\System32\wscript.exe"
    $shortcut.Arguments = '"' + $launcher + '"'
    $shortcut.WorkingDirectory = $AppDir
    $shortcut.Description = "WA-HQ-PTT helper"
    $shortcut.Save()

    & (Join-Path $AppDir "stop.ps1") -Quiet
    Start-Process "$env:WINDIR\System32\wscript.exe" -ArgumentList ('"' + $launcher + '"') -WindowStyle Hidden

    Write-Host ""
    Write-Host "INSTALLATION COMPLETE." -ForegroundColor Green
    Write-Host ""
    Write-Host "Completely quit WhatsApp Desktop, then reopen it."
    Write-Host "Use the normal WhatsApp microphone button to start and stop HQ recording."
    Write-Host "While recording, click the cancel button or press Escape to discard it."
    Write-Host "Log: $AppDir\logs\helper.log"
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

exit 0
