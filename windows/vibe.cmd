@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0vibe.windows.ps1" %*
exit /b %ERRORLEVEL%
