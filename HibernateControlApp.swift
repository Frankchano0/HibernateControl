import SwiftUI

// MARK: - App Entry Point（应用入口）
// HibernateControl 的启动入口。
// @main 标记使其成为应用程序的主入口点。
// 创建一个固定大小的窗口（.contentSize 禁止用户手动缩放），
// 窗口内容为 ContentView 主界面。

@main
struct HibernateControlApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)  // 窗口大小固定为内容尺寸，不可拖拽调整
    }
}
