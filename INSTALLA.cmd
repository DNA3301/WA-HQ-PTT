@echo off
setlocal
chcp 65001 >nul
set "SCRIPT=%~dp0scripts\install.ps1"
set "CORE=%~dp0scripts\start.core.ps1"
set "APPDIR=%LOCALAPPDATA%\WA-HQ-PTT"

if not exist "%SCRIPT%" (
  echo ERROR: scripts\install.ps1 was not found.
  echo Extract the complete release ZIP and try again.
  echo.
  pause
  exit /b 1
)

if not exist "%CORE%" (
  echo ERROR: scripts\start.core.ps1 was not found.
  echo Extract the complete release ZIP and try again.
  echo.
  pause
  exit /b 1
)

if not exist "%APPDIR%" mkdir "%APPDIR%" >nul 2>&1
copy /Y "%CORE%" "%APPDIR%\start.core.ps1" >nul
if errorlevel 1 (
  echo ERROR: could not install scripts\start.core.ps1.
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
