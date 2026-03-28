import Foundation
import SwiftUI

// MARK: - Enums（枚举定义）

/// 系统睡眠模式选项
enum SleepMode: Equatable {
    case neverSleep  // 永不睡眠 — 将 sleep 和 displaysleep 设为 0
    case custom      // 自定义 — 分别设置电池和充电状态下的睡眠时间
}

/// 磁盘睡眠模式选项
enum DiskSleepMode: Equatable {
    case neverSleep  // 磁盘永不休眠 — 将 disksleep 设为 0
    case custom      // 自定义 — 设置磁盘空闲后的休眠超时时间
}

/// 合盖行为模式选项
enum LidMode: Equatable {
    case sleepOnLidClose     // 合盖后正常睡眠（macOS 默认行为）
    case noSleepOnLidClose   // 合盖后保持唤醒（通过 caffeinate 进程实现）
}

/// 操作状态枚举 — 用于追踪每个设置项的应用状态
enum ActionStatus: Equatable {
    case idle              // 空闲 — 尚未执行操作
    case applying          // 执行中 — 正在应用设置
    case applied           // 已完成 — 设置成功应用
    case error(String)     // 出错 — 附带错误信息

    /// 便捷属性：判断是否正在执行中（用于禁用按钮防止重复点击）
    var isApplying: Bool {
        if case .applying = self { return true }
        return false
    }
}

// MARK: - ViewModel（视图模型）
// 核心业务逻辑层，负责：
// 1. 管理用户选择的各项设置状态
// 2. 调用 ShellHelper 执行 pmset 命令修改系统电源设置
// 3. 管理 caffeinate 进程实现合盖不睡眠
// 4. 追踪每个操作的执行状态（idle → applying → applied/error）
//
// 所有 pmset 命令需要管理员权限，会弹出系统密码输入框。
// @MainActor 确保所有 UI 状态更新都在主线程执行。

@MainActor
final class HibernateViewModel: ObservableObject {

    // MARK: Sleep Mode（系统睡眠设置）
    /// 当前选择的睡眠模式（永不睡眠 / 自定义）
    @Published var sleepMode: SleepMode = .neverSleep
    /// 电池供电时的睡眠超时分钟数（仅在 custom 模式下生效）
    @Published var batteryMinutes: Int = 10
    /// 充电状态下的睡眠超时分钟数（仅在 custom 模式下生效）
    @Published var chargingMinutes: Int = 15

    // MARK: Disk Sleep Mode（磁盘睡眠设置）
    /// 当前选择的磁盘睡眠模式
    @Published var diskSleepMode: DiskSleepMode = .neverSleep
    /// 磁盘空闲后的休眠超时分钟数（仅在 custom 模式下生效）
    @Published var diskSleepMinutes: Int = 10

    // MARK: Lid Mode（合盖行为设置）
    /// 当前选择的合盖行为模式
    @Published var lidMode: LidMode = .sleepOnLidClose

    // MARK: Power Button Hibernate（电源键休眠设置）
    /// 开启后按下电源键将触发真正的磁盘休眠（hibernatemode 25）：
    /// 系统将内存内容写入磁盘休眠镜像，然后完全断电 RAM，
    /// 实现零耗电深度休眠；未勾选时恢复 macOS 默认混合模式（hibernatemode 3）。
    @Published var powerButtonHibernate: Bool = false

    // MARK: Status（各功能区块的操作状态）
    @Published var sleepStatus: ActionStatus = .idle
    @Published var diskSleepStatus: ActionStatus = .idle
    @Published var lidStatus: ActionStatus = .idle
    @Published var powerButtonHibernateStatus: ActionStatus = .idle
    @Published var applyAllStatus: ActionStatus = .idle

    // MARK: System Info（系统信息）
    /// 当前 pmset 电源管理状态的文本输出
    @Published var currentPmsetInfo: String = ""

    // MARK: Internal（内部状态）
    /// caffeinate 子进程引用，用于在"合盖不睡眠"模式下保持系统唤醒。
    /// 当切回"合盖睡眠"时会终止此进程。
    private var caffeinateProcess: Process?

    init() {
        refreshPmsetInfo()  // 启动时立即读取当前系统电源设置
        loadCurrentSettings()  // 从系统读取当前值，同步到 UI
    }

    // MARK: - Load Current Settings（从系统读取当前设置同步到 UI）

