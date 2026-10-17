@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
if not exist "%~dp0files\Launch.ps1" (
  echo Please extract the ENTIRE ZIP first, then open START from the extracted folder.
  echo Сначала распакуйте ВЕСЬ ZIP-архив, затем откройте START из распакованной папки.
  pause
  exit /b 1
)
set "VOICEFIX_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "VOICEFIX_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
"%VOICEFIX_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0files\Launch.ps1"
endlocal