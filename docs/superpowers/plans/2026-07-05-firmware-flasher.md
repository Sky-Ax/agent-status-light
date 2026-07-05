# Firmware Flasher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a double-click Windows firmware flasher for the ESP32-C3 + WS2812B Arduino firmware.

**Architecture:** Add a double-click `hardware/arduino/flash-firmware.cmd` wrapper that launches a PowerShell implementation in `hardware/arduino/flash-firmware.ps1`. The PowerShell script keeps helper functions testable with `-NoRun`, downloads a local `arduino-cli` from Arduino's official download host into `tools/arduino-cli` when missing, installs ESP32 and FastLED dependencies, selects a COM port, compiles `SerialStatusLight.ino`, and uploads it. Keep the repository root focused on the main `start.cmd` launcher.

**Tech Stack:** Windows batch, PowerShell 5.1-compatible scripting, Arduino CLI, existing Go bridge port listing fallback where useful.

---

### Task 1: Flasher Tests

**Files:**
- Create: `test/firmware-flasher.test.ps1`
- Test: `hardware/arduino/flash-firmware.ps1`

- [ ] **Step 1: Write failing tests**

Create tests that dot-source `hardware/arduino/flash-firmware.ps1 -NoRun` and verify:

- `Get-ProjectRootFromArduinoScript` resolves the repository root from `hardware/arduino`.
- `Get-ArduinoCliPath` returns `tools/arduino-cli/arduino-cli.exe`.
- `Get-SerialPortsFromOutput` keeps only `COM` ports.
- `Resolve-SerialPortSelection` accepts one-based indexes and COM names.
- `Get-ArduinoCliDownloadUrl` returns Arduino's official latest Windows 64-bit zip URL.

- [ ] **Step 2: Run tests and verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test\firmware-flasher.test.ps1
```

Expected: fail because `hardware/arduino/flash-firmware.ps1` does not exist.

### Task 2: Flasher Implementation

**Files:**
- Create: `hardware/arduino/flash-firmware.ps1`
- Create: `hardware/arduino/flash-firmware.cmd`
- Modify: `.gitignore`
- Modify: `hardware/arduino/README.md`
- Modify: `README.md`
- Test: `test/firmware-flasher.test.ps1`

- [ ] **Step 1: Implement PowerShell helper functions**

Add `-NoRun`, path helpers, COM parsing, COM selection, local Arduino CLI path calculation, download URL calculation, and command invocation helpers. Add `tools/` to `.gitignore` because the flasher stores downloaded tooling there.

- [ ] **Step 2: Implement Arduino CLI setup and upload flow**

When run normally, the script should:

- Ensure `tools/arduino-cli/arduino-cli.exe` exists, downloading the latest GitHub release zip if needed after prompting the user.
- Run `core update-index --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json`.
- Install `esp32:esp32` with the same `--additional-urls` argument.
- Install `FastLED`.
- Compile `hardware/arduino/SerialStatusLight/SerialStatusLight.ino` for `esp32:esp32:esp32c3`.
- Upload to the selected COM port.

- [ ] **Step 3: Add hardware wrapper**

Create `hardware/arduino/flash-firmware.cmd` that runs the PowerShell script and pauses on exit. Do not add a root-level firmware flasher command; root stays reserved for the main project launcher.

- [ ] **Step 4: Verify GREEN**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test\firmware-flasher.test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test\install.test.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test\launcher.test.ps1
cd bridge
go test ./...
```

Expected: all commands exit `0`. The firmware flasher test must not download tools or require hardware.
