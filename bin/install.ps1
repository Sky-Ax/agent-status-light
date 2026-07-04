param(
  [switch]$Check,
  [switch]$Install,
  [switch]$Uninstall,
  [switch]$Interactive,
  [string]$CodexHome = (Join-Path $env:USERPROFILE ".codex")
)

$ErrorActionPreference = "Stop"

$Events = @("UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Stop")
$BinDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $BinDir
$HookCommand = Join-Path $BinDir "codex-hook.cmd"
$HookScript = Join-Path $BinDir "codex-hook.js"
$BridgeExe = Join-Path $BinDir "ai-hook-bridge.exe"
$LegacyHookCommands = @(
  (Join-Path $Root "codex-hook.cmd")
)
$HooksPath = Join-Path $CodexHome "hooks.json"
$StatusMessage = "Recording Codex status"

function Count-Modes {
  $count = 0
  foreach ($value in @($Check, $Install, $Uninstall, $Interactive)) {
    if ($value) { $count++ }
  }
  return $count
}

function Add-Or-SetProperty {
  param($Object, [string]$Name, $Value)

  if ($Object.PSObject.Properties[$Name]) {
    $Object.$Name = $Value
  } else {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  }
}

function Read-HooksFile {
  if (!(Test-Path -LiteralPath $HooksPath)) {
    return [pscustomobject]@{ hooks = [pscustomobject]@{} }
  }

  $raw = Get-Content -LiteralPath $HooksPath -Raw -Encoding UTF8
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return [pscustomobject]@{ hooks = [pscustomobject]@{} }
  }

  $data = $raw | ConvertFrom-Json
  if (!$data.PSObject.Properties["hooks"]) {
    Add-Or-SetProperty $data "hooks" ([pscustomobject]@{})
  }
  return $data
}

function Write-Utf8NoBom {
  param([string]$Path, [string]$Text)

  $encoding = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Backup-HooksFile {
  if (Test-Path -LiteralPath $HooksPath) {
    $backup = "$HooksPath.bak-$(Get-Date -Format yyyyMMddHHmmss)"
    Copy-Item -LiteralPath $HooksPath -Destination $backup
    Write-Host "Backup: $backup"
  }
}

function Save-HooksFile {
  param($Data)

  if (!(Test-Path -LiteralPath $CodexHome)) {
    New-Item -ItemType Directory -Path $CodexHome | Out-Null
  }

  Backup-HooksFile
  $json = $Data | ConvertTo-Json -Depth 20
  Write-Utf8NoBom $HooksPath ($json + "`r`n")
}

function New-HookEntry {
  return [pscustomobject]@{
    type = "command"
    command = $HookCommand
    timeout = 5
    statusMessage = $StatusMessage
  }
}

function Ensure-EventGroup {
  param($Hooks, [string]$Event)

  if (!$Hooks.PSObject.Properties[$Event]) {
    Add-Or-SetProperty $Hooks $Event @([pscustomobject]@{ hooks = @() })
  }

  $groups = @($Hooks.$Event)
  if ($groups.Count -eq 0) {
    $groups = @([pscustomobject]@{ hooks = @() })
  }

  foreach ($group in $groups) {
    if (!$group.PSObject.Properties["hooks"]) {
      Add-Or-SetProperty $group "hooks" @()
    }
  }

  return $groups
}

function Remove-OurHookFromGroups {
  param($Groups)

  foreach ($group in $Groups) {
    $kept = @($group.hooks) | Where-Object {
      $command = $_.command
      if ($command -ieq $HookCommand) {
        return $false
      }

      foreach ($legacyCommand in $LegacyHookCommands) {
        if ($command -ieq $legacyCommand) {
          return $false
        }
      }

      return $true
    }
    Add-Or-SetProperty $group "hooks" @($kept)
  }
}

function Install-Hooks {
  $data = Read-HooksFile

  foreach ($event in $Events) {
    $groups = Ensure-EventGroup $data.hooks $event
    Remove-OurHookFromGroups $groups

    $items = @($groups[0].hooks)
    $items += New-HookEntry
    Add-Or-SetProperty $groups[0] "hooks" @($items)
    Add-Or-SetProperty $data.hooks $event @($groups)
  }

  Save-HooksFile $data
  Write-Host "Installed: $HookCommand"
}

function Uninstall-Hooks {
  $data = Read-HooksFile

  foreach ($event in $Events) {
    if ($data.hooks.PSObject.Properties[$event]) {
      $groups = @($data.hooks.$event)
      Remove-OurHookFromGroups $groups
      Add-Or-SetProperty $data.hooks $event @($groups)
    }
  }

  Save-HooksFile $data
  Write-Host "Uninstalled: $HookCommand"
}

function Test-HookInstalled {
  param($Data, [string]$Event)

  if (!$Data.hooks.PSObject.Properties[$Event]) {
    return $false
  }

  foreach ($group in @($Data.hooks.$Event)) {
    foreach ($hook in @($group.hooks)) {
      if ($hook.command -ieq $HookCommand) {
        return $true
      }
    }
  }

  return $false
}

function Check-Setup {
  $errors = @()
  $node = Get-Command node -ErrorAction SilentlyContinue

  if (!$node) {
    $errors += "node was not found in PATH."
  } else {
    $version = (& node -v 2>$null)
    Write-Host "Node: $version"
  }

  if (!(Test-Path -LiteralPath $HookCommand)) {
    $errors += "Missing hook command: $HookCommand"
  }

  if (!(Test-Path -LiteralPath $HookScript)) {
    $errors += "Missing hook script: $HookScript"
  }

  if (!(Test-Path -LiteralPath $BridgeExe)) {
    $errors += "Missing bridge executable: $BridgeExe"
  } else {
    Write-Host "Bridge: $BridgeExe"
  }

  if (!(Test-Path -LiteralPath $HooksPath)) {
    $errors += "Missing Codex hooks file: $HooksPath"
  } else {
    $data = Read-HooksFile
    foreach ($event in $Events) {
      if (!(Test-HookInstalled $data $event)) {
        $errors += "Missing $event hook."
      }
    }
  }

  if ($errors.Count -gt 0) {
    foreach ($errorText in $errors) {
      Write-Host "ERROR: $errorText"
    }
    return $false
  }

  Write-Host "OK: Codex status hook is installed."
  return $true
}

function Start-Interactive {
  Write-Host "Codex status hook installer"
  Write-Host "Hooks file: $HooksPath"
  Write-Host "Hook command: $HookCommand"

  $node = Get-Command node -ErrorAction SilentlyContinue
  if (!$node) {
    Write-Host "ERROR: node was not found in PATH."
    exit 1
  }

  $choice = Read-Host "Choose action: [I]nstall/update, [C]heck, [U]ninstall, [Q]uit"
  switch -Regex ($choice) {
    "^[Uu]" { Uninstall-Hooks; return }
    "^[Cc]" {
      if (Check-Setup) { exit 0 } else { exit 1 }
    }
    "^[Qq]" { return }
    default { Install-Hooks; return }
  }
}

$modeCount = Count-Modes
if ($modeCount -eq 0) {
  $Check = $true
} elseif ($modeCount -gt 1) {
  Write-Host "ERROR: use only one mode: -Check, -Install, -Uninstall, or -Interactive."
  exit 1
}

if ($Interactive) {
  Start-Interactive
  exit 0
}

if ($Install) {
  if (!(Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: node was not found in PATH."
    exit 1
  }
  Install-Hooks
  exit 0
}

if ($Uninstall) {
  Uninstall-Hooks
  exit 0
}

if ($Check) {
  if (Check-Setup) { exit 0 } else { exit 1 }
}
