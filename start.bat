@echo off
rem One-click start: hub + game. See tools\start.ps1.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0tools\start.ps1" %*
