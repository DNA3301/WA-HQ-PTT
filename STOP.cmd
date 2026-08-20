@echo off
setlocal
set "APP=%LOCALAPPDATA%\WA-HQ-PTT"

if not exist "%APP%\stop.ps1" (
  echo WA-HQ-PTT is not installed.
  pause
  exit /b 1
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%APP%\stop.ps1"
set "RESULT=%ERRORLEVEL%"
timeout /t 2 >nul
exit /b %RESULT%
