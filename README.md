# HibernateControl

[中文](#中文) · [English](#english)

---

## 中文

macOS 菜单栏电源管理工具，轻松控制系统休眠、磁盘休眠、合盖行为和电源键休眠。

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Chip](https://img.shields.io/badge/chip-Apple%20Silicon-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

### 功能

| 功能 | 说明 |
|------|------|
| 🌙 自动休眠 | 系统/显示器休眠时间（永不 或 自定义分钟数） |
| 💾 磁盘休眠 | 磁盘空闲多久后停转 |
| 💻 合盖行为 | 合盖后继续运行 或 正常休眠 |
| ⚡️ 电源键休眠 | 按下电源键触发深度磁盘休眠（hibernatemode 25） |
| 📊 系统状态 | 查看当前 pmset 电源状态（带注释） |
| 🌐 语言切换 | 右键状态栏图标切换中文 / English |

### 行为说明

各选项组合下的实际执行效果：

```
合盖行为 × 电源键休眠
│
├── 合盖休眠 + 电源键休眠关闭（默认）
│   ├── pmset: hibernatemode=3, disablesleep=0
│   ├── 合盖      → 普通休眠，内存保持供电，唤醒快
│   └── 按电源键  → 普通休眠，内存保持供电，唤醒快
│
├── 合盖休眠 + 电源键休眠开启
│   ├── pmset: hibernatemode=25, disablesleep=0
│   ├── 合盖      → 深度休眠，内存写盘断电，零耗电
│   └── 按电源键  → 深度休眠，内存写盘断电，零耗电
│
├── 合盖不休眠 + 电源键休眠关闭
│   ├── pmset: hibernatemode=0, disablesleep=1 + caffeinate
│   ├── 合盖      → 保持运行 ✅（disablesleep=1 全封）
│   └── 按电源键  → 保持运行（disablesleep=1 同时阻止电源键）
│
└── 合盖不休眠 + 电源键休眠开启
    ├── pmset: hibernatemode=25, disablesleep=0 + caffeinate
    ├── 合盖      → 保持运行 ✅（caffeinate 防止自动休眠）
    └── 按电源键  → 深度休眠，内存写盘断电，零耗电 ✅
```

> **注意**：「合盖不休眠 + 电源键休眠开启」组合中，合盖不休眠依靠 caffeinate 进程实现（不使用 disablesleep=1，以保留电源键路径）。caffeinate 在极少数情况下可能被系统中止，此时合盖会触发深度休眠而非保持运行。如需 100% 确保合盖不休眠，请关闭「电源键休眠」。

### 安装

**方式一：下载 DMG（推荐）**

1. 前往 [Releases](../../releases) 页面下载最新的 `HibernateControl.dmg`
2. 双击打开 DMG，将 `HibernateControl.app` 拖到**应用程序**文件夹
3. 点击菜单栏的 ⚡️ 图标即可使用

**方式二：从源码编译**

```bash
git clone https://github.com/Frankchano0/HibernateControl.git
cd HibernateControl
swiftc -sdk $(xcrun --show-sdk-path) -target arm64-apple-macosx14.0 \
  -framework SwiftUI -framework AppKit -framework Foundation \
  HibernateControlApp.swift LanguageManager.swift ContentView.swift \
  HibernateViewModel.swift ShellHelper.swift \
  -o HibernateControl.app/Contents/MacOS/HibernateControl
codesign -s - --force --deep HibernateControl.app
open HibernateControl.app
```

### ⚠️ 常见问题

**"无法打开，因为无法验证开发者"**

右键点击 app → 选择「打开」→ 弹窗中点击「打开」

**"已损坏，无法打开"**

```bash
sudo xattr -cr /Applications/HibernateControl.app
```

**点击应用没反应**

应用需要管理员权限修改系统设置，弹出密码框时请输入 Mac 登录密码。

### 系统要求

- macOS 14.0 (Sonoma) 或更高
- Apple Silicon (M1/M2/M3/M4)

---

## English

A macOS menu bar utility for managing hibernate and sleep settings — no Terminal required.

### Features

| Feature | Description |
|---------|-------------|
| 🌙 Auto Sleep | Set system/display sleep timer or disable it entirely |
| 💾 Disk Hibernate | Control how long before idle disks spin down |
| 💻 Lid Behavior | Keep running on lid close, or sleep normally |
| ⚡️ Power Button Hibernate | Deep hibernate on power press (hibernatemode 25) — RAM written to disk, zero power draw |
| 📊 System State | View current pmset values with annotations |
| 🌐 Language | Right-click the menu bar icon to switch Chinese / English |

### Behavior Reference

How lid behavior and power button hibernate interact:

```
Lid Behavior × Power Button Hibernate
│
├── Sleep on Close + Power Hibernate OFF (default)
│   ├── pmset: hibernatemode=3, disablesleep=0
│   ├── Lid close   → normal sleep, RAM stays powered, fast wake
│   └── Power press → normal sleep, RAM stays powered, fast wake
│
├── Sleep on Close + Power Hibernate ON
│   ├── pmset: hibernatemode=25, disablesleep=0
│   ├── Lid close   → deep hibernate, RAM written to disk, zero draw
│   └── Power press → deep hibernate, RAM written to disk, zero draw
│
├── Stay Awake + Power Hibernate OFF
│   ├── pmset: hibernatemode=0, disablesleep=1 + caffeinate
│   ├── Lid close   → stays running ✅ (disablesleep=1 blocks all sleep)
│   └── Power press → stays running (disablesleep=1 also blocks power button)
│
└── Stay Awake + Power Hibernate ON
    ├── pmset: hibernatemode=25, disablesleep=0 + caffeinate
    ├── Lid close   → stays running ✅ (caffeinate prevents auto sleep)
    └── Power press → deep hibernate, RAM to disk, zero draw ✅
```

> **Note**: In the "Stay Awake + Power Hibernate ON" combination, lid-open behavior relies on caffeinate rather than `disablesleep=1` (to keep the power button path open). In rare cases caffeinate may be killed by the system, causing a lid-close to trigger deep hibernate instead of staying awake. For guaranteed lid-open behavior, disable Power Button Hibernate.

### Installation

**Option 1: Download DMG (recommended)**

1. Go to [Releases](../../releases) and download the latest `HibernateControl.dmg`
2. Open the DMG and drag `HibernateControl.app` to your Applications folder
3. Click the ⚡️ icon in the menu bar to get started

**Option 2: Build from source**

```bash
git clone https://github.com/Frankchano0/HibernateControl.git
cd HibernateControl
swiftc -sdk $(xcrun --show-sdk-path) -target arm64-apple-macosx14.0 \
  -framework SwiftUI -framework AppKit -framework Foundation \
  HibernateControlApp.swift LanguageManager.swift ContentView.swift \
  HibernateViewModel.swift ShellHelper.swift \
  -o HibernateControl.app/Contents/MacOS/HibernateControl
codesign -s - --force --deep HibernateControl.app
open HibernateControl.app
```

### ⚠️ Troubleshooting

**"Cannot be opened because the developer cannot be verified"**

Right-click the app → Open → click Open in the dialog.

**"The app is damaged and can't be opened"**

```bash
sudo xattr -cr /Applications/HibernateControl.app
```

**Nothing happens when I click Apply**

The app needs admin privileges to modify system settings. Enter your Mac login password when prompted.

### Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (M1/M2/M3/M4)

---

## Tech Stack

- **SwiftUI + AppKit** — native macOS menu bar app (NSStatusItem + NSPopover)
- `pmset` for power management
- `caffeinate` for lid-open mode
- AppleScript for admin privilege prompts

## License

MIT
