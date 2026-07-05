param(
  [switch]$NoRun,
  [switch]$Yes,
  [string]$Port = "",
  [string]$Firmware = ""
)

$ErrorActionPreference = "Stop"
try {
  [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
} catch {
}

$Esp32PackageUrl = "https://espressif.github.io/arduino-esp32/package_esp32_index.json"
$BoardFqbn = "esp32:esp32:esp32c3"
$FastLedVersion = "3.9.4"
$FirmwareRootRelativePath = "hardware\arduino\SerialStatusLight"

function Write-FlasherHeader {
  Write-Host ""
  Write-Host "+----------------------------------------+"
  Write-Host "|  Agent Hook Light Firmware Flasher     |"
  Write-Host "|  ESP32-C3 + WS2812B                    |"
  Write-Host "+----------------------------------------+"
  Write-Host ""
}

function Write-FlasherStep {
  param([string]$Text)

  Write-Host "[*] $Text" -ForegroundColor Cyan
}

function Write-FlasherSuccess {
  param([string]$Text)

  Write-Host "[OK] $Text" -ForegroundColor Green
}

function Write-FlasherWarning {
  param([string]$Text)

  Write-Host "[!] $Text" -ForegroundColor Yellow
}

function Get-ProjectRootFromArduinoScript {
  param([string]$ArduinoScriptDir)

  $root = Join-Path $ArduinoScriptDir "..\.."
  return [IO.Path]::GetFullPath($root).TrimEnd("\")
}

function Get-ArduinoCliPath {
  param([string]$RootDir)

  return (Join-Path $RootDir "tools\arduino-cli\arduino-cli.exe")
}

function Get-ArduinoDataDir {
  return (Join-Path $env:LOCALAPPDATA "Arduino15")
}

function Get-Esp32IndexPath {
  return (Join-Path (Get-ArduinoDataDir) "package_esp32_index.json")
}

function Get-ArduinoCliDownloadUrl {
  param([string]$Version = "latest")

  if ([string]::IsNullOrWhiteSpace($Version) -or $Version -eq "latest") {
    return "https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_Windows_64bit.zip"
  }

  $cleanVersion = $Version.TrimStart("v")
  return "https://github.com/arduino/arduino-cli/releases/download/v$cleanVersion/arduino-cli_${cleanVersion}_Windows_64bit.zip"
}

function Get-ArduinoCliManualInstallMessage {
  param([string]$RootDir)

  $cliPath = Get-ArduinoCliPath -RootDir $RootDir
  $url = Get-ArduinoCliDownloadUrl -Version "latest"
  return @"
Arduino CLI is required to compile and upload the firmware.

Manual install:
1. Download: $url
2. Extract arduino-cli.exe to: $cliPath
3. Run again: hardware\arduino\flash-firmware.cmd
"@.Trim()
}

function Get-FastLedLibrarySpec {
  return "FastLED@$FastLedVersion"
}

function Get-FirmwareRootDir {
  param([string]$RootDir)

  return (Join-Path $RootDir $FirmwareRootRelativePath)
}

function Convert-FirmwareIdToName {
  param([string]$Id)

  if ([string]::IsNullOrWhiteSpace($Id)) {
    return ""
  }

  return (($Id -creplace '(?<!^)([A-Z])', ' $1').Trim())
}

function Convert-ToProjectRelativePath {
  param(
    [string]$RootDir,
    [string]$Path
  )

  $rootFullPath = [IO.Path]::GetFullPath($RootDir).TrimEnd("\") + "\"
  $fullPath = [IO.Path]::GetFullPath($Path)
  if (!$fullPath.StartsWith($rootFullPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Path is outside the project root: $Path"
  }

  return $fullPath.Substring($rootFullPath.Length)
}

function Get-FirmwareDefinitions {
  param([string]$RootDir)

  $firmwareRoot = Get-FirmwareRootDir -RootDir $RootDir
  if (!(Test-Path -LiteralPath $firmwareRoot)) {
    return @()
  }

  $firmwares = @()
  $sketches = @(Get-ChildItem -LiteralPath $firmwareRoot -Filter "*.ino" -File)
  foreach ($sketch in $sketches) {
    $firmwareId = [IO.Path]::GetFileNameWithoutExtension($sketch.Name)
    $relativeSketchPath = Convert-ToProjectRelativePath -RootDir $RootDir -Path $sketch.FullName
    $firmwares += [pscustomobject]@{
      Id                 = $firmwareId
      Name               = Convert-FirmwareIdToName -Id $firmwareId
      RelativeSketchPath = $relativeSketchPath
      SketchPath         = $sketch.FullName
    }
  }

  return @($firmwares | Sort-Object Name, Id)
}

function Resolve-FirmwareSelection {
  param(
    [object[]]$Firmwares,
    [string]$Choice
  )

  if ([string]::IsNullOrWhiteSpace($Choice)) {
    return $null
  }

  $trimmedChoice = $Choice.Trim()
  if ($trimmedChoice -match "^[0-9]+$") {
    $index = [int]$trimmedChoice - 1
    if ($index -ge 0 -and $index -lt $Firmwares.Count) {
      return $Firmwares[$index]
    }
    return $null
  }

  foreach ($firmwareItem in @($Firmwares)) {
    if (($firmwareItem.Id -ieq $trimmedChoice) -or ($firmwareItem.Name -ieq $trimmedChoice)) {
      return $firmwareItem
    }
  }

  return $null
}

function Get-Esp32CoreManualInstallMessage {
  param([string]$ArduinoCli)

  $fastLedSpec = Get-FastLedLibrarySpec
  return @"
ESP32 board support or FastLED could not be installed automatically.

This is usually a network problem while Arduino CLI downloads Espressif's board index.

Manual commands to retry in PowerShell:
1. $ArduinoCli core update-index --additional-urls $Esp32PackageUrl
2. $ArduinoCli core install esp32:esp32 --additional-urls $Esp32PackageUrl
3. $ArduinoCli lib install $fastLedSpec

If the first command keeps failing, open this URL in a browser to check whether your network can reach it:
$Esp32PackageUrl

After the commands succeed, run again: hardware\arduino\flash-firmware.cmd
"@.Trim()
}

function Confirm-FlasherPrompt {
  param(
    [string]$Prompt,
    [bool]$DefaultYes = $false,
    [switch]$AssumeYes
  )

  if ($AssumeYes) {
    return $true
  }

  $suffix = "[y/N]"
  if ($DefaultYes) {
    $suffix = "[Y/n]"
  }

  $answer = Read-Host "$Prompt $suffix"
  if ([string]::IsNullOrWhiteSpace($answer)) {
    return $DefaultYes
  }

  return ($answer -match "^[Yy]")
}

function Get-SerialPortsFromOutput {
  param([string[]]$Output)

  $ports = @()
  foreach ($line in @($Output)) {
    $port = ([string]$line).Trim().ToUpperInvariant()
    if ($port -match "^COM[0-9]+$") {
      $ports += $port
    }
  }

  return $ports
}

function Get-SerialPorts {
  $ports = @()
  try {
    $ports = [System.IO.Ports.SerialPort]::GetPortNames()
  } catch {
    $ports = @()
  }

  return @(Get-SerialPortsFromOutput -Output $ports)
}

function Resolve-SerialPortSelection {
  param(
    [string[]]$Ports,
    [string]$Choice
  )

  if ([string]::IsNullOrWhiteSpace($Choice)) {
    return $null
  }

  $normalizedPorts = @($Ports | ForEach-Object { ([string]$_).Trim().ToUpperInvariant() })
  $trimmedChoice = $Choice.Trim()

  if ($trimmedChoice -match "^[0-9]+$") {
    $index = [int]$trimmedChoice - 1
    if ($index -ge 0 -and $index -lt $normalizedPorts.Count) {
      return $normalizedPorts[$index]
    }
    return $null
  }

  $portChoice = $trimmedChoice.ToUpperInvariant()
  if ($normalizedPorts -contains $portChoice) {
    return $portChoice
  }

  return $null
}

function Get-MenuHelpText {
  return "Use Up / Down to choose, Space or Enter to confirm. Press Esc to cancel."
}

function Move-MenuSelection {
  param(
    [int]$CurrentIndex,
    [int]$ItemCount,
    [string]$Key
  )

  if ($ItemCount -le 0) {
    return 0
  }

  switch ($Key) {
    "DownArrow" { return (($CurrentIndex + 1) % $ItemCount) }
    "UpArrow" { return (($CurrentIndex - 1 + $ItemCount) % $ItemCount) }
    default { return $CurrentIndex }
  }
}

function Get-MenuKeyAction {
  param([string]$Key)

  switch ($Key) {
    "Enter" { return "confirm" }
    "Spacebar" { return "confirm" }
    "Escape" { return "cancel" }
    default { return "move" }
  }
}

function Show-KeyboardMenu {
  param(
    [string]$Title,
    [string[]]$Items,
    [int]$DefaultIndex = 0,
    [string[]]$Details = @()
  )

  if ($Items.Count -eq 0) {
    return -1
  }

  $selectedIndex = $DefaultIndex
  if ($selectedIndex -lt 0 -or $selectedIndex -ge $Items.Count) {
    $selectedIndex = 0
  }

  while ($true) {
    Clear-Host
    Write-FlasherHeader

    if (![string]::IsNullOrWhiteSpace($Title)) {
      Write-Host $Title -ForegroundColor Cyan
      Write-Host ""
    }

    foreach ($detail in @($Details)) {
      if (![string]::IsNullOrWhiteSpace($detail)) {
        Write-Host $detail
      }
    }
    if ($Details.Count -gt 0) {
      Write-Host ""
    }

    Write-Host (Get-MenuHelpText) -ForegroundColor DarkCyan
    Write-Host ""

    for ($i = 0; $i -lt $Items.Count; $i++) {
      if ($i -eq $selectedIndex) {
        Write-Host ("  > {0}" -f $Items[$i]) -ForegroundColor Green
      } else {
        Write-Host ("    {0}" -f $Items[$i])
      }
    }

    $keyInfo = [Console]::ReadKey($true)
    $key = $keyInfo.Key.ToString()
    $action = Get-MenuKeyAction -Key $key

    if ($action -eq "confirm") {
      return $selectedIndex
    }

    if ($action -eq "cancel") {
      return -1
    }

    $selectedIndex = Move-MenuSelection -CurrentIndex $selectedIndex -ItemCount $Items.Count -Key $key
  }
}

function Select-SerialPort {
  param([string]$RequestedPort = "")

  $ports = @(Get-SerialPorts)
  if ($ports.Count -eq 0) {
    throw "No serial ports found. Connect the ESP32-C3 board and try again."
  }

  if (![string]::IsNullOrWhiteSpace($RequestedPort)) {
    $selected = Resolve-SerialPortSelection -Ports $ports -Choice $RequestedPort
    if ($selected) {
      return $selected
    }
    throw "Requested port is not available: $RequestedPort"
  }

  if ($ports.Count -eq 1) {
    Write-FlasherSuccess "Using detected serial port: $($ports[0])"
    return $ports[0]
  }

  $selection = Show-KeyboardMenu `
    -Title "Select ESP32-C3 serial port" `
    -Items $ports `
    -DefaultIndex 0 `
    -Details @("Tip: unplug/replug the ESP32-C3 if you are not sure which COM port is correct.")
  if ($selection -ge 0) {
    return $ports[$selection]
  }

  throw "Serial port selection was cancelled."
}

function Select-Firmware {
  param(
    [string]$RootDir,
    [string]$RequestedFirmware = ""
  )

  $firmwares = @(Get-FirmwareDefinitions -RootDir $RootDir)
  if ($firmwares.Count -eq 0) {
    throw "No firmware definitions found."
  }

  foreach ($firmwareItem in $firmwares) {
    if (!(Test-Path -LiteralPath $firmwareItem.SketchPath)) {
      throw "Missing firmware sketch: $($firmwareItem.SketchPath)"
    }
  }

  if (![string]::IsNullOrWhiteSpace($RequestedFirmware)) {
    $selected = Resolve-FirmwareSelection -Firmwares $firmwares -Choice $RequestedFirmware
    if ($selected) {
      return $selected
    }
    throw "Requested firmware is not available: $RequestedFirmware"
  }

  if ($firmwares.Count -eq 1) {
    Write-FlasherSuccess "Using firmware: $($firmwares[0].Name)"
    return $firmwares[0]
  }

  $items = @($firmwares | ForEach-Object { "{0} ({1})" -f $_.Name, $_.Id })
  $selection = Show-KeyboardMenu `
    -Title "Select firmware" `
    -Items $items `
    -DefaultIndex 0
  if ($selection -ge 0) {
    return $firmwares[$selection]
  }

  throw "Firmware selection was cancelled."
}

function Copy-FirmwareToIsolatedSketch {
  param(
    [object]$SelectedFirmware,
    [string]$TempRoot
  )

  $sketchDir = Join-Path $TempRoot $SelectedFirmware.Id
  $sketchPath = Join-Path $sketchDir ($SelectedFirmware.Id + ".ino")

  New-Item -ItemType Directory -Path $sketchDir -Force | Out-Null
  Copy-Item -LiteralPath $SelectedFirmware.SketchPath -Destination $sketchPath -Force

  return $sketchPath
}

function Format-CommandArgument {
  param([string]$Argument)

  if ($null -eq $Argument) {
    return '""'
  }

  if ($Argument -notmatch '[\s"]') {
    return $Argument
  }

  return '"' + ($Argument -replace '"', '\"') + '"'
}

function Invoke-CheckedCommand {
  param(
    [string]$FilePath,
    [string[]]$Arguments = @(),
    [int]$TimeoutSeconds = 300
  )

  Write-Host ("> {0} {1}" -f $FilePath, ($Arguments -join " "))

  & $FilePath @Arguments
  $exitCode = $LASTEXITCODE

  if ($exitCode -ne 0) {
    throw "Command failed with exit code ${exitCode}: $FilePath"
  }
}

function Invoke-CapturedCommand {
  param(
    [string]$FilePath,
    [string[]]$Arguments = @()
  )

  $output = & $FilePath @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  return [pscustomobject]@{
    ExitCode = $exitCode
    Output   = @($output | ForEach-Object { [string]$_ })
  }
}

function Test-CoreListContainsPlatform {
  param(
    [string[]]$Output,
    [string]$PlatformId
  )

  foreach ($line in @($Output)) {
    if (([string]$line).Trim() -match ("^" + [regex]::Escape($PlatformId) + "\s")) {
      return $true
    }
  }

  return $false
}

function Test-LibListContainsLibrary {
  param(
    [string[]]$Output,
    [string]$LibraryName
  )

  foreach ($line in @($Output)) {
    if (([string]$line).Trim() -match ("^" + [regex]::Escape($LibraryName) + "\s")) {
      return $true
    }
  }

  return $false
}

function Test-ArduinoDependenciesInstalled {
  param([string]$ArduinoCli)

  $coreResult = Invoke-CapturedCommand -FilePath $ArduinoCli -Arguments @("core", "list")
  if ($coreResult.ExitCode -ne 0) {
    return $false
  }
  if (!(Test-CoreListContainsPlatform -Output $coreResult.Output -PlatformId "esp32:esp32")) {
    return $false
  }

  $libResult = Invoke-CapturedCommand -FilePath $ArduinoCli -Arguments @("lib", "list")
  if ($libResult.ExitCode -ne 0) {
    return $false
  }

  return (Test-LibListContainsLibrary -Output $libResult.Output -LibraryName "FastLED")
}

function Get-RetryAttemptMessage {
  param(
    [int]$Attempt,
    [int]$Attempts
  )

  if ($Attempt -le 1 -or $Attempts -le 1) {
    return ""
  }

  return ("Retry attempt {0}/{1}" -f $Attempt, $Attempts)
}

function Invoke-CheckedCommandWithRetry {
  param(
    [string]$FilePath,
    [string[]]$Arguments = @(),
    [int]$Attempts = 3,
    [int]$DelaySeconds = 3,
    [int]$TimeoutSeconds = 300,
    [string]$FailureHelp = ""
  )

  if ($Attempts -lt 1) {
    $Attempts = 1
  }

  $lastError = $null
  for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
    try {
      $retryMessage = Get-RetryAttemptMessage -Attempt $attempt -Attempts $Attempts
      if (![string]::IsNullOrWhiteSpace($retryMessage)) {
        Write-FlasherStep $retryMessage
      }
      Invoke-CheckedCommand -FilePath $FilePath -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds
      return
    } catch {
      $lastError = $_.Exception.Message
      if ($attempt -lt $Attempts) {
        Write-FlasherWarning "$lastError"
        Write-FlasherWarning "Retrying in $DelaySeconds seconds..."
        Start-Sleep -Seconds $DelaySeconds
      }
    }
  }

  if (![string]::IsNullOrWhiteSpace($FailureHelp)) {
    throw "$lastError`n`n$FailureHelp"
  }

  throw $lastError
}

function Install-ArduinoCli {
  param(
    [string]$RootDir,
    [switch]$AssumeYes
  )

  $cliPath = Get-ArduinoCliPath -RootDir $RootDir
  if (Test-Path -LiteralPath $cliPath) {
    return $cliPath
  }

  Write-FlasherWarning "Arduino CLI is not installed in this project."
  if (!(Confirm-FlasherPrompt -Prompt "Download Arduino CLI from Arduino's official download host?" -AssumeYes:$AssumeYes)) {
    throw (Get-ArduinoCliManualInstallMessage -RootDir $RootDir)
  }

  $toolsDir = Split-Path -Parent $cliPath
  $tempDir = Join-Path ([IO.Path]::GetTempPath()) ("agent-hook-light-arduino-cli-" + [guid]::NewGuid())
  $zipPath = Join-Path $tempDir "arduino-cli.zip"
  $url = Get-ArduinoCliDownloadUrl -Version "latest"

  New-Item -ItemType Directory -Path $tempDir | Out-Null
  try {
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    try {
      Write-FlasherStep "Downloading Arduino CLI..."
      Invoke-WebRequest -Uri $url -OutFile $zipPath
    } catch {
      throw "Arduino CLI download failed: $($_.Exception.Message)`n`n$(Get-ArduinoCliManualInstallMessage -RootDir $RootDir)"
    }

    try {
      Write-FlasherStep "Extracting Arduino CLI..."
      Expand-Archive -LiteralPath $zipPath -DestinationPath $tempDir -Force
    } catch {
      throw "Arduino CLI archive extraction failed: $($_.Exception.Message)`n`n$(Get-ArduinoCliManualInstallMessage -RootDir $RootDir)"
    }

    $downloadedCli = Get-ChildItem -LiteralPath $tempDir -Filter "arduino-cli.exe" -Recurse -File | Select-Object -First 1
    if (!$downloadedCli) {
      throw "Downloaded Arduino CLI archive did not contain arduino-cli.exe.`n`n$(Get-ArduinoCliManualInstallMessage -RootDir $RootDir)"
    }

    Copy-Item -LiteralPath $downloadedCli.FullName -Destination $cliPath -Force
  } finally {
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
  }

  return $cliPath
}

function Ensure-ArduinoDependencies {
  param([string]$ArduinoCli)

  if (Test-ArduinoDependenciesInstalled -ArduinoCli $ArduinoCli) {
    Write-FlasherSuccess "ESP32 board support and FastLED are already installed."
    return
  }

  $failureHelp = Get-Esp32CoreManualInstallMessage -ArduinoCli $ArduinoCli

  Write-FlasherStep "Preparing Arduino package index..."
  try {
    Invoke-CheckedCommandWithRetry -FilePath $ArduinoCli -Arguments @("core", "update-index", "--additional-urls", $Esp32PackageUrl) -TimeoutSeconds 180 -FailureHelp $failureHelp
  } catch {
    $esp32IndexPath = Get-Esp32IndexPath
    if (Test-Path -LiteralPath $esp32IndexPath) {
      Write-FlasherWarning "Arduino CLI reported an index update failure, but the ESP32 index exists locally: $esp32IndexPath"
      Write-FlasherWarning "Continuing with the cached ESP32 index."
    } else {
      throw
    }
  }

  Write-FlasherStep "Installing ESP32 board support..."
  Invoke-CheckedCommandWithRetry -FilePath $ArduinoCli -Arguments @("core", "install", "esp32:esp32", "--additional-urls", $Esp32PackageUrl) -TimeoutSeconds 600 -FailureHelp $failureHelp

  Write-FlasherStep "Installing FastLED library..."
  Invoke-CheckedCommandWithRetry -FilePath $ArduinoCli -Arguments @("lib", "install", (Get-FastLedLibrarySpec)) -TimeoutSeconds 300 -FailureHelp $failureHelp
}

function Invoke-FirmwareFlash {
  param(
    [string]$RootDir,
    [string]$ArduinoCli,
    [string]$SelectedPort,
    [object]$SelectedFirmware
  )

  if (!(Test-Path -LiteralPath $SelectedFirmware.SketchPath)) {
    throw "Missing firmware sketch: $($SelectedFirmware.SketchPath)"
  }

  $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("agent-hook-light-firmware-" + [guid]::NewGuid())
  try {
    $sketchPath = Copy-FirmwareToIsolatedSketch -SelectedFirmware $SelectedFirmware -TempRoot $tempRoot

    Write-FlasherStep "Compiling firmware: $($SelectedFirmware.Name)..."
    Invoke-CheckedCommand -FilePath $ArduinoCli -Arguments @("compile", "--fqbn", $BoardFqbn, $sketchPath)

    Write-FlasherStep "Uploading firmware to $SelectedPort..."
    Invoke-CheckedCommand -FilePath $ArduinoCli -Arguments @("upload", "-p", $SelectedPort, "--fqbn", $BoardFqbn, $sketchPath)
  } finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-FirmwareFlasher {
  $arduinoScriptDir = $PSScriptRoot
  $rootDir = Get-ProjectRootFromArduinoScript -ArduinoScriptDir $arduinoScriptDir

  Write-FlasherHeader
  Write-FlasherStep "Checking local Arduino CLI..."
  $arduinoCli = Install-ArduinoCli -RootDir $rootDir -AssumeYes:$Yes
  Write-FlasherSuccess "Arduino CLI: $arduinoCli"

  Ensure-ArduinoDependencies -ArduinoCli $arduinoCli

  Write-FlasherStep "Selecting firmware..."
  $selectedFirmware = Select-Firmware -RootDir $rootDir -RequestedFirmware $Firmware

  Write-FlasherStep "Selecting ESP32-C3 serial port..."
  $selectedPort = Select-SerialPort -RequestedPort $Port

  Invoke-FirmwareFlash -RootDir $rootDir -ArduinoCli $arduinoCli -SelectedPort $selectedPort -SelectedFirmware $selectedFirmware

  Write-FlasherSuccess "$($selectedFirmware.Name) uploaded to $selectedPort."
  Write-Host ""
  Write-Host "You can now run start.cmd to start the status bridge."
}

if (!$NoRun) {
  try {
    Invoke-FirmwareFlasher
    exit 0
  } catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
  }
}
