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

    // MARK: Status（各功能区块的操作状态）
    @Published var sleepStatus: ActionStatus = .idle
    @Published var diskSleepStatus: ActionStatus = .idle
    @Published var lidStatus: ActionStatus = .idle
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
    }

    // MARK: - Refresh（刷新系统状态）

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
                    return line + "  ← 休眠模式（0=纯内存/3=混合）"
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

    /// 控制合盖后的系统行为，一次性设置所有防休眠参数。
    /// - sleepOnLidClose: 恢复 macOS 默认行为，还原所有参数
    /// - noSleepOnLidClose: 彻底堵死所有休眠路径：
    ///   1. disablesleep 1  — 全局禁用睡眠（包括合盖）
    ///   2. standby 0       — 禁止深度待机（防止长时间后断电 RAM）
    ///   3. hibernatemode 0 — 纯内存模式（不写磁盘休眠镜像）
    ///   4. networkoversleep 1 — 万一浅睡眠也保持网络连接
    ///   5. caffeinate -dimsu — 多重防护进程作为兜底
    func applyLidMode() async {
        lidStatus = .applying
        do {
            // 无论切换到哪个模式，都先停止已有的 caffeinate 进程
            stopCaffeinate()

            switch lidMode {
            case .sleepOnLidClose:
                // 恢复默认行为：还原所有参数，杀掉 caffeinate
                let restoreCmd = [
                    "pmset -a disablesleep 0",   // 重新允许系统睡眠
                    "pmset -a standby 1",        // 恢复深度待机
                    "pmset -a hibernatemode 3",   // 恢复混合休眠（macOS 默认）
                    "pmset -a networkoversleep 0", // 恢复默认网络行为
                ].joined(separator: "; ")
                try await ShellHelper.runWithAdmin(restoreCmd)
                _ = ShellHelper.run("pkill -f 'caffeinate' 2>/dev/null")
            case .noSleepOnLidClose:
                // 一次性设置所有防休眠参数，只弹一次密码框
                let fullCmd = [
                    "pmset -a disablesleep 1",    // 全局禁用睡眠（含合盖）
                    "pmset -a standby 0",         // 禁止深度待机
                    "pmset -a hibernatemode 0",   // 纯内存模式，不写磁盘
                    "pmset -a networkoversleep 1", // 睡眠时保持网络
                ].joined(separator: "; ")
                try await ShellHelper.runWithAdmin(fullCmd)
                // caffeinate -dimsu 作为多重保障兜底：
                //   -d 防显示器睡眠, -i 防空闲睡眠,
                //   -m 防磁盘睡眠, -s 防系统睡眠, -u 模拟用户活跃
                caffeinateProcess = try ShellHelper.launchCaffeinate()
            }
            lidStatus = .applied
            refreshPmsetInfo()
        } catch {
            lidStatus = .error("Failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Apply All（一键全部应用）

    /// 依次应用所有设置：睡眠模式 → 磁盘睡眠 → 合盖模式。
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
