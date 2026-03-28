import Foundation
import SwiftUI

// MARK: - Language Manager
// 管理应用语言（中文 / English），持久化到 UserDefaults。
// 通过 @EnvironmentObject 注入所有视图。

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()

    @Published var isEnglish: Bool {
        didSet { UserDefaults.standard.set(isEnglish, forKey: "isEnglish") }
    }

    private init() {
        self.isEnglish = UserDefaults.standard.bool(forKey: "isEnglish")
    }

    /// 双语便捷函数：根据当前语言返回对应文字
    func t(_ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }
}
