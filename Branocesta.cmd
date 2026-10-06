@echo off
rem Spusti Branocestu bez instalace. Zastupce s ikonou vytvori install.cmd.
start "" conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Branocesta.ps1"
