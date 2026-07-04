@echo off
setlocal

set "BIN_DIR=%~dp0"
for %%I in ("%BIN_DIR%..") do set "ROOT_DIR=%%~fI"
set "DATA_DIR=%ROOT_DIR%\data"
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%"

where node >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  set "NODE_EXE=node"
) else (
  echo %DATE% %TIME% node-not-found >> "%DATA_DIR%\codex-hook-wrapper.log"
  exit /b 1
)

echo %DATE% %TIME% hook-wrapper-start >> "%DATA_DIR%\codex-hook-wrapper.log"
"%NODE_EXE%" "%BIN_DIR%codex-hook.js"
set "EXIT_CODE=%ERRORLEVEL%"
echo %DATE% %TIME% hook-wrapper-exit %EXIT_CODE% >> "%DATA_DIR%\codex-hook-wrapper.log"

exit /b %EXIT_CODE%
