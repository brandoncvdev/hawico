@echo off
setlocal EnableExtensions
set "BASE=%~dp0"
cd /d "%BASE%"
title Recolector de Inventario TI

if not exist "%BASE%Bootstrap.ps1" (
    echo.
    echo ERROR: No se encontro Bootstrap.ps1
    echo Ruta esperada:
    echo %BASE%Bootstrap.ps1
    echo.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "%BASE%Bootstrap.ps1"

endlocal
