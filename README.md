# HibernateControl

macOS 电源管理工具，轻松控制系统睡眠、磁盘休眠和合盖行为。

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![Chip](https://img.shields.io/badge/chip-Apple%20Silicon-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

## 功能

| 功能 | 说明 |
|------|------|
| 🌙 Sleep Mode | 系统/显示器睡眠时间（永不 或 自定义分钟数） |
| 💾 Disk Sleep | 磁盘空闲休眠时间 |
| 💻 Lid Mode | 合盖后继续运行 或 正常睡眠 |
| 📊 System State | 查看当前 pmset 电源状态（带中文注释） |

## 安装

### 方式一：下载 DMG（推荐）

1. 前往 [Releases](../../releases) 页面下载最新的 `HibernateControl.dmg`
2. 双击打开 DMG，将 `HibernateControl.app` 拖到**应用程序**文件夹
3. 打开应用

### 方式二：从源码编译

```bash
git clone https://github.com/Frankchano0/HibernateControl.git
cd HibernateControl
swiftc -o HibernateControl.app/Contents/MacOS/HibernateControl \
  HibernateControlApp.swift ContentView.swift HibernateViewModel.swift ShellHelper.swift \
  -framework SwiftUI -framework AppKit -framework Foundation \
  -parse-as-library
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

### 点击 Apply 没反应

应用需要管理员权限修改系统设置，弹出密码框时请输入 Mac 登录密码。

## 系统要求

- macOS 14.0 (Sonoma) 或更高
- Apple Silicon (M1/M2/M3/M4)

## 技术实现

- **SwiftUI** 原生 macOS 应用
- 通过 `pmset` 命令管理电源设置
- 通过 `caffeinate` 进程实现合盖不睡眠
- AppleScript 获取管理员权限

## License

MIT
