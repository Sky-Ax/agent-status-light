@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0bin\install.ps1" -Check
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
  echo Check passed.
) else (
  echo Check failed with exit code %EXIT_CODE%.
)
pause
exit /b %EXIT_CODE%
