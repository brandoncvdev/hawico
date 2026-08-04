@echo off
powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%~dp0Bootstrap.ps1"
if errorlevel 1 pause
