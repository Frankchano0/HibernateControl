import Foundation
import CoreGraphics
import AppKit

// MARK: - CGEventTap C 回调（拦截触控板/鼠标事件）
private func trackpadTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent?,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    return nil  // 丢弃事件
}

// MARK: - TrackpadCleaner
// 通过 CGEventTap 拦截并丢弃所有鼠标/触控板事件，用于清洁触控板时防止误触。
// 安全机制：30 秒自动超时 + 键盘快捷键 ⌥⌘T 切换 + Esc 键停止

final class TrackpadCleaner {

    static let shared = TrackpadCleaner()

    /// 当前是否处于触控板锁定状态
    private(set) var isActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var autoStopTimer: Timer?

    /// 自动停止超时（秒）
    private let autoStopTimeout: TimeInterval = 30

    private init() {}

    // MARK: - Start

    func start() {
        guard !isActive else { return }

        guard AXIsProcessTrusted() else { return }

        var mask: CGEventMask = 0
        mask |= (1 << CGEventType.leftMouseDown.rawValue)
        mask |= (1 << CGEventType.leftMouseUp.rawValue)
        mask |= (1 << CGEventType.rightMouseDown.rawValue)
        mask |= (1 << CGEventType.rightMouseUp.rawValue)
        mask |= (1 << CGEventType.mouseMoved.rawValue)
        mask |= (1 << CGEventType.leftMouseDragged.rawValue)
        mask |= (1 << CGEventType.rightMouseDragged.rawValue)
        mask |= (1 << CGEventType.scrollWheel.rawValue)
        mask |= (1 << CGEventType.otherMouseDown.rawValue)
        mask |= (1 << CGEventType.otherMouseUp.rawValue)
        mask |= (1 << CGEventType.otherMouseDragged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: trackpadTapCallback,
            userInfo: nil
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        isActive = true

        // 安全机制：30 秒后自动停止，避免用户被锁死
        autoStopTimer = Timer.scheduledTimer(withTimeInterval: autoStopTimeout, repeats: false) { [weak self] _ in
            self?.stop()
            // 通知用户已自动恢复
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "触控板清洁已自动结束"
                alert.informativeText = "30 秒已到，触控板已恢复正常。"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "好的")
                alert.runModal()
            }
        }

        // 显示提示对话框
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "触控板已锁定（清洁模式）"
            alert.informativeText = "请用键盘操作：\n• 按 ⌥⌘T 提前停止\n• 30 秒后自动恢复"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "知道了")
            alert.runModal()
        }
    }

    // MARK: - Stop

    func stop() {
        guard isActive, let tap = eventTap else { return }

        autoStopTimer?.invalidate()
        autoStopTimer = nil

        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        eventTap = nil
        isActive = false
    }
}
