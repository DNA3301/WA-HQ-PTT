@echo off
setlocal
chcp 65001 >nul
set "APP=%LOCALAPPDATA%\WA-HQ-PTT"
set "SCRIPT=%APP%\uninstall.ps1"

if not exist "%SCRIPT%" set "SCRIPT=%~dp0scripts\uninstall.ps1"
if not exist "%SCRIPT%" (
  echo ERROR: uninstall.ps1 was not found.
  pause
  exit /b 1
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %RESULT%
