@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
title Scam With Your Friends - Voice Fix
set "VOICEFIX_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "VOICEFIX_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%VOICEFIX_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0files\Fix.ps1" -Action Undo
echo.
echo Press any key to close this window...
pause >nul
endlocal