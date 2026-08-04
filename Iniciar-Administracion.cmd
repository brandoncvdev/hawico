@echo off
powershell.exe -NoLogo -ExecutionPolicy Bypass -File "%~dp0Start-Administration.ps1"
if errorlevel 1 pause
