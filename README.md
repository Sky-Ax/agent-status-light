# Agent Hook Light

> Physical status light for AI coding agents.

[简体中文](README.zh-CN.md)

Agent Hook Light turns AI agent hook events into visible desk status colors. Codex is supported today through Codex Hooks. Other hook-capable agents can be added through the same status protocol.

## Demo

[Watch the demo video](https://github.com/Sky-Ax/agent-hook-light/releases/download/v0.1.0/demo.mp4)

<video src="https://github.com/Sky-Ax/agent-hook-light/releases/download/v0.1.0/demo.mp4" controls muted width="720"></video>

## Quick Start

Requirements:

- Windows
- Codex with hooks support
- ESP32-C3
- WS2812 / WS2812B LED ring
- USB data cable

### 1. Flash The Device

Connect the ESP32-C3 and run:

```powershell
.\hardware\arduino\flash-firmware.cmd
```

The flasher will download the project-managed Arduino CLI, install the ESP32 board package and FastLED, ask for the firmware and COM port, then compile and upload the sketch.

Recommended firmware:

```text
Status Light V3
```

Hardware and firmware details are in [hardware/arduino/README.md](hardware/arduino/README.md).

### 2. Start The Bridge

Run:

```powershell
.\start.cmd
```

The launcher checks Codex hooks, installs or updates them if needed, builds the Go bridge if missing, asks for the ESP32 COM port, then starts the bridge.

Keep this window running while using Codex. The light follows agent status changes.

## Status Colors

| State | Color | Meaning |
| --- | --- | --- |
| `idle` | Green / gray | No active task |
| `thinking` | Blue | Agent is reasoning |
| `working` | Yellow / orange | Agent is running tools |
| `waiting` | Purple | Waiting for user input or permission |
| `success` | Green | Task completed |
| `error` | Red | Error or attention required |
| `unknown` | Blue / gray | Unsupported or unclear state |

## Agent Support

| Agent | Status | Notes |
| --- | --- | --- |
| Codex | Supported | Uses Codex Hooks today. |
| Claude Code | Planned | Hook / lifecycle adapter. |
| Gemini CLI | Planned | Adapter depends on available lifecycle signals. |
| OpenCode | Planned | Hook adapter. |
| Cursor | Researching | Needs a reliable local status source. |
| Aider | Researching | Could map terminal/session state. |
| Custom agent | Planned | File, stdout, or webhook adapter. |

## Custom Development

If you need a custom agent adapter, firmware effect, Wi-Fi control mode, hardware build, or product integration, contact me on WeChat.

<img src="assets/wechat-contact.png" alt="WeChat contact QR code" width="320">

## License

MIT
