@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0capture-android-logs.ps1"
set "TOOL_EXIT_CODE=%ERRORLEVEL%"
exit /b %TOOL_EXIT_CODE%
