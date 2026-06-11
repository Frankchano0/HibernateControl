import Foundation
import CoreGraphics
import AppKit

// MARK: - CGEventTap C 回调（必须是 file-scope 函数，不能用 closure）
// 直接返回 nil 丢弃所有键盘事件
private func keyboardTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent?,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    return nil  // 丢弃事件
}

// MARK: - KeyboardCleaner
// 通过 CGEventTap（cgSessionEventTap）拦截并丢弃所有键盘事件。
// cgSessionEventTap：在用户会话层拦截，只需辅助功能权限即可，无需额外 Input Monitoring 权限。

final class KeyboardCleaner {

    static let shared = KeyboardCleaner()

    /// 当前是否处于键盘锁定状态
    private(set) var isActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init() {}

    // MARK: - Start

    func start() {
        guard !isActive else { return }

        // 权限检查
        guard AXIsProcessTrusted() else {
            showAccessibilityAlert()
            return
        }

        let eventsOfInterest: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,        // ← session 层，只需辅助功能权限
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: keyboardTapCallback,  // ← file-scope C 函数，不是 closure
            userInfo: nil
        ) else {
            showTapFailedAlert()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        isActive = true
    }

    // MARK: - Stop

    func stop() {
        guard isActive, let tap = eventTap else { return }

        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        eventTap = nil
        isActive = false
    }

    // MARK: - Alerts

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "需要辅助功能权限"
        alert.informativeText = "请前往「系统设置 → 隐私与安全性 → 辅助功能」，允许 HibernateControl，然后重启 App。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }

    private func showTapFailedAlert() {
        let alert = NSAlert()
        alert.messageText = "键盘清洁启动失败"
        alert.informativeText = "无法创建键盘拦截器。请确认已在「系统设置 → 隐私与安全性 → 辅助功能」中授权 HibernateControl，然后重启 App。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "关闭")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            )
        }
    }
}
