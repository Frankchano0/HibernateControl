# HibernateControl

macOS 菜单栏电源管理工具，轻松控制系统睡眠、磁盘休眠、合盖行为和电源键休眠。

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Chip](https://img.shields.io/badge/chip-Apple%20Silicon-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

## 功能

| 功能 | 说明 |
|------|------|
| 🌙 睡眠模式 | 系统/显示器睡眠时间（永不 或 自定义分钟数） |
| 💾 磁盘睡眠 | 磁盘空闲休眠时间 |
| 💻 合盖行为 | 合盖后继续运行 或 正常睡眠 |
| ⚡️ 电源键休眠 | 按下电源键触发深度磁盘休眠（hibernatemode 25） |
| 📊 系统状态 | 查看当前 pmset 电源状态（带中文注释） |

## 行为说明

各选项组合下的实际执行效果：

```
合盖行为 × 电源键休眠
│
├── 合盖睡眠 + 电源键休眠关闭（默认）
│   ├── pmset: hibernatemode=3, disablesleep=0
│   ├── 合盖      → 普通睡眠，内存保持供电，唤醒快
│   └── 按电源键  → 普通睡眠，内存保持供电，唤醒快
│
├── 合盖睡眠 + 电源键休眠开启
│   ├── pmset: hibernatemode=25, disablesleep=0
│   ├── 合盖      → 深度休眠，内存写盘断电，零耗电
│   └── 按电源键  → 深度休眠，内存写盘断电，零耗电
│
├── 合盖不睡眠 + 电源键休眠关闭
│   ├── pmset: hibernatemode=0, disablesleep=1 + caffeinate
│   ├── 合盖      → 保持运行，不睡眠 ✅（disablesleep=1 全封）
│   └── 按电源键  → 保持运行，不睡眠（disablesleep=1 同时阻止电源键）
│
└── 合盖不睡眠 + 电源键休眠开启
    ├── pmset: hibernatemode=25, disablesleep=0 + caffeinate
    ├── 合盖      → 保持运行，不睡眠 ✅（caffeinate 防止自动睡眠）
    └── 按电源键  → 深度休眠，内存写盘断电，零耗电 ✅
```

> **注意**：「合盖不睡眠 + 电源键休眠开启」组合中，合盖不睡眠依靠 caffeinate 进程实现
> （不使用 disablesleep=1，以保留电源键路径）。caffeinate 在极少数情况下可能被系统中止，
> 此时合盖会触发深度休眠而非保持运行。如需100%确保合盖不睡眠，请关闭「电源键休眠」。

## 安装

### 方式一：下载 DMG（推荐）

1. 前往 [Releases](../../releases) 页面下载最新的 `HibernateControl.dmg`
2. 双击打开 DMG，将 `HibernateControl.app` 拖到**应用程序**文件夹
3. 点击菜单栏的 ⚡️ 图标即可使用

### 方式二：从源码编译

```bash
git clone https://github.com/Frankchano0/HibernateControl.git
cd HibernateControl
swiftc -sdk $(xcrun --show-sdk-path) -target arm64-apple-macosx14.0 \
  -framework SwiftUI -framework AppKit -framework Foundation \
  HibernateControlApp.swift ContentView.swift HibernateViewModel.swift ShellHelper.swift \
  -o HibernateControl.app/Contents/MacOS/HibernateControl
codesign -s - --force --deep HibernateControl.app
open HibernateControl.app
```

## ⚠️ 常见问题

### "无法打开，因为无法验证开发者"

**右键点击** app → 选择 **"打开"** → 弹窗中点击 **"打开"**

或者：系统设置 → 隐私与安全性 → 向下滚动 → 点击"仍要打开"

### "已损坏，无法打开"

打开终端，**复制粘贴以下一整行命令**：

```bash
sudo xattr -cr /Applications/HibernateControl.app
```

输入 Mac 登录密码后回车，然后重新打开即可。

### 点击应用没反应

应用需要管理员权限修改系统设置，弹出密码框时请输入 Mac 登录密码。

## 系统要求

- macOS 14.0 (Sonoma) 或更高
- Apple Silicon (M1/M2/M3/M4)

## 技术实现

- **SwiftUI + AppKit** 原生 macOS 菜单栏应用（NSStatusItem + NSPopover）
- 通过 `pmset` 命令管理电源设置
- 通过 `caffeinate` 进程实现合盖不睡眠
- AppleScript 获取管理员权限

## License

MIT
