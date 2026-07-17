@echo off
setlocal
cd /d "%~dp0"
title Recolector de Inventario TI

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0Bootstrap.ps1"

endlocal
