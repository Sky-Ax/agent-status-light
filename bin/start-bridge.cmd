@echo off
setlocal

set "BIN_DIR=%~dp0"
for %%I in ("%BIN_DIR%..") do set "ROOT_DIR=%%~fI"
set "BRIDGE_EXE=%BIN_DIR%ai-hook-bridge.exe"

if not exist "%BRIDGE_EXE%" (
  echo ERROR: missing bridge executable: %BRIDGE_EXE%
  echo Build it with: go build -o "%BRIDGE_EXE%" "%ROOT_DIR%\bridge"
  pause
  exit /b 1
)

"%BRIDGE_EXE%" -status "%ROOT_DIR%\data\codex-status.json" %*
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if "%EXIT_CODE%"=="0" (
  echo Bridge stopped.
) else (
  echo Bridge failed with exit code %EXIT_CODE%.
)
pause
exit /b %EXIT_CODE%
