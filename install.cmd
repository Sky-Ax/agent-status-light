@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bin\install.ps1" -Interactive
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
  echo Done.
) else (
  echo Failed with exit code %EXIT_CODE%.
)
pause
exit /b %EXIT_CODE%
