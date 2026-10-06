@echo off
rem Vytvori zastupce "Branocesta" s ikonou v nabidce Start, na plose a v teto slozce.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Branocesta.ps1" -Install
pause
