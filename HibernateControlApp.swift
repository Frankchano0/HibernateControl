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
            case 37: // L → 关闭屏幕
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
                p.arguments = ["displaysleepnow"]
                try? p.run()
            default: break
            }
        }
    }

    @objc func handleClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
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

        // 立即休眠
        let sleepTitle = langManager.isEnglish ? "Sleep Now  ⌥⌘S" : "立即休眠  ⌥⌘S"
        let sleepItem = NSMenuItem(title: sleepTitle, action: #selector(sleepNow), keyEquivalent: "")
        sleepItem.target = self
        menu.addItem(sleepItem)

        // 关闭屏幕
        let displayTitle = langManager.isEnglish ? "Display Off  ⌥⌘L" : "关闭屏幕  ⌥⌘L"
        let displayItem = NSMenuItem(title: displayTitle, action: #selector(displaySleepNow), keyEquivalent: "")
        displayItem.target = self
        menu.addItem(displayItem)

        menu.addItem(.separator())

        // 语言切换
        let langTitle = langManager.isEnglish ? "切换为中文" : "Switch to English"
        let langItem = NSMenuItem(title: langTitle, action: #selector(toggleLanguage), keyEquivalent: "")
        langItem.target = self
        menu.addItem(langItem)

        menu.addItem(.separator())

        // 退出
        let quitTitle = langManager.isEnglish ? "Quit" : "退出"
        let quitItem = NSMenuItem(title: quitTitle, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func sleepNow() {
        Task { await viewModel.sleepNow() }
    }

    @objc private func displaySleepNow() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
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
        if let monitor = globalHotKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-f", "caffeinate"]
        try? task.run()
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
