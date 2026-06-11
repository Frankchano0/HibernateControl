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

/// 短按电源键行为
enum PowerButtonMode: Equatable {
    case displaySleep  // 仅关闭屏幕
    case systemSleep   // 系统进入睡眠/休眠
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

    // MARK: Display Lock（自动锁屏设置）
    /// 当前选择的锁屏模式（永不锁屏 / 自定义）
    @Published var displayLockMode: SleepMode = .neverSleep
    /// 锁屏超时分钟数
    @Published var displayLockMinutes: Int = 5
    @Published var displayLockStatus: ActionStatus = .idle

    // MARK: Lid Mode
    @Published var lidMode: LidMode = .sleepOnLidClose

    // MARK: Hibernate Mode（休眠模式）
    @Published var hibernateMode: HibernateMode = .hybrid

    // MARK: Power Button（电源键行为）
    /// 短按电源键行为：关闭屏幕 / 进入睡眠
    /// 联动规则：切换电源键模式时，若合盖不睡眠 active，重新 apply caffeinate flags
    @Published var powerButtonMode: PowerButtonMode = .systemSleep {
        didSet {
            guard !isLoadingSettings else { return }
            // 合盖不睡眠时，电源键模式变化需要切换 caffeinate 变体（-dimsu vs -dimu）
            if lidMode == .noSleepOnLidClose && !lidStatus.isApplying {
                Task { await applyLidMode() }
            }
        }
    }
    @Published var powerButtonStatus: ActionStatus = .idle
    @Published var hibernateNowStatus: ActionStatus = .idle
    @Published var sleepNowStatus: ActionStatus = .idle
    @Published var sleepNoWakeStatus: ActionStatus = .idle

    // MARK: Status
    @Published var sleepStatus: ActionStatus = .idle
    @Published var diskSleepStatus: ActionStatus = .idle
    @Published var lidStatus: ActionStatus = .idle
    @Published var hibernateModeStatus: ActionStatus = .idle
    @Published var applyAllStatus: ActionStatus = .idle

    // MARK: System Info（系统信息）
    /// 当前 pmset 电源管理状态的文本输出（raw，供 debug 保留）
    @Published var currentPmsetInfo: String = ""

    // MARK: Parsed System Config（结构化系统配置，用于 UI 展示）
    @Published var sysStandby: Int = -1          // -1 = 未读取
    @Published var sysNetworkOverSleep: Int = -1
    @Published var sysDiskSleep: Int = -1
    @Published var sysSystemSleep: Int = -1
    @Published var sysDisplaySleep: Int = -1
    @Published var sysHibernateMode: Int = -1
    @Published var sysHibernateFile: String = ""
    @Published var sysTcpKeepAlive: Int = -1
    @Published var sysDisableSleep: Int = -1
    /// sleep/displaysleep 被哪些进程阻止（空 = 未被阻止）
    @Published var sysSleepBlockers: [String] = []
    @Published var sysDisplaySleepBlockers: [String] = []
    @Published var sysAssertionBlockers: [String] = []

    // MARK: Internal（内部状态）
    /// caffeinate 子进程引用，用于在"合盖不睡眠"模式下保持系统唤醒。
    private var caffeinateProcess: Process?

    /// 加载系统设置时抑制 didSet 联动逻辑
    private var isLoadingSettings = false

    /// 缓存的 caffeinate 运行状态（由 refreshPmsetInfo 更新，避免在 view body 中同步执行 shell）
    @Published var caffeinateRunning: Bool = false

    /// 合盖是否会触发休眠（纯计算，读缓存值，不执行 shell）
    var lidWillSleep: Bool {
        sysDisableSleep != 1 && !caffeinateRunning
    }

    init() {
        refreshPmsetInfo()  // 启动时立即读取当前系统电源设置
        loadCurrentSettings()  // 从系统读取当前值，同步到 UI
        cleanupOrphanCaffeinate()  // 启动时清理与当前设置矛盾的孤儿进程
    }

    // MARK: - Orphan Cleanup（启动时安全检查）

