import Foundation
import SwiftUI

// MARK: - Enums（枚举定义）

/// 系统睡眠模式选项
enum SleepMode: Equatable {
    case neverSleep
    case custom
}

/// 磁盘睡眠模式选项
enum DiskSleepMode: Equatable {
    case neverSleep
    case custom
}

/// 合盖行为模式选项
enum LidMode: Equatable {
    case sleepOnLidClose
    case noSleepOnLidClose
}

/// 休眠模式选项（对应 pmset hibernatemode）
enum HibernateMode: Int, Equatable, CaseIterable {
    case memoryOnly   = 0   // 纯内存：不写磁盘，唤醒最快，断电丢数据
    case hybrid       = 3   // 混合（默认）：内存+磁盘双写，正常走内存，断电走磁盘
    case deepHibernate = 25  // 深度休眠：内存写盘后 RAM 断电，零耗电，唤醒慢
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

    // MARK: Lid Mode
    @Published var lidMode: LidMode = .sleepOnLidClose

    // MARK: Hibernate Mode（休眠模式）
    @Published var hibernateMode: HibernateMode = .hybrid

    // MARK: Status
    @Published var sleepStatus: ActionStatus = .idle
    @Published var diskSleepStatus: ActionStatus = .idle
    @Published var lidStatus: ActionStatus = .idle
    @Published var hibernateModeStatus: ActionStatus = .idle
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

        // --- 合盖行为
        let disableSleep = intVal("disablesleep") ?? 0
        lidMode = disableSleep == 1 ? .noSleepOnLidClose : .sleepOnLidClose

        // --- 休眠模式
        let hm = intVal("hibernatemode") ?? 3
        hibernateMode = HibernateMode(rawValue: hm) ?? .hybrid
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
                    return line + "  ← 休眠时保持网络（1=是）"
                } else if trimmed.hasPrefix("disablesleep") {
                    return line + "  ← 全局禁用休眠（1=禁用，合盖不休眠）"
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
                    return line + "  ← 系统空闲多久后休眠（0=永不）"
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

    // MARK: - Apply Lid Mode

    /// 合盖行为联动休眠模式：
    /// - 合盖不休眠 + deepHibernate → disablesleep=0 + caffeinate（保留电源键路径）
    /// - 合盖不休眠 + 其他           → disablesleep=1 + caffeinate（全封）
    /// - 合盖休眠                    → 恢复默认
    func applyLidMode() async {
        lidStatus = .applying
        do {
            stopCaffeinate()
            switch lidMode {
            case .sleepOnLidClose:
                let cmd = [
                    "pmset -a disablesleep 0",
                    "pmset -a standby 1",
                    "pmset -a networkoversleep 0",
                ].joined(separator: "; ")
                try await ShellHelper.runWithAdmin(cmd)
                _ = ShellHelper.run("pkill -f 'caffeinate' 2>/dev/null")
            case .noSleepOnLidClose:
                if hibernateMode == .deepHibernate {
                    let cmd = [
                        "pmset -a disablesleep 0",
                        "pmset -a standby 0",
                        "pmset -a hibernatemode 25",
                        "pmset -a networkoversleep 1",
                    ].joined(separator: "; ")
                    try await ShellHelper.runWithAdmin(cmd)
                } else {
                    let hmVal = hibernateMode.rawValue
                    let cmd = [
                        "pmset -a disablesleep 1",
                        "pmset -a standby 0",
                        "pmset -a hibernatemode \(hmVal)",
                        "pmset -a networkoversleep 1",
                    ].joined(separator: "; ")
                    try await ShellHelper.runWithAdmin(cmd)
                }
                caffeinateProcess = try ShellHelper.launchCaffeinate()
            }
            lidStatus = .applied
            refreshPmsetInfo()
        } catch {
            lidStatus = .error("Failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Apply Hibernate Mode

    /// 应用休眠模式，同时联动合盖行为的 disablesleep 设置。
    func applyHibernateMode() async {
        hibernateModeStatus = .applying
        do {
            var cmds: [String]
            switch hibernateMode {
            case .memoryOnly:
                cmds = ["pmset -a hibernatemode 0", "pmset -a standby 0"]
            case .hybrid:
                cmds = ["pmset -a hibernatemode 3", "pmset -a standby 1"]
            case .deepHibernate:
                cmds = ["pmset -a hibernatemode 25", "pmset -a standby 0"]
                // deepHibernate 需要 disablesleep=0 才能让电源键生效
                if lidMode == .noSleepOnLidClose {
                    cmds.append("pmset -a disablesleep 0")
                }
            }
            try await ShellHelper.runWithAdmin(cmds.joined(separator: "; "))
            hibernateModeStatus = .applied
            refreshPmsetInfo()
        } catch {
            hibernateModeStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Apply All

    func applyAll() async {
        applyAllStatus = .applying
        await applySleepMode()
        if case .error = sleepStatus { applyAllStatus = .error("Auto sleep failed"); return }
        await applyDiskSleepMode()
        if case .error = diskSleepStatus { applyAllStatus = .error("Disk hibernate failed"); return }
        await applyHibernateMode()
        if case .error = hibernateModeStatus { applyAllStatus = .error("Hibernate mode failed"); return }
        await applyLidMode()
        if case .error = lidStatus { applyAllStatus = .error("Lid mode failed"); return }
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
