import SwiftUI
import AppKit
import Carbon

// MARK: - App Delegate
// 左键点击状态栏图标 → 弹出操作面板
// 右键点击状态栏图标 → 弹出菜单（切换语言 / 退出）
// 全局快捷键 ⌥⌘S → 立即休眠

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let langManager = LanguageManager.shared
    private var viewModel: HibernateViewModel!
    private var globalHotKeyMonitor: Any?
    private var blinkTimer: Timer?
    private var blinkPhase = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewModel = HibernateViewModel()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = makeStatusBarIcon()
            button.image?.isTemplate = true
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 100)
        popover.behavior = .transient
        let hostingController = NSHostingController(
            rootView: ContentView(viewModel: viewModel).environmentObject(langManager)
        )
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        popover.contentViewController = hostingController
        popover.animates = true

        registerGlobalHotKey()
    }

    /// 注册全局快捷键：
    /// - ⌥⌘S → 立即休眠
    /// - ⌥⌘L → 关闭屏幕
    private func registerGlobalHotKey() {
        let trusted = AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        guard trusted else { return }

        globalHotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isOptCmd = event.modifierFlags.contains(.option) && event.modifierFlags.contains(.command)
            guard isOptCmd else { return }

            switch event.keyCode {
            case 1:  // S → 立即休眠
                Task { @MainActor in await self?.viewModel.sleepNow() }
            case 37: // L → 立即锁屏
                self?.lockScreenNow()
            case 17: // T → 切换触控板清洁
                if TrackpadCleaner.shared.isActive {
                    TrackpadCleaner.shared.stop()
                } else {
                    TrackpadCleaner.shared.start()
                }
            default: break
            }
        }
    }

    @objc func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            // 右键：始终弹出菜单（含 "✓ 键盘清洁中" 状态）
            showContextMenu()
        } else {
            // 左键：激活时点击即解锁；否则打开面板
            if KeyboardCleaner.shared.isActive {
                KeyboardCleaner.shared.stop()
                stopBlinkAnimation()
            } else {
                togglePopover()
            }
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // 弹出后获取底层 window，开启可拖拽 + 可调整大小
            if let window = popover.contentViewController?.view.window {
                window.makeKey()
                window.styleMask.insert(.resizable)
                window.isMovableByWindowBackground = true
                window.minSize = NSSize(width: 360, height: 200)
                window.maxSize = NSSize(width: 600, height: 1400)
                // 透明度 100%（不透明）
                window.alphaValue = 1.0
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        addMenuSection(langManager.isEnglish ? "Power" : "电源", to: menu)

        let sleepTitle = langManager.isEnglish ? "Sleep Now  ⌥⌘S" : "立即睡眠  ⌥⌘S"
        let sleepItem = NSMenuItem(title: sleepTitle, action: #selector(sleepNow), keyEquivalent: "")
        sleepItem.target = self
        menu.addItem(sleepItem)

        let bagTitle = langManager.isEnglish ? "Put in Bag (No Wake)" : "放入书包（关闭唤醒源）"
        let bagItem = NSMenuItem(title: bagTitle, action: #selector(sleepNoWake), keyEquivalent: "")
        bagItem.target = self
        menu.addItem(bagItem)

        let lockTitle = langManager.isEnglish ? "Lock Screen  ⌥⌘L" : "立即锁屏  ⌥⌘L"
        let lockItem = NSMenuItem(title: lockTitle, action: #selector(lockScreenNow), keyEquivalent: "")
        lockItem.target = self
        menu.addItem(lockItem)

        let displayTitle = langManager.isEnglish ? "Display Off" : "关闭屏幕"
        let displayItem = NSMenuItem(title: displayTitle, action: #selector(displaySleepNow), keyEquivalent: "")
        displayItem.target = self
        menu.addItem(displayItem)

        menu.addItem(.separator())
        addMenuSection(langManager.isEnglish ? "Cleaning" : "清洁", to: menu)

        let cleanTitle: String
        if langManager.isEnglish {
            cleanTitle = KeyboardCleaner.shared.isActive ? "✓ Keyboard Clean" : "Keyboard Clean"
        } else {
            cleanTitle = KeyboardCleaner.shared.isActive ? "✓ 键盘清洁中" : "键盘清洁"
        }
        let cleanItem = NSMenuItem(title: cleanTitle, action: #selector(toggleKeyboardClean), keyEquivalent: "")
        cleanItem.target = self
        menu.addItem(cleanItem)

        let trackpadTitle: String
        if langManager.isEnglish {
            trackpadTitle = TrackpadCleaner.shared.isActive ? "✓ Trackpad Clean  ⌥⌘T" : "Trackpad Clean  ⌥⌘T"
        } else {
            trackpadTitle = TrackpadCleaner.shared.isActive ? "✓ 触控板清洁中  ⌥⌘T" : "触控板清洁  ⌥⌘T"
        }
        let trackpadItem = NSMenuItem(title: trackpadTitle, action: #selector(toggleTrackpadClean), keyEquivalent: "")
        trackpadItem.target = self
        menu.addItem(trackpadItem)

        menu.addItem(.separator())
        addMenuSection(langManager.isEnglish ? "App" : "应用", to: menu)

        let langTitle = langManager.isEnglish ? "切换为中文" : "Switch to English"
        let langItem = NSMenuItem(title: langTitle, action: #selector(toggleLanguage), keyEquivalent: "")
        langItem.target = self
        menu.addItem(langItem)

        let quitTitle = langManager.isEnglish ? "Quit" : "退出"
        let quitItem = NSMenuItem(title: quitTitle, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func addMenuSection(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @objc private func sleepNow() {
        Task { await viewModel.sleepNow() }
    }

    @objc private func sleepNoWake() {
        Task { await viewModel.sleepNoWake() }
    }

    @objc private func displaySleepNow() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
    }

    @objc private func lockScreenNow() {
        // 使用系统 API 触发锁屏（等同于 Ctrl+Cmd+Q）
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"]
        try? p.run()
    }

    @objc private func toggleKeyboardClean() {
        if KeyboardCleaner.shared.isActive {
            KeyboardCleaner.shared.stop()
            stopBlinkAnimation()
        } else {
            KeyboardCleaner.shared.start()
            if KeyboardCleaner.shared.isActive {
                startBlinkAnimation()
            }
        }
    }

    @objc private func toggleTrackpadClean() {
        if TrackpadCleaner.shared.isActive {
            TrackpadCleaner.shared.stop()
        } else {
            TrackpadCleaner.shared.start()
        }
    }

    /// 开始闪烁动效：月亮图标 ↔ 锁图标，每 0.8s 切换一次
    private func startBlinkAnimation() {
        blinkPhase = false
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.blinkPhase.toggle()
            if self.blinkPhase {
                self.statusItem.button?.image = self.makeCleanActiveIcon()
            } else {
                self.statusItem.button?.image = self.makeStatusBarIcon()
            }
        }
        // 立即显示激活图标
        statusItem.button?.image = makeCleanActiveIcon()
    }

    private func stopBlinkAnimation() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        statusItem.button?.image = makeStatusBarIcon()
    }

    /// 键盘清洁激活图标：月牙 + 锁形（使用 SF Symbol lock.fill，isTemplate 自动适配深/浅色）
    private func makeCleanActiveIcon() -> NSImage {
        if let sf = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) {
            let sized = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
                sf.draw(in: rect)
                return true
            }
            sized.isTemplate = true
            return sized
        }
        // fallback：画一个简单的小锁轮廓
        return makeStatusBarIcon()
    }

    /// 用代码绘制状态栏图标：月牙 + 暂停竖条（isTemplate=true，自动适配深/浅色）
    private func makeStatusBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.setFillColor(NSColor.black.cgColor)

            let w = rect.width, h = rect.height
            let cx = w * 0.44, cy = h * 0.5

            // ── 月牙：外圆路径减去内偏移圆 ──
            let outerR: CGFloat = h * 0.42
            let innerR: CGFloat = h * 0.34
            let dx: CGFloat = h * 0.14   // 内圆向右偏移

            let outerPath = CGMutablePath()
            outerPath.addArc(center: CGPoint(x: cx, y: cy),
                             radius: outerR, startAngle: 0,
                             endAngle: .pi * 2, clockwise: false)

            let innerPath = CGMutablePath()
            innerPath.addArc(center: CGPoint(x: cx + dx, y: cy + h * 0.04),
                             radius: innerR, startAngle: 0,
                             endAngle: .pi * 2, clockwise: false)

            // 月牙 = 外圆 - 内圆（使用 even-odd 规则）
            let moonPath = CGMutablePath()
            moonPath.addPath(outerPath)
            moonPath.addPath(innerPath)
            ctx.addPath(moonPath)
            ctx.fillPath(using: .evenOdd)

            // ── 暂停竖条（右上角）──
            let barW: CGFloat = w * 0.10
            let barH: CGFloat = h * 0.34
            let barY: CGFloat = cy + h * 0.06
            let bar1X: CGFloat = w * 0.66
            let bar2X: CGFloat = w * 0.80

            let r1 = CGRect(x: bar1X - barW/2, y: barY - barH/2, width: barW, height: barH)
            let r2 = CGRect(x: bar2X - barW/2, y: barY - barH/2, width: barW, height: barH)
            ctx.fill([r1, r2])

            return true
        }
        image.isTemplate = true
        return image
    }

    @objc private func toggleLanguage() {
        langManager.isEnglish.toggle()
        popover.contentViewController = NSHostingController(
            rootView: ContentView(viewModel: viewModel).environmentObject(langManager)
        )
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        KeyboardCleaner.shared.stop()  // 确保退出时键盘解锁
        TrackpadCleaner.shared.stop()  // 确保退出时触控板解锁
        stopBlinkAnimation()
        if let monitor = globalHotKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        // caffeinate 由 ViewModel 持有并带 -w 绑定本 App 生命周期，退出时不再 broad-kill。
        // 如果当前是合盖睡眠模式，确保 disablesleep=0（允许系统正常睡眠）
        if viewModel.lidMode == .sleepOnLidClose {
            let restore = Process()
            restore.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            restore.arguments = ["-a", "disablesleep", "0"]
            try? restore.run()
        }
    }
}

// MARK: - App Entry Point

@main
struct HibernateControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
