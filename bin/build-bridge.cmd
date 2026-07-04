@echo off
setlocal

set "BIN_DIR=%~dp0"
for %%I in ("%BIN_DIR%..") do set "ROOT_DIR=%%~fI"
set "BRIDGE_DIR=%ROOT_DIR%\bridge"
set "BRIDGE_EXE=%BIN_DIR%ai-hook-bridge.exe"

where go >nul 2>nul
if not "%ERRORLEVEL%"=="0" (
  echo ERROR: go was not found in PATH.
  pause
  exit /b 1
)

pushd "%BRIDGE_DIR%" || exit /b 1
go mod tidy
if not "%ERRORLEVEL%"=="0" (
  popd
  pause
  exit /b 1
)

go build -o "%BRIDGE_EXE%" .
set "EXIT_CODE=%ERRORLEVEL%"
popd

echo.
if "%EXIT_CODE%"=="0" (
  echo Built: %BRIDGE_EXE%
) else (
  echo Build failed with exit code %EXIT_CODE%.
)
pause
exit /b %EXIT_CODE%
