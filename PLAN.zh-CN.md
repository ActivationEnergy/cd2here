# cd2here 开发计划

[English](PLAN.md) | 简体中文

## 目标

构建两个小型、可靠、易审计的 macOS Finder 工具栏应用：

- `cd2hereWindow.app`：始终在选定终端中新建窗口。
- `cd2hereTab.app`：在选定终端的前台窗口中新建标签页；没有终端窗口时改为新建窗口。

用户第一次使用时选择已安装的终端。普通点击使用保存的选择；Option 点击用于更改默认终端。

## 范围和约束

- 使用 Swift、Foundation 和 AppKit，不使用 SwiftUI。
- Finder 路径解析、终端选择、终端 backend、应用流程和错误处理共用一套核心代码。
- 使用 `NSAppleScript` / Apple Events 集成 Finder 与终端，通过 `Process` 调用 CLI 终端。
- 首批支持 Ghostty、iTerm2、Terminal.app、WezTerm、Alacritty 与 Kitty；**新增一个 backend 实际要改 3 个文件**：新建 controller（遵循 `AppleScriptTerminalControlling` 或 `CLITerminalControlling`）、`TerminalController.swift` 5 处小改动（`TerminalKind` 加 case + `displayName` + `bundleIdentifier` + `cliBinaryName` + `TerminalControllerFactory.make` 加 switch 分支）、`TerminalControllerTests.swift` 加测试。
- 不使用 Finder Sync Extension、后台 daemon 或网络，不修改终端配置，也不替换用户配置的 shell。
- 不枚举或探测目标目录；Finder 负责提供路径，终端负责实际的文件访问。
- 两个应用均为 `LSUIElement`，不出现在 Dock 和 Command-Tab 应用切换器中。
- 本机构建和测试不依赖付费 Apple Developer 账号。
- 面向用户的文档同时维护英文和简体中文版本。

## Finder 路径解析规则

`FinderSnapshot` 改用 enum 实现，两个 case 让非法组合在类型层不可表达：`.noWindow(directory)` 与 `.window(currentDirectory, selection, desktopDirectory)`。"有文件夹选中但 Finder 无窗口"这种状态无法构造，编译期即拒绝。

1. 单选文件夹：使用该文件夹。
2. 单选文件：使用其父目录。
3. 没有选择：使用 Finder 前台窗口的当前目录。
4. 多选：使用 Finder 前台窗口的当前目录。
5. Finder 没有窗口：使用桌面目录。

## 实现

### 模块布局

`Shared/` 是单一 Swift package target（`Cd2HereCore`）。Foundation-only 与 AppKit-dependent 代码以**文件边界**分隔，不分包：

| 文件 | 仅 Foundation? | 含 AppKit? |
| --- | --- | --- |
| `TerminalController.swift` | 是 | — |
| `FinderContext.swift` | 是 | — |
| `AppleScriptExecutor.swift` | 是 | — |
| `AppleScriptLiteral.swift` | 是 | — |
| `CommandExecutor.swift` | 是 | — |
| `BinaryLocator.swift` | 是 | — |
| `Cd2HereError.swift` | 是 | — |
| `ShellLiteral.swift` | 是 | — |
| 6 个 `*TerminalController.swift` | 是 | — |
| `TerminalKindUI.swift` | — | 是（`NSWorkspace.urlForApplication`） |
| `TerminalPreferences.swift` | 是（UserDefaults） | — |
| `AppRunner.swift` | — | 是（`NSApplication`、`NSAlert`） |
| `TerminalPicker.swift` | — | 是（`NSAlert`、`NSPopUpButton`） |

### 步骤

1. 使用 Swift Package 提供 `Cd2HereCore` 和单元测试。
2. 在 `Shared/` 中实现 Finder context、终端 backend、共享偏好、终端选择器、应用流程和错误处理。
3. 为 `cd2hereWindow` 和 `cd2hereTab` 提供极小的入口和各自的 property list。
4. 通过纳入版本控制的 XcodeGen 配置生成并保留 Xcode 工程。
5. 配置 Apple Events 用途说明、自动化 entitlement、Hardened Runtime，以及兼容本地和 ad-hoc 签名的构建方式。
6. 提供适合开源项目的中英文 README、MIT License 和 `.gitignore`。