    /// 读取 pmset -g 的实际值，将系统当前状态反映到各 UI 控件。
    func loadCurrentSettings() {
        let raw = ShellHelper.run("pmset -g")

        // 解析某个 key 对应的整数值，例如 "sleep 10" → 10
        func intVal(_ key: String) -> Int? {
            guard let range = raw.range(of: #"(?m)^\s*"# + key + #"\s+(\d+)"#, options: .regularExpression) else { return nil }
            let matched = String(raw[range])
            let parts = matched.trimmingCharacters(in: .whitespaces).split(separator: " ")
            return parts.last.flatMap { Int($0) }
        }

        // --- 睡眠模式 ---
        let sleepVal = intVal("sleep") ?? 0
        if sleepVal == 0 {
            sleepMode = .neverSleep
        } else {
            sleepMode = .custom
            // battery(-b) 和 charging(-c) 可能不同，尝试分别读，否则用同一值
            batteryMinutes = sleepVal
            chargingMinutes = sleepVal
        }

        // --- 磁盘睡眠 ---
        let diskVal = intVal("disksleep") ?? 0
        if diskVal == 0 {
            diskSleepMode = .neverSleep
        } else {
            diskSleepMode = .custom
            diskSleepMinutes = diskVal
        }

        // --- 合盖行为：disablesleep 1 表示"合盖不睡眠" ---
        let disableSleep = intVal("disablesleep") ?? 0
        lidMode = disableSleep == 1 ? .noSleepOnLidClose : .sleepOnLidClose

        // --- 电源键休眠：hibernatemode 25 表示开启 ---
        let hibernateMode = intVal("hibernatemode") ?? 3
        powerButtonHibernate = (hibernateMode == 25)
    }

    /// 执行 `pmset -g` 命令，提取 sleep/displaysleep/disksleep 相关行，
    /// 更新 currentPmsetInfo 供 UI 显示。
    func refreshPmsetInfo() {
        let output = ShellHelper.run("pmset -g | grep -E '(hibernatefile|networkoversleep|disksleep|sleep|displaysleep|disablesleep|standby|hibernatemode|tcpkeepalive)'")
        // 为每行 pmset 参数追加中文注释，方便用户理解
        let annotated = output
            .components(separatedBy: "\n")
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("hibernatefile") {
                    return line + "  ← 休眠镜像文件路径"
                } else if trimmed.hasPrefix("networkoversleep") {
                    return line + "  ← 睡眠时保持网络（1=是）"
                } else if trimmed.hasPrefix("disablesleep") {
                    return line + "  ← 全局禁用睡眠（1=禁用，合盖不休眠）"
                } else if trimmed.hasPrefix("disksleep") {
                    return line + "  ← 磁盘空闲多久后休眠（0=永不）"
                } else if trimmed.hasPrefix("displaysleep") {
                    return line + "  ← 显示器空闲多久后关闭（0=永不）"
                } else if trimmed.hasPrefix("standby") {
                    return line + "  ← 深度待机（0=禁用，防长时间断电）"
                } else if trimmed.hasPrefix("hibernatemode") {
                    return line + "  ← 休眠模式（0=纯内存 /3=混合 /25=电源键深度休眠）"
                } else if trimmed.hasPrefix("tcpkeepalive") {
                    return line + "  ← TCP连接保活（1=开启）"
                } else if trimmed.hasPrefix("sleep") {
                    return line + "  ← 系统空闲多久后睡眠（0=永不）"
                } else {
                    return line
                }
            }
            .joined(separator: "\n")
        currentPmsetInfo = annotated
    }

    // MARK: - Apply Sleep Mode（应用睡眠设置）

