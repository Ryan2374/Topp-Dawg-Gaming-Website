@echo off
setlocal
cd /d "%~dp0"
echo TOPP DAWG GAMING - SHOPPING CONNECTIVITY DIAGNOSTIC
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnose_shopping.ps1"
echo.
pause
