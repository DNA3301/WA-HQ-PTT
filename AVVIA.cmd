@echo off
setlocal
set "APP=%LOCALAPPDATA%\WA-HQ-PTT"

if not exist "%APP%\start.ps1" (
  echo WA-HQ-PTT is not installed. Run INSTALLA.cmd first.
  pause
  exit /b 1
)

start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%APP%\start.ps1"
echo WA-HQ-PTT helper start requested. Duplicate instances are prevented automatically.
timeout /t 2 >nul
exit /b 0