    /// 根据用户选择，通过 pmset 命令设置系统睡眠参数。
    /// - neverSleep: `pmset -a sleep 0 displaysleep 0`（-a = 所有电源模式）
    /// - custom: 分别设置电池(-b)和充电(-c)模式下的超时时间
    func applySleepMode() async {
        sleepStatus = .applying
        do {
            switch sleepMode {
            case .neverSleep:
                try await ShellHelper.runWithAdmin("pmset -a sleep 0 displaysleep 0")
            case .custom:
                let cmd = "pmset -b sleep \(batteryMinutes) displaysleep \(batteryMinutes); pmset -c sleep \(chargingMinutes) displaysleep \(chargingMinutes)"
                try await ShellHelper.runWithAdmin(cmd)
            }
            sleepStatus = .applied
            refreshPmsetInfo()  // 应用后刷新显示最新状态
        } catch {
            sleepStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Apply Disk Sleep Mode（应用磁盘睡眠设置）

    /// 通过 pmset 命令设置磁盘休眠参数。
    /// - neverSleep: `pmset -a disksleep 0`
    /// - custom: `pmset -a disksleep <分钟数>`
    func applyDiskSleepMode() async {
        diskSleepStatus = .applying
        do {
            switch diskSleepMode {
            case .neverSleep:
                try await ShellHelper.runWithAdmin("pmset -a disksleep 0")
            case .custom:
                try await ShellHelper.runWithAdmin("pmset -a disksleep \(diskSleepMinutes)")
            }
            diskSleepStatus = .applied
            refreshPmsetInfo()
        } catch {
            diskSleepStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Apply Lid Mode（应用合盖行为设置）

    /// 控制合盖后的系统行为。
    ///
    /// 与「电源键休眠」的交互说明：
    /// - disablesleep=1 会全局禁止所有睡眠，包括按电源键，因此：
    ///   - 合盖不睡眠 + 电源键休眠关闭 → disablesleep=1（全封）
    ///   - 合盖不睡眠 + 电源键休眠开启 → disablesleep=0，仅靠 caffeinate 防合盖睡眠，
    ///     保留电源键触发 hibernatemode=25 的路径
    func applyLidMode() async {
        lidStatus = .applying
        do {
            stopCaffeinate()

            switch lidMode {
            case .sleepOnLidClose:
                // 恢复默认行为，hibernatemode 由「电源键休眠」设置决定
                let restoreCmd = [
                    "pmset -a disablesleep 0",
                    "pmset -a standby 1",
                    "pmset -a networkoversleep 0",
                ].joined(separator: "; ")
                try await ShellHelper.runWithAdmin(restoreCmd)
                _ = ShellHelper.run("pkill -f 'caffeinate' 2>/dev/null")

            case .noSleepOnLidClose:
                if powerButtonHibernate {
                    // 电源键休眠开启时：不能用 disablesleep=1（会阻止电源键休眠）
                    // 改为只靠 caffeinate 防合盖睡眠，保留电源键通路
                    let cmd = [
                        "pmset -a disablesleep 0",     // 不全局禁止，保留电源键路径
                        "pmset -a standby 0",
                        "pmset -a hibernatemode 25",   // 电源键触发深度休眠
                        "pmset -a networkoversleep 1",
                    ].joined(separator: "; ")
                    try await ShellHelper.runWithAdmin(cmd)
                    // caffeinate -dim（去掉 -s，不阻止系统睡眠，只阻止自动睡眠）
                    caffeinateProcess = try ShellHelper.launchCaffeinate()
                } else {
                    // 电源键休眠关闭：用 disablesleep=1 完全封死所有睡眠
                    let cmd = [
                        "pmset -a disablesleep 1",
                        "pmset -a standby 0",
                        "pmset -a hibernatemode 0",
                        "pmset -a networkoversleep 1",
                    ].joined(separator: "; ")
                    try await ShellHelper.runWithAdmin(cmd)
                    caffeinateProcess = try ShellHelper.launchCaffeinate()
                }
            }
            lidStatus = .applied
            refreshPmsetInfo()
        } catch {
            lidStatus = .error("Failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Apply Power Button Hibernate（应用电源键休眠设置）

    /// 控制按下电源键时是否进入真正的磁盘休眠。
    /// 会根据合盖模式决定是否调整 disablesleep，避免互相覆盖。
    func applyPowerButtonHibernate() async {
        powerButtonHibernateStatus = .applying
        do {
            if powerButtonHibernate {
                // 开启：写入 hibernatemode 25
                // 若合盖不睡眠模式开启，同步确保 disablesleep=0（否则电源键无效）
                var cmds = ["pmset -a hibernatemode 25", "pmset -a standby 0"]
                if lidMode == .noSleepOnLidClose {
                    cmds.append("pmset -a disablesleep 0")
                }
                try await ShellHelper.runWithAdmin(cmds.joined(separator: "; "))
            } else {
                // 关闭：恢复 hibernatemode 3
                // 若合盖不睡眠模式开启，恢复 disablesleep=1
                var cmds = ["pmset -a hibernatemode 3", "pmset -a standby 1"]
                if lidMode == .noSleepOnLidClose {
                    cmds.append("pmset -a disablesleep 1")
                }
                try await ShellHelper.runWithAdmin(cmds.joined(separator: "; "))
            }
            powerButtonHibernateStatus = .applied
            refreshPmsetInfo()
        } catch {
            powerButtonHibernateStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Apply All（一键全部应用）

    /// 依次应用所有设置：睡眠模式 → 磁盘睡眠 → 合盖模式 → 电源键休眠。
    /// 任何一步失败都会立即停止并显示错误。
    func applyAll() async {
        applyAllStatus = .applying

        // 第一步：应用睡眠模式
        await applySleepMode()
        if case .error = sleepStatus {
            applyAllStatus = .error("Sleep mode failed")
            return
        }

        // 第二步：应用磁盘睡眠模式
        await applyDiskSleepMode()
        if case .error = diskSleepStatus {
            applyAllStatus = .error("Disk sleep mode failed")
            return
        }

        // 第三步：应用合盖模式
        await applyLidMode()
        if case .error = lidStatus {
            applyAllStatus = .error("Lid mode failed")
            return
        }

        // 第四步：应用电源键休眠设置
        await applyPowerButtonHibernate()
        if case .error = powerButtonHibernateStatus {
            applyAllStatus = .error("Power hibernate failed")
            return
        }

        applyAllStatus = .applied
    }

    // MARK: - Helpers（辅助方法）

    /// 终止当前运行的 caffeinate 进程。
    /// 同时通过 pkill 确保杀掉所有可能残留的 caffeinate 进程。
    private func stopCaffeinate() {
        caffeinateProcess?.terminate()
        caffeinateProcess = nil
        _ = ShellHelper.run("pkill -f 'caffeinate' 2>/dev/null")
    }
}
