import SwiftUI
import AppKit

// MARK: - App Delegate（菜单栏应用委托）
// 使用 NSStatusItem + NSPopover 实现状态栏图标弹出面板，
// 比 SwiftUI MenuBarExtra 更稳定可靠。

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 创建状态栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.shield.fill", accessibilityDescription: "HibernateControl")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // 创建 Popover
        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 600)
        popover.behavior = .transient   // 点击外部自动关闭
        popover.contentViewController = NSHostingController(rootView: ContentView())
        popover.animates = true
    }

    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// MARK: - App Entry Point

@main
struct HibernateControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 纯菜单栏 app，不需要 WindowGroup
        Settings { EmptyView() }
    }
}
