@echo off
start "" /B powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0dll-icon-viewer.ps1" >nul 2>&1
