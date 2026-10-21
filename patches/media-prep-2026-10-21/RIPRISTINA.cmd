@echo off
setlocal
chcp 65001 >nul
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Correggi-WAJS.ps1" -Restore
set "RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %RESULT%
