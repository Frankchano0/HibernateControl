# HibernateControl

[中文](#中文) · [English](#english)

---

## 中文

### 为什么需要它？

macOS 的休眠管理隐藏在终端命令 `pmset` 背后，普通用户几乎无从下手：

- 系统偏好设置里只有简单的"几分钟后关闭显示器"，**看不到 hibernatemode、standby、disablesleep 等关键参数**
- 不知道当前到底是"纯内存睡眠"还是"深度休眠"，断电后数据是否安全？
- 合盖后到底有没有休眠？显示"已启用"但 caffeinate 进程可能正在偷偷阻止
- 想改一个设置，需要查文档、敲命令、还要记住十几个参数名

**HibernateControl 把这些全部可视化**，菜单栏一点，所有状态一览无余，改完即应用。

---

macOS 菜单栏电源管理工具，无需终端，直观控制系统休眠、磁盘休眠、合盖行为、休眠模式与电源键行为，并提供可展开的系统配置实时状态面板。

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Chip](https://img.shields.io/badge/chip-Apple%20Silicon-green)
![Version](https://img.shields.io/badge/version-v5.0-orange)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

---

### 功能一览

| 功能 | 说明 |
|------|------|
| 🌙 **自动休眠** | 系统 / 显示器休眠计时器（永不 或 自定义分钟数，分电池 / 充电分别设置） |
| 💾 **磁盘休眠** | 磁盘空闲多久后停转（0 = 永不） |
| 💻 **合盖行为** | 合盖后继续运行（caffeinate）或 正常进入休眠 |
| 😴 **休眠模式** | 三种模式切换，附唤醒速度 / 断电保护 / 待机耗电说明，支持立即执行 |
| 🔘 **电源键行为** | 短按电源键：关闭屏幕 或 进入睡眠 |
| 📋 **系统配置** | 结构化展示当前 pmset 实际状态，每行可展开查看系统指令与白话解读 |
| 🌐 **语言切换** | 右键状态栏图标，一键切换中文 / English |

---

### 休眠模式详解

| 模式 | pmset 值 | 唤醒速度 | 断电保护 | 待机耗电 | 适合场景 |
|------|----------|---------|---------|---------|---------|
| **纯内存** | 0 | 极快（<1s） | ❌ 断电丢数据 | 正常（内存供电） | 短时休眠、频繁唤醒 |
| **混合**（默认） | 3 | 快（<2s） | ✅ 磁盘有备份 | 正常 | 日常使用推荐 |
| **深度休眠** | 25 | 慢（10–30s） | ✅ 内存完全写盘 | 极低（RAM 断电） | 长时间不用、省电优先 |

---

### 系统配置面板

展开后分四组实时显示当前系统状态：

- **合盖行为** — 合盖是否休眠、休眠期间网络状态
- **电源键行为** — 短按电源键触发动作
- **休眠模式** — 当前 hibernatemode 值、深度待机是否生效
- **自动休眠计时器** — 系统 / 显示器 / 磁盘的闲置超时，自动识别"被程序阻止"状态（如 caffeinate）

每一行点击可展开，显示：
```
▸ pmset -g | grep hibernatemode  → 3
  0=纯内存（唤醒最快，断电丢失）  3=混合（默认，断电安全）  25=深度（RAM断电，零耗电）
```

---

### 安装

**方式一：下载 DMG（推荐）**

1. 前往 [Releases](../../releases) 页面下载最新的 `HibernateControl_v5.0.dmg`
2. 双击打开 DMG，将 `HibernateControl.app` 拖到「应用程序」文件夹
3. 点击菜单栏的盾牌图标即可使用

**方式二：从源码编译**

```bash
git clone https://github.com/Frankchano0/HibernateControl.git
cd HibernateControl
swiftc -sdk $(xcrun --show-sdk-path) -target arm64-apple-macos13.0 \
  -framework SwiftUI -framework AppKit -framework Foundation \
  -parse-as-library \
  HibernateControlApp.swift LanguageManager.swift ContentView.swift \
  HibernateViewModel.swift ShellHelper.swift \
  -o HibernateControl.app/Contents/MacOS/HibernateControl
open HibernateControl.app
```

---

### ⚠️ 常见问题

**「无法打开，因为无法验证开发者」**

右键点击 app → 选择「打开」→ 弹窗中点击「打开」

**「已损坏，无法打开」**

```bash
sudo xattr -cr /Applications/HibernateControl.app
```

**点击「应用」弹出密码框**

修改 pmset 电源设置需要管理员权限，输入 Mac 登录密码即可，这是 macOS 系统要求。

---

### 系统要求

- macOS 13.0 (Ventura) 或更高
- Apple Silicon（M1 / M2 / M3 / M4）

---

## English

### Why does this exist?

macOS sleep management is powerful but completely hidden from normal users:

- System Preferences only shows a basic "turn off display after X minutes" slider — **there's no UI for hibernatemode, standby, disablesleep, or any of the parameters that actually matter**
- You can't tell whether your Mac is doing a fast RAM sleep or a safe deep hibernate — so if the battery dies overnight, will your work survive?
- "Sleep on lid close" sounds simple, but a background process like caffeinate could be silently blocking it — and macOS won't tell you
- Making any change requires digging through man pages, memorizing a dozen `pmset` flag names, and running Terminal commands with sudo

**HibernateControl puts everything in a menu bar icon.** See the real system state at a glance, change settings with a click, and understand exactly what each option does — no Terminal required.

---

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Chip](https://img.shields.io/badge/chip-Apple%20Silicon-green)
![Version](https://img.shields.io/badge/version-v5.0-orange)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

---

### Features

| Feature | Description |
|---------|-------------|
| 🌙 **Auto Sleep** | Set system / display sleep timer per power source (battery vs charging) or disable entirely |
| 💾 **Disk Hibernate** | Control idle spin-down time (0 = never) |
| 💻 **Lid Behavior** | Stay awake on lid close (via caffeinate) or sleep normally |
| 😴 **Hibernate Mode** | Switch between 3 modes with speed / safety / power metrics; execute immediately |
| 🔘 **Power Button** | Short press: turn off display only, or put system to sleep |
| 📋 **System Config** | Structured live view of pmset state; tap any row to expand the terminal command + plain-English explanation |
| 🌐 **Language** | Right-click the menu bar icon to switch Chinese / English |

---

### Hibernate Mode Reference

| Mode | pmset | Wake speed | Power-loss safe | Idle power | Best for |
|------|-------|-----------|----------------|-----------|---------|
| **RAM Only** | 0 | Fastest (<1s) | ❌ Data lost | Normal (RAM on) | Frequent naps |
| **Hybrid** (default) | 3 | Fast (<2s) | ✅ Disk backup | Normal | Daily use |
| **Deep Hibernate** | 25 | Slow (10–30s) | ✅ Full RAM dump | Minimal (RAM off) | Long trips / max battery |

---

### System Config Panel

Expands to show four groups of live system state:

- **Lid Behavior** — whether lid close triggers sleep, network state during sleep
- **Power Button** — what short press does
- **Hibernate Mode** — active hibernatemode value, whether deep standby is actually effective
- **Auto-sleep Timers** — system / display / disk timeouts; automatically flags "blocked by process" states (e.g. caffeinate)

Tap any row to expand:
```
▸ pmset -g | grep hibernatemode  → 3
  0=RAM only (fastest)  3=Hybrid (default, safe)  25=Deep (RAM off, zero draw)
```

---

### Installation

**Option 1: Download DMG (recommended)**

1. Go to [Releases](../../releases) and download `HibernateControl_v5.0.dmg`
2. Open the DMG and drag `HibernateControl.app` to your Applications folder
3. Click the shield icon in the menu bar to get started

**Option 2: Build from source**

```bash
git clone https://github.com/Frankchano0/HibernateControl.git
cd HibernateControl
swiftc -sdk $(xcrun --show-sdk-path) -target arm64-apple-macos13.0 \
  -framework SwiftUI -framework AppKit -framework Foundation \
  -parse-as-library \
  HibernateControlApp.swift LanguageManager.swift ContentView.swift \
  HibernateViewModel.swift ShellHelper.swift \
  -o HibernateControl.app/Contents/MacOS/HibernateControl
open HibernateControl.app
```

---

### ⚠️ Troubleshooting

**"Cannot be opened because the developer cannot be verified"**

Right-click the app → Open → click **Open** in the dialog.

**"The app is damaged and can't be opened"**

```bash
sudo xattr -cr /Applications/HibernateControl.app
```

**Password prompt when clicking Apply**

Modifying pmset requires admin privileges — this is a macOS requirement. Enter your Mac login password to proceed.

---

### Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon (M1 / M2 / M3 / M4)

---

## Tech Stack

- **SwiftUI + AppKit** — native macOS menu bar app (NSStatusItem + NSPopover)
- `pmset` — power management commands
- `caffeinate` — lid-open / stay-awake mode
- `defaults` — power button behavior (`PowerButtonSleepsSystem`)
- AppleScript — admin privilege prompts

## License

MIT
