param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$AppDir = Join-Path $env:LOCALAPPDATA "WA-HQ-PTT"
$PidPath = Join-Path $AppDir "helper.pid"

function Write-Status([string]$Message) {
    if (-not $Quiet) { Write-Host $Message }
}

if (-not (Test-Path -LiteralPath $PidPath)) {
    Write-Status "WA-HQ-PTT helper is not running."
    return
}

try {
    $helperPid = [int](Get-Content -LiteralPath $PidPath -Raw)
    $process = Get-CimInstance Win32_Process -Filter "ProcessId = $helperPid" -ErrorAction SilentlyContinue

    if ($process -and
        $process.Name -match "^(powershell|pwsh)(\.exe)?$" -and
        $process.CommandLine -match "(?i)WA-HQ-PTT[\\/]start\.ps1") {
        Stop-Process -Id $helperPid -Force -ErrorAction Stop
        Write-Status "WA-HQ-PTT helper stopped."
    } elseif ($process) {
        Write-Status "The saved process ID belongs to another program; it was not stopped."
    } else {
        Write-Status "WA-HQ-PTT helper was already stopped."
    }
} catch {
    throw "Unable to stop the helper: $($_.Exception.Message)"
} finally {
    Remove-Item -LiteralPath $PidPath -Force -ErrorAction SilentlyContinue
}

return
