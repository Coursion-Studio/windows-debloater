@echo off
rem Debloater - a clean start for Windows 11. Double-click this file to open it.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0src\Debloater.ps1" %*
