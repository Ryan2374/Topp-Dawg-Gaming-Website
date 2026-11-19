@echo off
setlocal
cd /d "%~dp0"
echo ================================================
echo       TOPP DAWG GAMING - LOCAL PRICE TEST
echo              NO PYTHON REQUIRED
echo ================================================
echo.
set "POWERSHELL=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL%" (
  echo Windows PowerShell was not found. This launcher supports Windows 10/11.
  pause
  exit /b 1
)
"%POWERSHELL%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0local_price_server.ps1"
set "RESULT=%errorlevel%"
echo.
echo Local test stopped. Nothing was published online.
pause
exit /b %RESULT%
