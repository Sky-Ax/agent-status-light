$ErrorActionPreference = "Stop"

$TestDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $TestDir
$FlasherScript = Join-Path $Root "hardware\arduino\flash-firmware.ps1"
$HardwareFlasherCmd = Join-Path $Root "hardware\arduino\flash-firmware.cmd"
$RootFlasherCmd = Join-Path $Root "flash-firmware.cmd"

function Assert-Equal {
  param($Actual, $Expected, [string]$Message)

  if ($Actual -ne $Expected) {
    throw "$Message Expected '$Expected', got '$Actual'."
  }
}

function Assert-True {
  param([bool]$Condition, [string]$Message)

  if (!$Condition) {
    throw $Message
  }
}

. $FlasherScript -NoRun

Assert-True (Test-Path -LiteralPath $HardwareFlasherCmd) "Firmware double-click launcher should live under hardware\arduino."
Assert-True (!(Test-Path -LiteralPath $RootFlasherCmd)) "Repository root should stay minimal and should not contain flash-firmware.cmd."

$resolvedRoot = Get-ProjectRootFromArduinoScript -ArduinoScriptDir (Join-Path $Root "hardware\arduino")
Assert-Equal $resolvedRoot $Root "Arduino script directory should resolve to the repository root."

$cliPath = Get-ArduinoCliPath -RootDir $Root
Assert-Equal $cliPath (Join-Path $Root "tools\arduino-cli\arduino-cli.exe") "Arduino CLI should live under the local tools directory."

$arduinoDataDir = Get-ArduinoDataDir
Assert-Equal $arduinoDataDir (Join-Path $env:LOCALAPPDATA "Arduino15") "Arduino CLI data directory should match the Windows Arduino15 location."

$esp32IndexPath = Get-Esp32IndexPath
Assert-Equal $esp32IndexPath (Join-Path $env:LOCALAPPDATA "Arduino15\package_esp32_index.json") "ESP32 package index path should point to the Arduino15 cache."

$ports = Get-SerialPortsFromOutput -Output @("No serial ports found.", "COM3", "COM7", "not-a-port", " /dev/ttyUSB0 ")
Assert-Equal $ports.Count 2 "Only Windows COM ports should be kept."
Assert-Equal $ports[0] "COM3" "First COM port should be preserved."
Assert-Equal $ports[1] "COM7" "Second COM port should be preserved."

Assert-Equal (Resolve-SerialPortSelection -Ports @("COM3", "COM4", "COM7") -Choice "2") "COM4" "Numeric selection should use one-based indexes."
Assert-Equal (Resolve-SerialPortSelection -Ports @("COM3", "COM4", "COM7") -Choice "com7") "COM7" "COM name selection should be case-insensitive."
Assert-Equal (Resolve-SerialPortSelection -Ports @("COM3", "COM4", "COM7") -Choice "4") $null "Out-of-range numeric selection should be rejected."
Assert-Equal (Resolve-SerialPortSelection -Ports @("COM3", "COM4", "COM7") -Choice "COM9") $null "Unavailable COM name should be rejected."

$latestUrl = Get-ArduinoCliDownloadUrl -Version "latest"
Assert-Equal $latestUrl "https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_Windows_64bit.zip" "Latest download URL should use the official Arduino Windows 64-bit archive."

$manualMessage = Get-ArduinoCliManualInstallMessage -RootDir $Root
Assert-True ($manualMessage -like "*https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_Windows_64bit.zip*") "Manual install message should include the Arduino CLI download URL."
Assert-True ($manualMessage -like "*tools\arduino-cli\arduino-cli.exe*") "Manual install message should include the local Arduino CLI target path."
Assert-True ($manualMessage -like "*hardware\arduino\flash-firmware.cmd*") "Manual install message should tell the user to run the hardware flasher again."

$esp32Message = Get-Esp32CoreManualInstallMessage -ArduinoCli $cliPath
Assert-True ($esp32Message -like "*https://espressif.github.io/arduino-esp32/package_esp32_index.json*") "ESP32 fallback message should include the Espressif package index URL."
Assert-True ($esp32Message -like "*core update-index*") "ESP32 fallback message should include the update-index command."
Assert-True ($esp32Message -like "*core install esp32:esp32*") "ESP32 fallback message should include the ESP32 core install command."
Assert-True ($esp32Message -like "*lib install FastLED@3.9.4*") "ESP32 fallback message should include the pinned FastLED install command."

Assert-Equal (Get-FastLedLibrarySpec) "FastLED@3.9.4" "FastLED should be pinned to the verified smaller package."
Assert-Equal (Test-CoreListContainsPlatform -Output @("ID          Installed Latest Name", "esp32:esp32 3.3.10    3.3.10 esp32") -PlatformId "esp32:esp32") $true "ESP32 core list parser should detect an installed core."
Assert-Equal (Test-CoreListContainsPlatform -Output @("ID          Installed Latest Name", "arduino:avr 1.8.8 1.8.8 Arduino AVR Boards") -PlatformId "esp32:esp32") $false "ESP32 core list parser should reject missing core."
Assert-Equal (Test-LibListContainsLibrary -Output @("Name    Installed Available Location Description", "FastLED 3.9.4     3.10.5    user     LED library") -LibraryName "FastLED") $true "Library list parser should detect installed FastLED."
Assert-Equal (Test-LibListContainsLibrary -Output @("No libraries installed.") -LibraryName "FastLED") $false "Library list parser should reject missing FastLED."

Assert-Equal (Get-RetryAttemptMessage -Attempt 1 -Attempts 3) "" "First command attempt should not show a retry label."
Assert-Equal (Get-RetryAttemptMessage -Attempt 2 -Attempts 3) "Retry attempt 2/3" "Second command attempt should be labeled as a retry."
Assert-Equal (Get-RetryAttemptMessage -Attempt 3 -Attempts 3) "Retry attempt 3/3" "Third command attempt should be labeled as a retry."

