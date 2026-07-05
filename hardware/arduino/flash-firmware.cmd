@echo off
setlocal EnableExtensions

set "SCRIPT=%~dp0flash-firmware.ps1"

if not exist "%SCRIPT%" (
  echo ERROR: missing firmware flasher: %SCRIPT%
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
  echo Firmware flasher exited with code %EXIT_CODE%.
)
pause
exit /b %EXIT_CODE%
