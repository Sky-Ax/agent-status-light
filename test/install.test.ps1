$ErrorActionPreference = "Stop"

$TestDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $TestDir
$InstallScript = Join-Path $Root "bin\install.ps1"
$Temp = Join-Path ([IO.Path]::GetTempPath()) ("codex-hook-install-" + [guid]::NewGuid())

function Run-Install {
  param([string[]]$ScriptArgs)

  $result = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $InstallScript @ScriptArgs 2>&1
  return @{
    Code = $LASTEXITCODE
    Output = ($result -join "`n")
  }
}

try {
  New-Item -ItemType Directory -Path $Temp | Out-Null

  $checkBefore = Run-Install -ScriptArgs @("-Check", "-CodexHome", $Temp)
  if ($checkBefore.Code -eq 0) {
    throw "Check should fail before hooks are installed."
  }

  $install = Run-Install -ScriptArgs @("-Install", "-CodexHome", $Temp)
  if ($install.Code -ne 0) {
    throw "Install failed: $($install.Output)"
  }

  $hooksPath = Join-Path $Temp "hooks.json"
  if (!(Test-Path -LiteralPath $hooksPath)) {
    throw "hooks.json was not created."
  }

  $hooks = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($event in "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop") {
    $commands = @($hooks.hooks.$event | ForEach-Object { $_.hooks } | ForEach-Object { $_.command })
    if ($commands -notcontains (Join-Path $Root "bin\codex-hook.cmd")) {
      throw "Missing hook command for $event."
    }
  }

  $checkAfter = Run-Install -ScriptArgs @("-Check", "-CodexHome", $Temp)
  if ($checkAfter.Code -ne 0) {
    throw "Check should pass after install: $($checkAfter.Output)"
  }

  $uninstall = Run-Install -ScriptArgs @("-Uninstall", "-CodexHome", $Temp)
  if ($uninstall.Code -ne 0) {
    throw "Uninstall failed: $($uninstall.Output)"
  }

  $hooks = Get-Content -LiteralPath $hooksPath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($event in "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop") {
    $commands = @($hooks.hooks.$event | ForEach-Object { $_.hooks } | ForEach-Object { $_.command })
    if ($commands -contains (Join-Path $Root "bin\codex-hook.cmd")) {
      throw "Hook command still exists for $event after uninstall."
    }
  }
} finally {
  Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