$firmwareRoot = Get-FirmwareRootDir -RootDir $Root
Assert-Equal $firmwareRoot (Join-Path $Root "hardware\arduino\SerialStatusLight") "Firmware discovery should be limited to the SerialStatusLight folder."

Assert-Equal (Convert-FirmwareIdToName -Id "SerialStatusLight") "Serial Status Light" "Firmware display names should split PascalCase ids."
Assert-Equal (Convert-FirmwareIdToName -Id "RainbowLight") "Rainbow Light" "Firmware display names should be readable for new firmware ids."

$firmwares = @(Get-FirmwareDefinitions -RootDir $Root)
Assert-True ($firmwares.Count -ge 2) "Firmware flasher should expose firmware sketches from inside the SerialStatusLight folder."
$rainbowFirmware = Resolve-FirmwareSelection -Firmwares $firmwares -Choice "RainbowLight"
Assert-Equal $rainbowFirmware.Id "RainbowLight" "Rainbow firmware should be discoverable."
Assert-Equal $rainbowFirmware.Name "Rainbow Light" "Rainbow firmware display name should be human-readable."
Assert-Equal $rainbowFirmware.RelativeSketchPath "hardware\arduino\SerialStatusLight\RainbowLight.ino" "Rainbow firmware sketch path should stay directly under the SerialStatusLight folder."
Assert-True (Test-Path -LiteralPath $rainbowFirmware.SketchPath) "Rainbow firmware sketch path should exist on disk."
Assert-True (!(Test-Path -LiteralPath (Join-Path $Root "hardware\arduino\SerialStatusLight\RainbowLight"))) "Rainbow firmware should not create an extra nested folder."
$statusFirmware = Resolve-FirmwareSelection -Firmwares $firmwares -Choice "SerialStatusLight"
Assert-Equal $statusFirmware.Id "SerialStatusLight" "Status firmware should still be available."
Assert-Equal $statusFirmware.Name "Serial Status Light" "Status firmware display name should be human-readable."
Assert-Equal $statusFirmware.RelativeSketchPath "hardware\arduino\SerialStatusLight\SerialStatusLight.ino" "Status firmware sketch path should point to the existing sketch."
Assert-True (Test-Path -LiteralPath $statusFirmware.SketchPath) "Status firmware sketch path should exist on disk."

$selectedFirmwareByNumber = Resolve-FirmwareSelection -Firmwares $firmwares -Choice "1"
Assert-Equal $selectedFirmwareByNumber.Id "RainbowLight" "Numeric firmware selection should use one-based indexes."
Assert-True (![string]::IsNullOrWhiteSpace($selectedFirmwareByNumber.SketchPath)) "Numeric firmware selection should return the full firmware object."
$selectedFirmwareByName = Resolve-FirmwareSelection -Firmwares $firmwares -Choice "serialstatuslight"
Assert-Equal $selectedFirmwareByName.Id "SerialStatusLight" "Firmware id selection should be case-insensitive."
Assert-True (![string]::IsNullOrWhiteSpace($selectedFirmwareByName.SketchPath)) "Firmware id selection should return the full firmware object."
Assert-Equal (Resolve-FirmwareSelection -Firmwares $firmwares -Choice "999") $null "Out-of-range firmware selection should be rejected."
Assert-Equal (Resolve-FirmwareSelection -Firmwares $firmwares -Choice "OtherFirmware") $null "Unknown firmware id should be rejected."

$isolatedTempRoot = Join-Path ([IO.Path]::GetTempPath()) ("agent-hook-light-firmware-test-" + [guid]::NewGuid())
try {
  $isolatedSketchPath = Copy-FirmwareToIsolatedSketch -SelectedFirmware $rainbowFirmware -TempRoot $isolatedTempRoot
  Assert-Equal $isolatedSketchPath (Join-Path $isolatedTempRoot "RainbowLight\RainbowLight.ino") "Isolated sketch path should use an Arduino-compatible folder and filename."
  Assert-True (Test-Path -LiteralPath $isolatedSketchPath) "Isolated sketch should be copied to disk."
  Assert-Equal (Get-Content -Raw -LiteralPath $isolatedSketchPath) (Get-Content -Raw -LiteralPath $rainbowFirmware.SketchPath) "Isolated sketch content should match the selected firmware."
} finally {
  Remove-Item -LiteralPath $isolatedTempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Assert-Equal (Move-MenuSelection -CurrentIndex 0 -ItemCount 3 -Key "DownArrow") 1 "DownArrow should move to the next firmware port menu item."
Assert-Equal (Move-MenuSelection -CurrentIndex 2 -ItemCount 3 -Key "DownArrow") 0 "DownArrow should wrap firmware port menu selection to the first item."
Assert-Equal (Move-MenuSelection -CurrentIndex 0 -ItemCount 3 -Key "UpArrow") 2 "UpArrow should wrap firmware port menu selection to the last item."
Assert-Equal (Move-MenuSelection -CurrentIndex 1 -ItemCount 0 -Key "DownArrow") 0 "Empty firmware menus should keep index zero."

Assert-Equal (Get-MenuKeyAction -Key "Enter") "confirm" "Enter should confirm the firmware port menu selection."
Assert-Equal (Get-MenuKeyAction -Key "Spacebar") "confirm" "Spacebar should confirm the firmware port menu selection."
Assert-Equal (Get-MenuKeyAction -Key "Escape") "cancel" "Escape should cancel the firmware port menu selection."
Assert-Equal (Get-MenuKeyAction -Key "A") "move" "Other keys should keep the firmware port menu active."
