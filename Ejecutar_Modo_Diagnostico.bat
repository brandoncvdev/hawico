@echo off
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -Command ^
  "try { & '.\Bootstrap.ps1' } catch { Write-Host $_ -ForegroundColor Red }"
