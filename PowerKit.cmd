@echo off
rem Launches PowerKit without leaving a console window open.
start "" powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0PowerKit.ps1"
exit /b 0
