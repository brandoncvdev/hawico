@echo off
setlocal EnableExtensions
set "BASE=%~dp0"
cd /d "%BASE%"
title Diagnostico - Recolector de Inventario TI

echo.
echo Ruta del proyecto:
echo %BASE%
echo.

if not exist "%BASE%Bootstrap.ps1" (
    echo ERROR: No se encontro Bootstrap.ps1
    echo Ruta esperada:
    echo %BASE%Bootstrap.ps1
    echo.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -NoExit -File "%BASE%Bootstrap.ps1"

echo.
echo PowerShell termino con codigo %errorlevel%.
pause
endlocal
