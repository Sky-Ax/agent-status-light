# Arduino Firmware

This folder contains the ESP32-C3 + WS2812B firmware for Agent Status Light.

Firmware sketches live under `SerialStatusLight`:

- `SerialStatusLight/SerialStatusLight.ino`: status light firmware for the current Go bridge
- `SerialStatusLight/RainbowLight.ino`: standalone rainbow light demo firmware

Shared hardware settings:

- Board: ESP32-C3
- LED type: WS2812B
- LED count: 24
- Data pin: GPIO10
- Color order: GRB
- Serial baud rate: 115200

The firmware reads one status line from USB serial:

```text
idle
working
attention
unknown
```

Default color mapping:

| State | Color |
| --- | --- |
| `idle` | Green |
| `working` | Yellow |
| `attention` | Red |
| `unknown` | Blue |

When flashing from Arduino IDE, enable USB CDC on boot for ESP32-C3 serial access.

## Double-Click Flashing

From the repository root, run:

```powershell
.\hardware\arduino\flash-firmware.cmd
```

The flasher downloads a local Arduino CLI into `tools/arduino-cli` if needed, installs ESP32 board support and FastLED, asks for the ESP32-C3 COM port, then compiles and uploads the firmware.

When multiple `.ino` firmware sketches exist directly under `SerialStatusLight`, the flasher lists them first so you can choose which firmware to upload.

If automatic download fails or you do not want the script to download tools, download Arduino CLI manually:

```text
https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_Windows_64bit.zip
```

Extract `arduino-cli.exe` to `tools\arduino-cli\arduino-cli.exe`, then run `hardware\arduino\flash-firmware.cmd` again.

If ESP32 board support download fails, the flasher retries Arduino CLI network commands and then prints manual commands for:

- `core update-index --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json`
- `core install esp32:esp32 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json`
- `lib install FastLED@3.9.4`

The flasher pins FastLED to `3.9.4` because it compiles this firmware successfully and avoids the much larger latest FastLED package.

For unattended local setup, pass `-Yes` to the PowerShell script:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\hardware\arduino\flash-firmware.ps1 -Yes -Port COM4
```