### Backend 子协议

`TerminalControlling` 拆成两个带默认实现的子协议：

- `AppleScriptTerminalControlling` —— 声明 `static func script(mode:directory:) -> String`；`open` 与 `isCompatible` 由默认扩展走 `AppleScriptExecutor`。用于 Ghostty / iTerm2 / Terminal.app。
- `CLITerminalControlling` —— 声明 `binaryName`、`executor`、`binaryLocator`、`arguments(mode:directory:)`；`open`（检查 binary + 执行）与 `isCompatible`（`binaryLocator() != nil`）由默认扩展实现。用于 WezTerm / Alacritty / Kitty。

新增一个 backend 因此只需实现这两个协议之一，加上 `TerminalKind` 的 4 处 switch。

### 进程模型

`CommandExecuting.run` 走 fire-and-forget：仅在 spawn 失败时 throw，非零退出由 `ProcessTracker` + `terminationHandler` 异步 NSLog。这是 CLI 终端主进程即 GUI 窗口（Alacritty、Kitty、WezTerm `start`）的必然要求。`BinaryLocator.locateViaWhich` 保持同步，因为判断"是否找到"需要 exit code。

## 交互

1. 第一次启动或保存的终端已不存在：显示终端选择对话框。
2. 普通点击：直接使用保存的终端打开。
3. Option 点击：显示选择对话框、保存新选择并执行本次打开操作。
4. 未安装的终端仍显示在选择对话框中，但不可选择。

`TerminalKind.option` 通过 static `[TerminalKind: TerminalOption]` 字典缓存（`@MainActor`），同一会话内多次访问不重复探测。

## 验证

- 对 Finder 路径规则、backend 脚本编译、转义、终端选择策略、`CommandExecutor` fire-and-forget、`option` 缓存等运行 Swift Package 测试。
- 在不配置 Development Team 的条件下构建两个 app target。
- 检查生成的 app bundle、property list、图标和 entitlement。
- 静态检查是否意外引入 SwiftUI、网络、daemon 或 shell 选择逻辑。
- 确认英文与简体中文文档描述的用户行为一致。

### 已验证 vs 未验证的 backend

Ghostty、iTerm2 与 Terminal.app 由维护者在真实机器上手工测试过。WezTerm、Alacritty 与 Kitty 仅由单元测试覆盖，因为维护者的机器上未安装这三个终端。单元测试只验证生成的 AppleScript 或 argv 在语法层面合法，不能验证终端是否真的接受这些参数、remote-control socket 是否可达，或者启动的进程是否真的会切换目录。这一边界在面向用户的 README 的"已验证的 backend"小节有明确说明。

### 手动发布验收矩阵

- Finder 状态：单选文件夹、单选文件、无选择、多选，以及 Finder 无窗口。
- 目录位置：本地目录、iCloud Drive、OneDrive 或其他 File Provider 域、网络卷，以及可移动卷。
- 终端与模式：每个受支持 backend 的 window 和 tab 模式，包括终端无窗口时的 tab fallback。
- 交互：首次启动、普通点击、Option 点击、取消选择、已保存终端被卸载，以及终端已安装但接口不兼容。
- 权限：首次 Automation 提示、拒绝 Automation 权限，以及所选终端被拒绝“文件与文件夹”权限。
- 路径：空格、引号、非 ASCII 字符，以及 Finder 返回路径后卷变为不可用。

## 已知的集成边界

自动测试覆盖路径策略、终端选择策略、转义和脚本构造。Finder 与终端的端到端自动化仍需要登录状态下的 macOS GUI 会话，以及用户批准的 Apple Events 权限。iTerm2 backend 会向默认 profile 的 session 发送 `cd <path> && clear`，因此默认 profile 应启动本地交互式 shell。