    /// 启动时检查：如果当前设置是「合盖睡眠」，但系统中仍有 caffeinate 进程在跑，
    /// 说明上次 App 异常退出遗留了孤儿进程。主动清理，防止合盖后不睡眠。
    /// 同理：如果 disablesleep=1 但 lidMode=sleepOnLidClose，也需要恢复。
    private func cleanupOrphanCaffeinate() {
        if lidMode == .sleepOnLidClose {
            // 合盖睡眠模式下只终止本 App 当前持有的 caffeinate，不处理用户或其他 App 的 caffeinate。
            stopCaffeinate()
            // disablesleep 也不应为 1
            let raw = ShellHelper.run("pmset -g")
            if raw.contains("disablesleep") && raw.range(of: #"disablesleep\s+1"#, options: .regularExpression) != nil {
                Task {
                    try? await ShellHelper.runWithAdmin("pmset -a disablesleep 0")
                    refreshPmsetInfo()
                }
            }
        }
    }

    // MARK: - Load Current Settings（从系统读取当前设置同步到 UI）

    /// 读取 pmset -g 的实际值，将系统当前状态反映到各 UI 控件。
    func loadCurrentSettings() {
        isLoadingSettings = true
        defer { isLoadingSettings = false }
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

        // --- 自动锁屏 ---
        let dispVal = intVal("displaysleep") ?? 0
        if dispVal == 0 {
            displayLockMode = .neverSleep
        } else {
            displayLockMode = .custom
            displayLockMinutes = dispVal
        }

        // --- 合盖行为（disablesleep=1 明确禁用，或检测到 App 自己的 caffeinate 在跑）
        let disableSleep = intVal("disablesleep") ?? 0
        let caffRunning = isManagedCaffeinateRunning
        lidMode = (disableSleep == 1 || caffRunning) ? .noSleepOnLidClose : .sleepOnLidClose

        // --- 休眠模式
        let hm = intVal("hibernatemode") ?? 3
        hibernateMode = HibernateMode(rawValue: hm) ?? .hybrid

        // --- 电源键行为
        let pbds = ShellHelper.run("defaults read com.apple.loginwindow PowerButtonSleepsSystem 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines)
        // PowerButtonSleepsSystem=0 → 关屏；1或未设置 → 睡眠
        powerButtonMode = (pbds == "0") ? .displaySleep : .systemSleep
    }

    /// 执行 `pmset -g` 命令，解析所有关键字段到结构化属性，同时更新 currentPmsetInfo。
    func refreshPmsetInfo() {
        let output = ShellHelper.run("pmset -g")
        currentPmsetInfo = output

        // 解析整数值：匹配 "  key  123" 或 "  key  123 (reason...)"
        func intVal(_ key: String) -> Int {
            guard let range = output.range(of: #"(?m)^\s*"# + key + #"\s+(\d+)"#, options: .regularExpression) else { return -1 }
            let parts = String(output[range]).trimmingCharacters(in: .whitespaces).split(separator: " ")
            return parts.last.flatMap { Int($0) } ?? -1
        }
        func strVal(_ key: String) -> String {
            guard let range = output.range(of: #"(?m)^\s*"# + key + #"\s+(\S+)"#, options: .regularExpression) else { return "" }
            let parts = String(output[range]).trimmingCharacters(in: .whitespaces).split(separator: " ")
            return parts.last.map(String.init) ?? ""
        }
        // 解析 "key  0 (prevented by proc1, proc2)" 中的进程名列表
        func blockers(for key: String) -> [String] {
            let pattern = #"(?m)^\s*"# + key + #"\s+\d+\s+\(.*?prevented by ([^)]+)\)"#
            guard let range = output.range(of: pattern, options: .regularExpression) else { return [] }
            let matched = String(output[range])
            guard let paren = matched.range(of: "prevented by ") else { return [] }
            let tail = String(matched[paren.upperBound...])
                .replacingOccurrences(of: ")", with: "")
            // 去重，过滤掉系统守护进程和临时 assertion，只留用户关心的持久阻止
            let all = tail.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let userFacing = all.filter { !["powerd", "sharingd", "runningboardd", "bluetoothd", "caffeinate", "useractivityd"].contains($0) }
            return Array(Set(userFacing)).sorted()
        }

        sysStandby          = intVal("standby")
        sysNetworkOverSleep = intVal("networkoversleep")
        sysDiskSleep        = intVal("disksleep")
        sysSystemSleep      = intVal("sleep")
        sysDisplaySleep     = intVal("displaysleep")
        sysHibernateMode    = intVal("hibernatemode")
        sysHibernateFile    = strVal("hibernatefile")
        sysTcpKeepAlive     = intVal("tcpkeepalive")
        sysDisableSleep     = intVal("disablesleep")
        sysSleepBlockers        = blockers(for: "sleep")
        sysDisplaySleepBlockers = blockers(for: "displaysleep")
        sysAssertionBlockers    = collectSleepAssertionBlockers()

        caffeinateRunning = isManagedCaffeinateRunning
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

    // MARK: - Apply Display Lock（应用自动锁屏设置）

    /// 通过 pmset 命令设置屏幕关闭计时器（关屏后自动锁定）。
    func applyDisplayLock() async {
        displayLockStatus = .applying
        do {
            switch displayLockMode {
            case .neverSleep:
                try await ShellHelper.runWithAdmin("pmset -a displaysleep 0")
            case .custom:
                try await ShellHelper.runWithAdmin("pmset -a displaysleep \(displayLockMinutes)")
            }
            displayLockStatus = .applied
            refreshPmsetInfo()
        } catch {
            displayLockStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Apply Lid Mode

    /// 合盖行为联动休眠模式：
    /// - 合盖不睡眠 + deepHibernate → disablesleep=0 + caffeinate（保留电源键路径）
    /// - 合盖不睡眠 + 电源键睡眠   → disablesleep=1 + caffeinateLight（无-s，电源键可用）
    /// - 合盖不睡眠 + 电源键关屏   → disablesleep=1 + caffeinate（含-s，全封）
    /// - 合盖睡眠                  → 恢复默认
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
            case .noSleepOnLidClose:
                if hibernateMode == .deepHibernate {
                    let cmd = [
                        "pmset -a disablesleep 0",
                        "pmset -a standby 0",
                        "pmset -a hibernatemode 25",
                        "pmset -a networkoversleep 0",
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
                // 根据电源键模式选择 caffeinate 变体：
                // - 电源键=进入睡眠 → 不含 -s，保留电源键睡眠路径
                // - 电源键=关闭屏幕 → 含 -s，全面阻止（电源键不触发睡眠，无需保留路径）
                if powerButtonMode == .systemSleep {
                    caffeinateProcess = try ShellHelper.launchCaffeinateLight()
                } else {
                    caffeinateProcess = try ShellHelper.launchCaffeinate()
                }
            }
            lidStatus = .applied
            refreshPmsetInfo()
        } catch {
            lidStatus = .error("Failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Apply Hibernate Mode

    /// 应用休眠模式，同时联动唤醒源和合盖行为：
    /// - 深度休眠 (mode 25): 关闭所有唤醒源（womp/powernap/tcpkeepalive），确保只有物理操作能唤醒
    /// - 混合/睡眠: 只调整睡眠深度，不主动打开或关闭唤醒源
    func applyHibernateMode() async {
        hibernateModeStatus = .applying
        do {
            var cmds: [String]
            switch hibernateMode {
            case .memoryOnly:
                cmds = [
                    "pmset -a hibernatemode 0",
                    "pmset -a standby 0",
                ]
            case .hybrid:
                cmds = [
                    "pmset -a hibernatemode 3",
                    "pmset -a standby 1",
                ]
            case .deepHibernate:
                cmds = [
                    "pmset -a hibernatemode 25",
                    "pmset -a standby 0",
                    // 关闭所有唤醒源 → 只有开盖/电源键能唤醒
                    "pmset -a womp 0",
                    "pmset -a powernap 0",
                    "pmset -a tcpkeepalive 0",
                    "pmset -a networkoversleep 0",
                ]
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

    // MARK: - Apply Power Button Behavior

    /// 电源键短按行为：
    /// - displaySleep → 仅关屏（PowerButtonSleepsSystem = NO）
    /// - systemSleep  → 系统睡眠（恢复默认）
    func applyPowerButtonBehavior() async {
        powerButtonStatus = .applying
        do {
            let cmd: String
            switch powerButtonMode {
            case .displaySleep:
                cmd = "defaults write com.apple.loginwindow PowerButtonSleepsSystem -bool NO"
            case .systemSleep:
                cmd = "defaults delete com.apple.loginwindow PowerButtonSleepsSystem 2>/dev/null; true"
            }
            try await ShellHelper.runWithAdmin(cmd)
            powerButtonStatus = .applied
        } catch {
            powerButtonStatus = .error(error.localizedDescription)
        }
    }

    /// 立即执行睡眠/休眠：
    /// 1. 先将 hibernatemode 设为当前选中模式
    /// 2. 暂停 caffeinate（否则会阻止睡眠），睡眠后由系统唤醒时自动恢复
    /// 3. 触发 pmset sleepnow
    func hibernateNow() async {
        hibernateNowStatus = .applying
        do {
            // Step 1: 暂停本 App 自己创建的 caffeinate（不动第三方进程）
            stopCaffeinate()

            // Step 2: 刷新阻止源诊断；只提示，不自动暂停或杀掉第三方进程
            refreshSleepBlockerDiagnostics()
            try await Task.sleep(nanoseconds: 300_000_000)

            // Step 3: 一次 admin 调用完成所有设置 + 触发睡眠
            var cmds: [String] = []
            let hmVal = hibernateMode.rawValue
            let standbyVal = hibernateMode == .hybrid ? 1 : 0
            cmds.append("pmset -a hibernatemode \(hmVal)")
            cmds.append("pmset -a standby \(standbyVal)")
            if hibernateMode == .deepHibernate {
                cmds.append("pmset -a womp 0")
                cmds.append("pmset -a powernap 0")
                cmds.append("pmset -a tcpkeepalive 0")
                cmds.append("pmset -a networkoversleep 0")
            }
            cmds.append("pmset -a disablesleep 0")
            cmds.append("pmset sleepnow")
            try await ShellHelper.runWithAdmin(cmds.joined(separator: "; "))

            hibernateNowStatus = .applied
            refreshPmsetInfo()
        } catch {
            hibernateNowStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Sleep Now（立即进入睡眠）

    /// 立即让系统进入睡眠，使用系统当前已有的 hibernatemode，不修改任何 pmset 参数。
    /// 操作前暂停 caffeinate（否则它持有的断言会阻止 pmset sleepnow），
    /// 唤醒后系统恢复正常，caffeinate 不会自动重启（如需持续"合盖不休眠"请重新应用合盖设置）。
    func sleepNow() async {
        sleepNowStatus = .applying
        do {
            // Step 1: 停掉本 App 自己创建的 caffeinate（不动第三方进程）
            stopCaffeinate()

            // Step 2: 刷新阻止源诊断；只提示，不自动暂停或杀掉第三方进程
            refreshSleepBlockerDiagnostics()
            try await Task.sleep(nanoseconds: 300_000_000)

            // Step 3: 一次 admin 调用：解除 disablesleep + 触发睡眠
            try await ShellHelper.runWithAdmin("pmset -a disablesleep 0; pmset sleepnow")
            sleepNowStatus = .applied
            refreshPmsetInfo()
        } catch {
            sleepNowStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Sleep No Wake（睡眠+关闭唤醒源，安全放书包）

    /// 进入混合睡眠（快速唤醒）但关闭所有唤醒源，确保不会被后台任务唤醒。
    /// 适合放进书包的场景：不发热、微耗电、开盖即时恢复。
    func sleepNoWake() async {
        sleepNoWakeStatus = .applying
        do {
            // 停掉本 App 自己创建的 caffeinate；第三方阻止源只诊断不处理。
            stopCaffeinate()
            refreshSleepBlockerDiagnostics()
            try await Task.sleep(nanoseconds: 300_000_000)

            // 一次 admin：关闭唤醒源 + 保持 mode 3（快速恢复）+ 触发睡眠
            let cmds = [
                "pmset -a disablesleep 0",
                "pmset -a hibernatemode 3",
                "pmset -a womp 0",
                "pmset -a powernap 0",
                "pmset -a tcpkeepalive 0",
                "pmset -a networkoversleep 0",
                "pmset sleepnow",
            ].joined(separator: "; ")
            try await ShellHelper.runWithAdmin(cmds)

            sleepNoWakeStatus = .applied
            refreshPmsetInfo()
        } catch {
            sleepNoWakeStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Sleep Blocker Diagnostics（睡眠阻止源诊断）

    /// 只刷新睡眠阻止源诊断，不暂停或杀掉第三方进程。
    /// 真实处理应交给用户：退出相关 App、停止播放音频、关闭外设唤醒等。
    func checkSleepBlockers() {
        refreshSleepBlockerDiagnostics()
    }

    func refreshSleepBlockerDiagnostics() {
        sysAssertionBlockers = collectSleepAssertionBlockers()
        refreshPmsetInfo()
    }

    private var isManagedCaffeinateRunning: Bool {
        caffeinateProcess?.isRunning == true
    }

    private func collectSleepAssertionBlockers() -> [String] {
        let output = ShellHelper.run("pmset -g assertions")
        let ignored = Set(["powerd"])
        let assertionKeys = [
            "PreventUserIdleSystemSleep",
            "NoIdleSleepAssertion",
            "PreventSystemSleep",
            "NoDisplaySleepAssertion",
        ]
        var blockers: [String] = []

        for line in output.components(separatedBy: "\n") {
            guard assertionKeys.contains(where: { line.contains($0) }) else { continue }
            guard let pidRange = line.range(of: #"pid (\d+)\(([^)]+)\)"#, options: .regularExpression) else { continue }
            let pidMatch = String(line[pidRange])
            let parts = pidMatch.replacingOccurrences(of: "pid ", with: "").components(separatedBy: "(")
            guard parts.count == 2 else { continue }
            let procName = parts[1].replacingOccurrences(of: ")", with: "")
            guard !ignored.contains(procName) else { continue }

            let assertionName = assertionKeys.first(where: { line.contains($0) }) ?? "SleepAssertion"
            let label: String
            if let nameRange = line.range(of: #"named: "([^"]+)""#, options: .regularExpression) {
                let named = String(line[nameRange])
                    .replacingOccurrences(of: "named: ", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                label = "\(procName) — \(named)"
            } else {
                label = "\(procName) — \(assertionName)"
            }
            blockers.append(label)
        }

        return Array(Set(blockers)).sorted()
    }

    // MARK: - Apply All

    func applyAll() async {
        applyAllStatus = .applying
        await applySleepMode()
        if case .error = sleepStatus { applyAllStatus = .error("Auto sleep failed"); return }
        await applyDisplayLock()
        if case .error = displayLockStatus { applyAllStatus = .error("Display lock failed"); return }
        await applyDiskSleepMode()
        if case .error = diskSleepStatus { applyAllStatus = .error("Disk hibernate failed"); return }
        await applyHibernateMode()
        if case .error = hibernateModeStatus { applyAllStatus = .error("Hibernate mode failed"); return }
        await applyLidMode()
        if case .error = lidStatus { applyAllStatus = .error("Lid mode failed"); return }
        applyAllStatus = .applied
    }

    // MARK: - Helpers（辅助方法）

    /// 终止当前 App 启动的 caffeinate 进程，不影响用户或其他 App 的 caffeinate。
    private func stopCaffeinate() {
        guard let process = caffeinateProcess else {
            caffeinateRunning = false
            return
        }
        if process.isRunning {
            process.terminate()
        }
        caffeinateProcess = nil
        caffeinateRunning = false
    }
}
