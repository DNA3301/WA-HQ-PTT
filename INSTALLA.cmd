@echo off
setlocal
chcp 65001 >nul
set "SCRIPT=%~dp0scripts\install.ps1"

if not exist "%SCRIPT%" (
  echo ERROR: scripts\install.ps1 was not found.
  echo Extract the complete release ZIP and try again.
  echo.
  pause
  exit /b 1
)

"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "RESULT=%ERRORLEVEL%"
echo.
if not "%RESULT%"=="0" echo Installation failed. Read the message above, then try again.
pause
exit /b %RESULT%
