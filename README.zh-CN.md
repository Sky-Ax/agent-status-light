# Agent Hook Light

> 面向 AI 编程 Agent 的实体状态灯。

[English](README.md)

Agent Hook Light 将 AI Agent 的 hook 事件转成桌面可见的状态颜色。当前通过 Codex Hooks 支持 Codex，后续其它支持 hook 的 Agent 可以复用同一套状态协议接入。

## 演示

<table>
  <tr>
    <td>
      <video src="https://github.com/Sky-Ax/agent-hook-light/releases/download/v0.1.0/demo.mp4" controls="controls" muted="muted" width="720" style="max-width:100%; min-height:360px">
      </video>
    </td>
  </tr>
</table>

## 快速开始

需要准备：

- Windows
- 支持 hooks 的 Codex
- ESP32-C3
- WS2812 / WS2812B 灯环
- USB 数据线

### 1. 烧录设备

连接 ESP32-C3 后运行：

```powershell
.\hardware\arduino\flash-firmware.cmd
```

烧录脚本会下载项目内置 Arduino CLI，安装 ESP32 开发板包和 FastLED，提示选择固件和 COM 口，然后编译并上传 sketch。

推荐固件：

```text
Status Light V3
```

硬件和固件细节放在 [hardware/arduino/README.md](hardware/arduino/README.md)。

### 2. 启动桥接程序

运行：

```powershell
.\start.cmd
```

启动器会检查 Codex hooks，必要时安装或更新 hooks；如果缺少 Go bridge，会自动构建；然后选择 ESP32 COM 口并启动 bridge。

使用 Codex 时保持这个窗口运行，灯光会跟随 Agent 状态变化。

## 状态颜色

| 状态 | 颜色 | 含义 |
| --- | --- | --- |
| `idle` | 绿色 / 灰色 | 当前没有任务 |
| `thinking` | 蓝色 | Agent 正在思考 |
| `working` | 黄色 / 橙色 | Agent 正在执行工具 |
| `waiting` | 琥珀色 | 等待用户输入或授权 |
| `success` | 绿色 | 任务完成 |
| `error` | 红色 | 出错或需要注意 |
| `unknown` | 蓝色 / 灰色 | 状态不明确或暂不支持 |

## Agent 支持

| Agent | 状态 | 说明 |
| --- | --- | --- |
| Codex | 已支持 | 当前通过 Codex Hooks 接入。 |
| Claude Code | 计划支持 | Hook / lifecycle 适配器。 |
| Gemini CLI | 计划支持 | 取决于可用生命周期信号。 |
| OpenCode | 计划支持 | Hook 适配器。 |
| Cursor | 调研中 | 需要可靠的本地状态来源。 |
| Aider | 调研中 | 可考虑映射终端或会话状态。 |
| 自定义 Agent | 计划支持 | 文件、stdout 或 webhook 适配器。 |

## 定制化开发

如果您有自定义 Agent 接入、灯效定制、Wi-Fi 控制、硬件制作或产品化集成需求，可以扫码添加微信联系。

<img src="assets/wechat-contact.png" alt="微信联系二维码" width="320">

## 许可证

MIT
