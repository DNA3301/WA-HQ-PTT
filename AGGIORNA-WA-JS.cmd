@echo off
setlocal
chcp 65001 >nul
set "APP=%LOCALAPPDATA%\WA-HQ-PTT"

if not exist "%APP%\update-wajs.ps1" (
  echo WA-HQ-PTT is not installed. Run INSTALLA.cmd first.
  pause
  exit /b 1
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%APP%\update-wajs.ps1"
set "RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %RESULT%
