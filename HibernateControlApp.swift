import SwiftUI
import AppKit

// MARK: - App Delegate
// 左键点击状态栏图标 → 弹出操作面板
// 右键点击状态栏图标 → 弹出菜单（切换语言 / 退出）

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let langManager = LanguageManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "bolt.shield.fill", accessibilityDescription: "HibernateControl")
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 400, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(langManager)
        )
        popover.animates = true
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
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

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
        statusItem.menu = nil  // 用完即清，避免影响左键行为
    }

    @objc private func toggleLanguage() {
        langManager.isEnglish.toggle()
        // 切换语言后刷新 popover 内容
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(langManager)
        )
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
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
