# HibernateControl

[中文](#中文) · [English](#english)

---

## 中文

### 为什么需要它？

macOS 的电源管理隐藏在终端命令 `pmset` 背后，普通用户几乎无从下手：

- 系统偏好设置只有简单的"几分钟后关闭显示器"，**看不到 hibernatemode、standby、disablesleep 等关键参数**
- 不知道当前是"纯内存睡眠"还是"深度休眠"，断电后数据是否安全？
- 合盖后合上电脑放进书包，后台进程（微信、Chrome、iOA）会持续唤醒系统、发热耗电
- 按下电源键但电脑没睡——因为某个 App 偷偷持有 sleep assertion 在阻止

**HibernateControl 把这些全部可视化**，菜单栏一点，所有状态一览无余，改完即应用。

---

macOS 菜单栏电源管理工具，无需终端，直观控制睡眠行为、合盖行为、休眠深度与电源键行为，提供实时系统配置面板，并内置多项防止意外唤醒的安全机制。

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Chip](https://img.shields.io/badge/chip-Apple%20Silicon-green)
![Version](https://img.shields.io/badge/version-v6.0-orange)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

---

### 功能一览

| 功能 | 说明 |
|------|------|
| 🌙 **自动睡眠** | 系统闲置多久后自动睡眠（永不 或 自定义分钟数，分电池 / 充电设置） |
| 🔒 **自动锁屏** | 屏幕闲置多久后关闭并锁定 |
| 💻 **合盖行为** | 合盖后正常睡眠 或 保持运行（caffeinate） |
| 🔘 **电源键行为** | 短按电源键：锁屏 或 进入睡眠 |
| 😴 **睡眠深度** | 三种模式，附唤醒速度 / 断电保护 / 待机耗电说明；选「休眠」自动关闭所有唤醒源 |
| 📋 **系统配置** | 结构化实时展示当前 pmset 状态，含一句话总结，每行可展开查看指令与白话解读 |
| 🌐 **语言切换** | 右键状态栏图标，一键切换中文 / English |

---

### 右键菜单快捷操作

| 操作 | 快捷键 | 说明 |
|------|--------|------|
| 立即休眠 | **⌥⌘S** | 按当前睡眠深度立即入睡 |
| 睡眠+关闭唤醒源 | — | mode 3 混合睡眠 + 关闭 womp/powernap/tcpkeepalive，放书包专用 |
| 立即锁屏 | **⌥⌘L** | 触发系统锁屏（Ctrl+Cmd+Q） |
| 关闭屏幕 | — | `pmset displaysleepnow` |
| 清除睡眠阻止源 | — | 自动扫描并释放所有阻止睡眠的第三方进程，之后电源键可正常入睡 |
| 键盘清洁 | — | 锁定键盘输入，清洁键盘时防止误触 |
| 触控板清洁 | **⌥⌘T** | 锁定触控板/鼠标，30 秒后自动恢复或随时按 ⌥⌘T 解锁 |

---

### 睡眠深度详解

| 模式 | pmset 值 | 唤醒速度 | 断电保护 | 待机耗电 | 唤醒源 | 适合场景 |
|------|----------|---------|---------|---------|--------|---------|
| **睡眠** | 0 | 极快（<1s） | ❌ 断电丢数据 | 正常（RAM 供电） | 所有 | 频繁唤醒 |
| **混合**（默认） | 3 | 快（<2s） | ✅ 磁盘有备份 | 正常 | 所有 | 日常使用 |
| **休眠** | 25 | 慢（10–30s） | ✅ 内存完全写盘 | 极低（RAM 断电）| **仅物理操作** | 放书包、长时间不用 |

> **选「休眠」模式后，App 会自动关闭 `womp`、`powernap`、`tcpkeepalive`。**
> 合盖放进书包后，微信/iCloud/Chrome 等不会再唤醒系统，不发热不耗电。

---

### 为什么按电源键没反应？

常见原因：某个 App（Chrome 音频服务、腾讯 iOA、QClaw 等）持有 `NoIdleSleepAssertion`，阻止系统睡眠。

**解决方法：** 右键菜单 → 「清除睡眠阻止源」，再按电源键即可。

---

### 系统配置面板

展开后显示当前系统状态一句话总结，以及分组实时数据：

- **合盖行为** — 合盖是否睡眠、睡眠期间网络状态
- **电源键行为** — 短按触发动作
- **睡眠深度** — 当前 hibernatemode 值、超长待机是否生效
- **自动睡眠计时器** — 系统 / 显示器 / 磁盘的闲置超时，自动识别"被程序阻止"状态

每一行点击可展开：
```
▸ pmset -g | grep hibernatemode  → 3
  0=睡眠（唤醒最快，断电丢失）  3=混合（默认，断电安全）  25=休眠（RAM断电，零耗电）
```

---

### 安装

**方式一：下载 DMG（推荐）**

1. 前往 [Releases](../../releases) 页面下载最新的 `HibernateControl_v6.0.dmg`
2. 双击打开 DMG，将 `HibernateControl.app` 拖到「应用程序」文件夹
3. 点击菜单栏图标即可使用

**方式二：从源码编译**

```bash
git clone https://github.com/Frankchano0/HibernateControl.git
cd HibernateControl
swiftc -O -sdk $(xcrun --show-sdk-path) -target arm64-apple-macos14.0 \
  -parse-as-library \
  ContentView.swift HibernateControlApp.swift HibernateViewModel.swift \
  ShellHelper.swift KeyboardCleaner.swift TrackpadCleaner.swift LanguageManager.swift \
  -o HibernateControl.app/Contents/MacOS/HibernateControl
open HibernateControl.app
```

---

### ⚠️ 常见问题

**「无法打开，因为无法验证开发者」**

第一次打开时，不要直接双击。右键点击 app → 选择「打开」→ 弹窗中点击「打开」。
只需操作一次，以后就能直接打开。

或者，用终端命令移除隔离标记后就能直接打开：
```bash
sudo xattr -cr /Applications/HibernateControl.app
```

**「已损坏，无法打开」**

```bash
sudo xattr -cr /Applications/HibernateControl.app
```

**点击「应用」弹出密码框**

修改 pmset 电源设置需要管理员权限，输入 Mac 登录密码即可，这是 macOS 系统要求。

**触控板清洁后鼠标失效**

按 **⌥⌘T** 解锁，或等 30 秒自动恢复。

---

### 系统要求

- macOS 14.0 (Sonoma) 或更高
- Apple Silicon（M1 / M2 / M3 / M4 / M5）

---

## English

### Why does this exist?

macOS power management is powerful but completely hidden from normal users:

- System Preferences only shows a basic slider — **no UI for hibernatemode, standby, disablesleep, or the parameters that actually matter**
- You can't tell if your Mac is doing a fast RAM sleep or a safe deep hibernate
- Close the lid and put it in your bag — background processes (WeChat, Chrome, iOA) keep waking the system, generating heat and draining battery
- Press the power button but the Mac doesn't sleep — because some app is silently holding a sleep assertion

**HibernateControl puts everything in a menu bar icon.** Real system state at a glance, one-click changes, and a built-in tool to clear whatever is blocking sleep.

---

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Chip](https://img.shields.io/badge/chip-Apple%20Silicon-green)
![Version](https://img.shields.io/badge/version-v6.0-orange)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

---

### Features

| Feature | Description |
|---------|-------------|
| 🌙 **Auto Sleep** | Set system idle sleep timer per power source, or disable entirely |
| 🔒 **Auto Lock** | Control display sleep / lock timeout independently |
| 💻 **Lid Behavior** | Sleep on lid close, or stay awake via caffeinate |
| 🔘 **Power Button** | Short press: lock screen or put system to sleep |
| 😴 **Sleep Depth** | Three modes with speed/safety/power metrics; selecting Hibernate auto-disables all wake sources |
| 📋 **System Config** | Live structured pmset state with one-line summary; tap any row to expand the command + plain-English explanation |
| 🌐 **Language** | Right-click menu bar icon to switch Chinese / English |

---

### Right-click Menu

| Action | Shortcut | Description |
|--------|----------|-------------|
| Sleep Now | **⌥⌘S** | Sleep immediately using current depth setting |
| Sleep (No Wake) | — | Hybrid sleep + disable womp/powernap/tcpkeepalive — safe for bags |
| Lock Screen | **⌥⌘L** | Triggers system lock (Ctrl+Cmd+Q) |
| Display Off | — | `pmset displaysleepnow` |
| Clear Sleep Blockers | — | Scans pmset assertions and releases all third-party blockers so the power button works |
| Keyboard Clean | — | Blocks keyboard input while cleaning |
| Trackpad Clean | **⌥⌘T** | Blocks mouse/trackpad; auto-restores after 30s or press ⌥⌘T to unlock |

---

### Sleep Depth Reference

| Mode | pmset | Wake speed | Power-loss safe | Idle power | Wake sources | Best for |
|------|-------|-----------|----------------|-----------|-------------|---------|
| **Sleep** | 0 | Fastest (<1s) | ❌ Data lost | Normal (RAM on) | All | Frequent naps |
| **Hybrid** (default) | 3 | Fast (<2s) | ✅ Disk backup | Normal | All | Daily use |
| **Hibernate** | 25 | Slow (10–30s) | ✅ Full RAM dump | Minimal (RAM off) | **Physical only** | Bag / long trips |

> **Selecting Hibernate automatically disables `womp`, `powernap`, and `tcpkeepalive`.**
> Once in the bag, nothing — not WeChat, iCloud, or Chrome — can wake the machine.

---

### Why doesn't the power button work?

A third-party app (Chrome audio service, Tencent iOA, QClaw, etc.) is likely holding a `NoIdleSleepAssertion`.

**Fix:** Right-click menu → **Clear Sleep Blockers**, then press the power button.

---

### Installation

**Option 1: Download DMG (recommended)**

1. Go to [Releases](../../releases) and download `HibernateControl_v6.0.dmg`
2. Open the DMG and drag `HibernateControl.app` to Applications
3. Click the menu bar icon to get started

**Option 2: Build from source**

```bash
git clone https://github.com/Frankchano0/HibernateControl.git
cd HibernateControl
swiftc -O -sdk $(xcrun --show-sdk-path) -target arm64-apple-macos14.0 \
  -parse-as-library \
  ContentView.swift HibernateControlApp.swift HibernateViewModel.swift \
  ShellHelper.swift KeyboardCleaner.swift TrackpadCleaner.swift LanguageManager.swift \
  -o HibernateControl.app/Contents/MacOS/HibernateControl
open HibernateControl.app
```

---

### ⚠️ Troubleshooting

**"Cannot be opened because the developer cannot be verified"**

The first time you open the app, don't double-click. Right-click → Open → click **Open**.
You only need to do this once; after that it opens normally.

Or, remove quarantine from the terminal to skip this:
```bash
sudo xattr -cr /Applications/HibernateControl.app
```

**"The app is damaged and can't be opened"**

```bash
sudo xattr -cr /Applications/HibernateControl.app
```

**Password prompt when clicking Apply**

Modifying pmset requires admin privileges — enter your Mac login password to proceed.

**Trackpad/mouse stopped working after Trackpad Clean**

Press **⌥⌘T** to unlock immediately, or wait 30 seconds for auto-restore.

---

### Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1 / M2 / M3 / M4 / M5)

---

## Tech Stack

- **SwiftUI + AppKit** — native macOS menu bar app (NSStatusItem + NSPopover)
- `pmset` — power management commands
- `caffeinate` — stay-awake mode
- `CGEventTap` — keyboard / trackpad cleaning
- `defaults` — power button behavior (`PowerButtonSleepsSystem`)
- AppleScript — admin privilege prompts & lock screen

## License

MIT
