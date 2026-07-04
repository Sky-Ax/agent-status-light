# Codex Status Light

Codex Status Light is a small hardware status indicator for Codex. It listens to Codex hook events, writes the current session state to a local status file, and forwards that state to an ESP32-C3 + WS2812 LED ring.

Codex Status Light 是一个基于 Codex Hooks 的状态灯项目。它会监听 Codex 会话状态，将工作中、空闲、需要注意等状态同步到 ESP32-C3 + WS2812 灯环，用灯光直观显示当前 Codex 的运行状态。

## What It Does

- Records Codex hook events into `data/codex-status.json`.
- Runs a Go bridge that watches the status file.
- Sends `idle`, `working`, `attention`, or `unknown` to the ESP32 over serial.
- Shows the Codex state on a WS2812 LED ring.

## Hardware

- ESP32-C3 board
- WS2812 / WS2812B LED ring
- Tested with 24 LEDs on GPIO10
- USB serial connection to Windows

## Status Mapping

| Codex State | LED Color |
| --- | --- |
| `idle` | Green |
| `working` | Yellow |
| `attention` | Red |
| `unknown` | Blue |

## Project Structure

```text
bin/
  codex-hook.cmd       Codex hook command wrapper
  codex-hook.js        Codex hook event parser
  ai-hook-bridge.exe   Built Go serial bridge
  build-bridge.cmd     Build the Go bridge
  start-bridge.cmd     Start the Go bridge
  install.ps1          Hook installer/checker
bridge/
  main.go              Go bridge source
data/
  .gitkeep             Runtime data directory placeholder
test/
  codex-hook.test.js
  install.test.ps1
install.cmd            Interactive installer
check.cmd              Setup checker
```

## Usage

Install or update the Codex hook:

```powershell
.\install.cmd
```

Check the setup:

```powershell
.\check.cmd
```

Start the serial bridge:

```powershell
.\bin\start-bridge.cmd -port COM4
```

Build the Go bridge after changing `bridge/main.go`:

```powershell
.\bin\build-bridge.cmd
```

## ESP32 Firmware

The ESP32 firmware is kept outside this repository during local development. The current serial protocol is line-based:

```text
idle
working
attention
unknown
```

The ESP32 should read one line from USB serial at `115200` baud and update the LED ring color.

For ESP32-C3 USB serial, enable `USB CDC On Boot` when uploading the Arduino sketch.

## Development

Run tests:

```powershell
node .\test\codex-hook.test.js
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test\install.test.ps1
cd bridge
go test ./...
```

## License

MIT
