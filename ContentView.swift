import SwiftUI
import ApplicationServices

// MARK: - Theme（主题配置）
// 统一管理应用中所有 UI 元素的颜色、间距、圆角等视觉参数，
// 修改这里可以一次性调整整个应用的外观风格。

enum AppTheme {
    /// 卡片背景色，跟随系统明暗模式自动切换
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    /// 卡片之间的垂直间距
    static let sectionSpacing: CGFloat = 12
    /// 卡片圆角半径
    static let cardCornerRadius: CGFloat = 10
    /// 卡片内边距
    static let cardPadding: CGFloat = 14

    /// 每个功能区块的配色方案（图标色 + 强调色）
    struct SectionColor {
        let icon: Color
        let accent: Color
    }

    /// 睡眠模式区块 — 靛蓝色
    static let sleep = SectionColor(icon: .indigo, accent: .indigo)
    /// 磁盘睡眠区块 — 橙色
    static let disk = SectionColor(icon: .orange, accent: .orange)
    /// 合盖模式区块 — 青色
    static let lid = SectionColor(icon: .teal, accent: .teal)
    /// 电源键休眠区块 — 紫色
    static let powerHibernate = SectionColor(icon: .purple, accent: .purple)
    /// 电源键行为区块 — 红色
    static let powerButton = SectionColor(icon: .red, accent: .red)
}

// MARK: - Content View（主界面）
// 应用的主视图，采用上中下三段式布局：
// 1. 顶部标题栏 (headerView)
// 2. 中间可滚动的设置卡片区域（睡眠模式、磁盘睡眠、合盖模式、系统状态）
// 3. 底部"全部应用"操作栏 (applyAllBar)

struct ContentView: View {
    @ObservedObject var viewModel: HibernateViewModel
    @EnvironmentObject private var lang: LanguageManager
    @State private var showPmsetInfo = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AppTheme.sectionSpacing) {
                    sleepModeCard
                    displayLockCard
                    lidModeCard
                    powerButtonCard
                    hibernateModeCard
                    pmsetInfoCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }

            applyAllBar         // 底部"全部应用"操作栏
        }
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header（顶部标题栏）
    // 显示应用图标、名称和版本号

    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.shield.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.linearGradient(
                    colors: [.blue, .indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text("HibernateControl")
                .font(.system(size: 15, weight: .semibold))
            Spacer()
            Text("v2.0")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.5), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: - Sleep Mode Card（睡眠模式设置卡片）
    // 控制 macOS 系统和显示器的睡眠时间。
    // - "Never Sleep"：永不睡眠（pmset sleep 0 displaysleep 0）
    // - "Custom"：自定义电池/充电状态下的睡眠分钟数

    private var sleepModeCard: some View {
        SettingCard(
            icon: "moon.zzz.fill",
            iconColor: AppTheme.sleep.icon,
            title: lang.t("自动睡眠", "Auto Sleep"),
            status: viewModel.sleepStatus
        ) {
            VStack(spacing: 10) {
                modePicker(selection: $viewModel.sleepMode, options: [
                    (SleepMode.neverSleep, lang.t("永不睡眠", "Never"), "infinity"),
                    (SleepMode.custom, lang.t("自定义", "Custom"), "slider.horizontal.3"),
                ])

                if viewModel.sleepMode == .custom {
                    VStack(spacing: 6) {
                        minuteRow(
                            icon: "battery.25",
                            label: lang.t("电池", "Battery"),
                            value: $viewModel.batteryMinutes,
                            accent: AppTheme.sleep.accent
                        )
                        minuteRow(
                            icon: "bolt.fill",
                            label: lang.t("充电中", "Charging"),
                            value: $viewModel.chargingMinutes,
                            accent: AppTheme.sleep.accent
                        )
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        } applyAction: {
            await viewModel.applySleepMode()
        }
    }

    // MARK: - Display Lock Card（自动锁屏设置卡片）

    private var displayLockCard: some View {
        SettingCard(
            icon: "lock.fill",
            iconColor: .cyan,
            title: lang.t("自动锁屏", "Auto Lock"),
            status: viewModel.displayLockStatus
        ) {
            VStack(spacing: 10) {
                modePicker(selection: $viewModel.displayLockMode, options: [
                    (SleepMode.neverSleep, lang.t("永不锁屏", "Never"), "infinity"),
                    (SleepMode.custom, lang.t("自定义", "Custom"), "slider.horizontal.3"),
                ])

                if viewModel.displayLockMode == .custom {
                    minuteRow(
                        icon: "clock",
                        label: lang.t("闲置后锁屏", "Lock after idle"),
                        value: $viewModel.displayLockMinutes,
                        accent: .cyan
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        } applyAction: {
            await viewModel.applyDisplayLock()
        }
    }

    // MARK: - Disk Sleep Card（磁盘睡眠设置卡片）
    // 控制硬盘空闲后自动休眠的时间。
    // - "Never Sleep"：磁盘永不休眠（pmset disksleep 0）
    // - "Custom"：自定义磁盘休眠超时分钟数

    private var diskSleepCard: some View {
        SettingCard(
            icon: "internaldrive.fill",
            iconColor: AppTheme.disk.icon,
            title: lang.t("磁盘睡眠", "Disk Sleep"),
            status: viewModel.diskSleepStatus
        ) {
            VStack(spacing: 10) {
                modePicker(selection: $viewModel.diskSleepMode, options: [
                    (DiskSleepMode.neverSleep, lang.t("永不睡眠", "Never"), "infinity"),
                    (DiskSleepMode.custom, lang.t("自定义", "Custom"), "slider.horizontal.3"),
                ])

                if viewModel.diskSleepMode == .custom {
                    minuteRow(
                        icon: "clock",
                        label: lang.t("空闲多久后休眠", "Idle timeout"),
                        value: $viewModel.diskSleepMinutes,
                        accent: AppTheme.disk.accent
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        } applyAction: {
            await viewModel.applyDiskSleepMode()
        }
    }

    // MARK: - Lid Mode Card（合盖模式设置卡片）
    // 控制合上笔记本盖子时的行为：
    // - "Sleep on Close"：合盖后正常进入睡眠（macOS 默认行为）
    // - "Stay Awake"：合盖后保持唤醒（通过运行 caffeinate -i 实现）

    private var lidModeCard: some View {
        SettingCard(
            icon: "laptopcomputer.closed",
            iconColor: AppTheme.lid.icon,
            title: lang.t("合盖行为", "Lid Behavior"),
            status: viewModel.lidStatus
        ) {
            modePicker(selection: $viewModel.lidMode, options: [
                (LidMode.sleepOnLidClose, lang.t("合盖睡眠", "Sleep on Close"), "moon.fill"),
                (LidMode.noSleepOnLidClose, lang.t("合盖不睡眠", "Stay Awake"), "eye.fill"),
            ])
        } applyAction: {
            await viewModel.applyLidMode()
        }
    }

    // MARK: - Power Button Card（电源键行为设置卡片）
    // 短按电源键行为配置 + 立即深度休眠按钮

    private var powerButtonModeSummary: String {
        switch viewModel.powerButtonMode {
        case .displaySleep: return lang.t("锁屏", "Lock Screen")
        case .systemSleep:  return lang.t("进入睡眠", "Sleep")
        }
    }

    private var powerButtonCard: some View {
        SettingCard(
            icon: "power",
            iconColor: AppTheme.powerButton.icon,
            title: lang.t("电源键行为", "Power Button"),
            status: viewModel.powerButtonStatus,
            isCollapsible: true,
            collapsedSummary: powerButtonModeSummary,
            alwaysShowSummary: true
        ) {
            VStack(spacing: 10) {
                modePicker(
                    selection: $viewModel.powerButtonMode,
                    options: [
                        (.displaySleep, lang.t("锁屏", "Lock Screen"), "lock.fill"),
                        (.systemSleep,  lang.t("进入睡眠", "Sleep"),     "moon.fill"),
                    ]
                )
            }
        } applyAction: {
            await viewModel.applyPowerButtonBehavior()
        }
    }

    // MARK: - Sleep Now Bar（顶部立即休眠栏）

    private var sleepNowBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lang.t("立即休眠", "Sleep Now"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(lang.t("快捷键：⌥⌘S", "Shortcut: ⌥⌘S"))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: {
                    Task { await viewModel.sleepNow() }
                }) {
                    HStack(spacing: 4) {
                        if viewModel.sleepNowStatus.isApplying {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 11))
                        }
                        Text(lang.t("休眠", "Sleep"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.small)
                .disabled(viewModel.sleepNowStatus.isApplying)
            }
            .padding(.horizontal, 4)

            // 辅助功能权限提示
            if !AXIsProcessTrusted() {
                Button(action: {
                    AXIsProcessTrustedWithOptions(
                        [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    )
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text(lang.t("点击授权辅助功能权限以启用快捷键", "Tap to grant Accessibility permission for shortcut"))
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Spacer()
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    // MARK: - Hibernate Mode Card（休眠模式 — 可折叠 + 说明框含执行按钮）

    private var hibernateModeSummary: String {
        switch viewModel.hibernateMode {
        case .memoryOnly:    return lang.t("睡眠",   "Sleep")
        case .hybrid:        return lang.t("混合",   "Hybrid")
        case .deepHibernate: return lang.t("休眠",   "Hibernate")
        }
    }

    private var hibernateModeCard: some View {
        SettingCard(
            icon: "sleep",
            iconColor: AppTheme.powerHibernate.icon,
            title: lang.t("睡眠深度", "Sleep Depth"),
            status: viewModel.hibernateModeStatus,
            isCollapsible: true,
            collapsedSummary: hibernateModeSummary,
            alwaysShowSummary: true
        ) {
            VStack(spacing: 10) {
                modePicker(selection: $viewModel.hibernateMode, options: [
                    (.memoryOnly,    lang.t("睡眠", "Sleep"),      "bolt.fill"),
                    (.hybrid,        lang.t("混合", "Hybrid"),     "square.stack.fill"),
                    (.deepHibernate, lang.t("休眠", "Hibernate"),  "moon.zzz.fill"),
                ])
                hibernateModeDetail(for: viewModel.hibernateMode)
            }
        } applyAction: {
            await viewModel.applyHibernateMode()
        }
    }

    @ViewBuilder
    private func hibernateModeDetail(for mode: HibernateMode) -> some View {
        let rows: [(String, String, String)] = {
            switch mode {
            case .memoryOnly:
                return [
                    ("bolt.fill",               lang.t("唤醒速度", "Wake speed"),     lang.t("极快（<1s）",       "Fastest (<1s)")),
                    ("exclamationmark.triangle", lang.t("断电保护", "Power-loss safe"), lang.t("否，断电丢数据",    "No – data lost")),
                    ("battery.25",              lang.t("待机耗电", "Idle power"),      lang.t("正常（内存供电）",  "Normal (RAM on)")),
                ]
            case .hybrid:
                return [
                    ("bolt.fill",               lang.t("唤醒速度", "Wake speed"),     lang.t("快（<2s）",         "Fast (<2s)")),
                    ("checkmark.shield.fill",   lang.t("断电保护", "Power-loss safe"), lang.t("是，磁盘有备份",    "Yes – disk backup")),
                    ("battery.50",              lang.t("待机耗电", "Idle power"),      lang.t("正常（macOS 默认）","Normal (default)")),
                ]
            case .deepHibernate:
                return [
                    ("tortoise.fill",           lang.t("唤醒速度", "Wake speed"),     lang.t("慢（10–30s）",      "Slow (10–30s)")),
                    ("checkmark.shield.fill",   lang.t("断电保护", "Power-loss safe"), lang.t("是，内存完全写盘",  "Yes – full RAM dump")),
                    ("battery.100",             lang.t("待机耗电", "Idle power"),      lang.t("极低（RAM 断电）",  "Minimal (RAM off)")),
                ]
            }
        }()

        // （执行按钮已移除）
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        Image(systemName: rows[i].0)
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.powerHibernate.accent)
                            .frame(width: 14, alignment: .center)
                        Text(rows[i].1)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(rows[i].2)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(AppTheme.powerHibernate.accent.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 8))
        }
        .animation(.easeInOut(duration: 0.15), value: mode)
    }

    // MARK: - System Config Card（系统配置卡片 — 结构化展示）

    private var pmsetInfoCard: some View {
        VStack(spacing: 0) {
            // 标题行（可折叠）
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(lang.t("系统配置", "System Config"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if showPmsetInfo {
                    Button(action: { viewModel.refreshPmsetInfo() }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.blue)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(showPmsetInfo ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: showPmsetInfo)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { showPmsetInfo.toggle() }
                if showPmsetInfo { viewModel.refreshPmsetInfo() }
            }
            .padding(.horizontal, AppTheme.cardPadding)
            .padding(.vertical, 8)
            .background(AppTheme.cardBackground,
                        in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))

            if showPmsetInfo {
                systemConfigGrid
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// 结构化系统配置网格
    private var systemConfigGrid: some View {
        VStack(spacing: 0) {

            // ── 当前设置效果总结 ─────────────────────────────────────
            configSummaryView

            // ── 合盖行为 ─────────────────────────────────────────
            configSectionHeader(lang.t("合盖行为", "Lid Behavior"))
            configRow(
                icon: "laptopcomputer.closed",
                iconColor: AppTheme.lid.icon,
                label: lang.t("合上盖子后", "When lid closes"),
                value: viewModel.lidWillSleep
                    ? lang.t("进入休眠", "Sleeps")
                    : lang.t("保持运行", "Stays awake"),
                valueColor: viewModel.lidWillSleep ? .green : .orange,
                detail: (
                    cmd: viewModel.lidWillSleep
                        ? "pmset -g | grep disablesleep  → 0"
                        : "pmset -g | grep disablesleep  → 1  /  pgrep caffeinate",
                    explain: viewModel.lidWillSleep
                        ? lang.t("disablesleep=0，合盖后 macOS 正常触发睡眠流程", "disablesleep=0: macOS sleeps normally on lid close")
                        : lang.t("disablesleep=1 或 caffeinate 进程阻止了睡眠，合盖后系统继续运行", "disablesleep=1 or caffeinate prevents sleep – system stays on")
                )
            )
            configRow(
                icon: "wifi",
                iconColor: .blue,
                label: lang.t("睡眠期间网络", "Network while asleep"),
                value: viewModel.sysNetworkOverSleep == 1
                    ? lang.t("保持连接", "Stays connected")
                    : lang.t("断开连接", "Disconnected"),
                valueColor: viewModel.sysNetworkOverSleep == 1 ? .green : .secondary,
                detail: (
                    cmd: "pmset -g | grep networkoversleep  → \(viewModel.sysNetworkOverSleep < 0 ? "?" : "\(viewModel.sysNetworkOverSleep)")",
                    explain: lang.t("1=睡眠时维持网络唤醒（Power Nap），0=完全断网省电", "1=keep network for Power Nap; 0=disconnect to save power")
                )
            )

            configDivider()

            // ── 电源键行为 ────────────────────────────────────────
            configSectionHeader(lang.t("电源键行为", "Power Button"))
            let pbDisplaySleep = viewModel.powerButtonMode == .displaySleep
            configRow(
                icon: "power",
                iconColor: AppTheme.powerButton.icon,
                label: lang.t("短按电源键", "Short press"),
                value: pbDisplaySleep
                    ? lang.t("锁屏", "Lock screen")
                    : lang.t("系统睡眠", "System sleep"),
                valueColor: pbDisplaySleep ? .cyan : .secondary,
                detail: (
                    cmd: pbDisplaySleep
                        ? "defaults read com.apple.loginwindow PowerButtonSleepsSystem  → 0"
                        : "defaults read com.apple.loginwindow PowerButtonSleepsSystem  → 1（默认）",
                    explain: pbDisplaySleep
                        ? lang.t("PowerButtonSleepsSystem=NO，短按只灭屏，系统继续运行，适合外接显示器场景", "PowerButtonSleepsSystem=NO: press turns off display only; system keeps running")
                        : lang.t("macOS 默认行为，短按电源键触发系统睡眠", "Default macOS behavior: short press puts the system to sleep")
                )
            )

            configDivider()

            // ── 休眠模式 ─────────────────────────────────────────
            configSectionHeader(lang.t("睡眠深度", "Sleep Depth"))
            configRow(
                icon: "sleep",
                iconColor: AppTheme.powerHibernate.icon,
                label: lang.t("当前睡眠深度", "Active depth"),
                value: hibernateModeLabel(viewModel.sysHibernateMode),
                valueColor: AppTheme.powerHibernate.accent,
                detail: (
                    cmd: "pmset -g | grep hibernatemode  → \(viewModel.sysHibernateMode < 0 ? "?" : "\(viewModel.sysHibernateMode)")",
                    explain: lang.t("0=睡眠（唤醒最快，断电丢失）  3=混合（默认，断电安全）  25=休眠（RAM断电，零耗电）",
                                    "0=RAM only (fastest)  3=Hybrid (default, safe)  25=Deep (RAM off, zero draw)")
                )
            )
            // 深度待机：只有 sleep > 0 时才有意义
            let standbyEffective = viewModel.sysStandby == 1 && viewModel.sysSystemSleep > 0
                                   && viewModel.sysSleepBlockers.isEmpty
            configRow(
                icon: "moon.stars.fill",
                iconColor: .gray,
                label: lang.t("超长待机节电", "Extended standby"),
                value: standbyEffective
                    ? lang.t("进入深度待机", "Deep standby")
                    : (viewModel.sysStandby == 1
                        ? lang.t("不生效（自动睡眠已关闭）", "N/A – auto-sleep is off")
                        : lang.t("已禁用", "Disabled")),
                valueColor: standbyEffective ? .green : .secondary,
                detail: (
                    cmd: "pmset -g | grep standby  → \(viewModel.sysStandby < 0 ? "?" : "\(viewModel.sysStandby)")",
                    explain: standbyEffective
                        ? lang.t("系统睡眠后会进一步切断更多硬件供电，电池续航更长", "After sleeping, system cuts more power to extend battery life")
                        : lang.t("需要先开启自动睡眠（系统闲置超时 > 0），超长待机才能生效", "Requires auto-sleep timer > 0 to work – currently sleep is disabled")
                )
            )

            configDivider()

            // ── 自动休眠计时器 ────────────────────────────────────
            configSectionHeader(lang.t("自动睡眠计时器", "Auto-sleep Timers"))

            // 系统休眠行 — 区分"配置为0"和"被进程阻止"
            let sleepBlocked = !viewModel.sysSleepBlockers.isEmpty
            let sleepVal = viewModel.sysSystemSleep
            configRow(
                icon: "moon.zzz.fill",
                iconColor: AppTheme.sleep.icon,
                label: lang.t("系统闲置后睡眠", "System sleeps after"),
                value: sleepBlocked
                    ? lang.t("被 \(viewModel.sysSleepBlockers.joined(separator: "、")) 阻止",
                              "Blocked by \(viewModel.sysSleepBlockers.joined(separator: ", "))")
                    : (sleepVal == 0
                        ? lang.t("已关闭", "Off")
                        : lang.t("\(sleepVal) 分钟后", "After \(sleepVal) min")),
                valueColor: sleepBlocked ? .orange : (sleepVal == 0 ? .secondary : .primary),
                detail: (
                    cmd: "pmset -g | grep '^ sleep'  → \(sleepVal < 0 ? "?" : "\(sleepVal)")\(sleepBlocked ? " (prevented)" : "")",
                    explain: sleepBlocked
                        ? lang.t("计时器本身可能有效，但当前有程序（如 caffeinate）持有『阻止睡眠断言』，系统不会自动进入睡眠", "Timer may be set, but a process holds a sleep-prevention assertion (e.g. caffeinate)")
                        : (sleepVal == 0
                            ? lang.t("sleep=0 表示关闭了自动睡眠计时器，系统永远不会因为闲置而自动睡眠", "sleep=0: auto-sleep timer disabled; system never sleeps on its own")
                            : lang.t("系统闲置 \(sleepVal) 分钟后自动进入睡眠", "System auto-sleeps after \(sleepVal) min of inactivity"))
                )
            )

            // 当前睡眠阻止源（来自 pmset -g assertions，仅诊断，不自动处理）
            let assertionBlocked = !viewModel.sysAssertionBlockers.isEmpty
            configRow(
                icon: assertionBlocked ? "exclamationmark.triangle.fill" : "checkmark.shield.fill",
                iconColor: assertionBlocked ? .orange : .green,
                label: lang.t("当前阻止源", "Current blockers"),
                value: assertionBlocked
                    ? blockerSummary(viewModel.sysAssertionBlockers)
                    : lang.t("未发现", "None detected"),
                valueColor: assertionBlocked ? .orange : .green,
                detail: (
                    cmd: "pmset -g assertions",
                    explain: assertionBlocked
                        ? lang.t("当前阻止源：\(viewModel.sysAssertionBlockers.joined(separator: "；"))。HibernateControl 只提示，不会自动结束它们；建议先退出相关 App、停止音频播放或断开外设后再睡眠。", "Current blockers: \(viewModel.sysAssertionBlockers.joined(separator: "; ")). HibernateControl reports them only; quit the app, stop audio, or disconnect peripherals before sleeping.")
                        : lang.t("当前没有明显的第三方睡眠阻止源。", "No obvious third-party sleep blocker is active.")
                ),
                actionIcon: "arrow.clockwise",
                actionHelp: lang.t("重新检查睡眠阻止源", "Refresh sleep blockers")
            ) {
                viewModel.checkSleepBlockers()
            }

            // 显示器关闭行
            let dispBlocked = !viewModel.sysDisplaySleepBlockers.isEmpty
            let dispVal = viewModel.sysDisplaySleep
            configRow(
                icon: "display",
                iconColor: .cyan,
                label: lang.t("显示器闲置后关闭", "Display turns off after"),
                value: dispBlocked
                    ? lang.t("被 \(viewModel.sysDisplaySleepBlockers.joined(separator: "、")) 阻止",
                              "Blocked by \(viewModel.sysDisplaySleepBlockers.joined(separator: ", "))")
                    : (dispVal == 0
                        ? lang.t("已关闭", "Off")
                        : lang.t("\(dispVal) 分钟后", "After \(dispVal) min")),
                valueColor: dispBlocked ? .orange : (dispVal == 0 ? .secondary : .primary),
                detail: (
                    cmd: "pmset -g | grep displaysleep  → \(dispVal < 0 ? "?" : "\(dispVal)")\(dispBlocked ? " (prevented)" : "")",
                    explain: dispBlocked
                        ? lang.t("有程序阻止显示器关闭（如全屏播放、caffeinate -d）", "A process is preventing display sleep (e.g. fullscreen video, caffeinate -d)")
                        : (dispVal == 0
                            ? lang.t("displaysleep=0，显示器永远不会自动关闭", "displaysleep=0: display never turns off automatically")
                            : lang.t("显示器闲置 \(dispVal) 分钟后自动关闭", "Display turns off after \(dispVal) min of inactivity"))
                )
            )

            // 磁盘休眠行
            let diskVal = viewModel.sysDiskSleep
            configRow(
                icon: "internaldrive.fill",
                iconColor: AppTheme.disk.icon,
                label: lang.t("磁盘闲置后睡眠", "Disk sleeps after"),
                value: diskVal == 0
                    ? lang.t("已关闭", "Off")
                    : lang.t("\(diskVal) 分钟后", "After \(diskVal) min"),
                valueColor: diskVal == 0 ? .secondary : .primary,
                detail: (
                    cmd: "pmset -g | grep disksleep  → \(diskVal < 0 ? "?" : "\(diskVal)")",
                    explain: diskVal == 0
                        ? lang.t("disksleep=0，磁盘不会因闲置自动睡眠，适合外接硬盘或频繁读写场景", "disksleep=0: disk never spins down; good for external drives or frequent I/O")
                        : lang.t("磁盘闲置 \(diskVal) 分钟后自动停转以节省电量", "Disk spins down after \(diskVal) min to save power")
                )
            )
        }
        .padding(.horizontal, 4)
        .background(AppTheme.cardBackground,
                    in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    // ── 设置效果总结 ──────────────────────────────────────────

    /// 根据当前系统状态生成一句话总结
    private var configSummaryView: some View {
        let summary = generateConfigSummary()
        return Text(summary)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
    }

    private func generateConfigSummary() -> String {
        let lidSleeps = viewModel.lidWillSleep
        let pbSleeps = viewModel.powerButtonMode == .systemSleep
        let hm = viewModel.sysHibernateMode
        let sleepTimer = viewModel.sysSystemSleep
        let standby = viewModel.sysStandby == 1

        let hmName: String = {
            switch hm {
            case 0: return lang.t("睡眠模式（RAM供电，快速唤醒）", "sleep mode (RAM on, fast wake)")
            case 3: return lang.t("混合模式（快速唤醒+断电安全）", "hybrid mode (fast wake + power-loss safe)")
            case 25: return lang.t("休眠模式（零耗电，唤醒较慢）", "hibernate mode (zero power, slow wake)")
            default: return "mode \(hm)"
            }
        }()

        var parts: [String] = []

        // 合盖
        if lidSleeps {
            parts.append(lang.t("合盖后进入\(hmName)", "Lid close enters \(hmName)"))
        } else {
            parts.append(lang.t("合盖后保持运行", "Stays awake when lid closes"))
        }

        // 电源键
        if pbSleeps {
            parts.append(lang.t("电源键可触发睡眠", "power button triggers sleep"))
        } else {
            parts.append(lang.t("电源键仅锁屏", "power button only locks screen"))
        }

        // 闲置计时器
        if sleepTimer > 0 {
            if lidSleeps {
                parts.append(lang.t("闲置\(sleepTimer)分钟自动睡眠", "auto-sleeps after \(sleepTimer) min idle"))
            } else {
                parts.append(lang.t("闲置计时器已设但被合盖不睡眠覆盖", "idle timer set but overridden by lid-awake mode"))
            }
        }

        // 深度待机
        if standby && lidSleeps && sleepTimer > 0 {
            parts.append(lang.t("之后进入深度待机节电", "then enters deep standby"))
        }

        return parts.joined(separator: lang.t("；", "; ")) + "。"
    }

    // ── 辅助视图组件 ────────────────────────────────────────────

    private func configSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    /// detail: (命令示例, 状态解读)，非 nil 时显示可展开的灰色说明栏
    private func configRow(
        icon: String, iconColor: Color,
        label: String, value: String, valueColor: Color,
        detail: (cmd: String, explain: String)? = nil,
        actionIcon: String? = nil,
        actionHelp: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        ConfigRowView(
            icon: icon, iconColor: iconColor,
            label: label, value: value, valueColor: valueColor,
            detail: detail,
            actionIcon: actionIcon,
            actionHelp: actionHelp,
            action: action
        )
    }

    private func configDivider() -> some View {
        Divider()
            .padding(.horizontal, 12)
            .padding(.top, 6)
    }

    // ── 辅助格式化函数 ─────────────────────────────────────────

    private func idleTimeLabel(_ val: Int) -> String {
        guard val >= 0 else { return "—" }
        if val == 0 { return lang.t("从不自动休眠", "Never") }
        if val == 1 { return lang.t("1 分钟后", "After 1 min") }
        return lang.t("\(val) 分钟后", "After \(val) min")
    }

    private func hibernateModeLabel(_ val: Int) -> String {
        switch val {
        case 0:  return lang.t("睡眠 (0)", "Sleep (0)")
        case 3:  return lang.t("混合 (3)", "Hybrid (3)")
        case 25: return lang.t("休眠 (25)", "Hibernate (25)")
        default: return val >= 0 ? "\(val)" : "—"
        }
    }

    private func blockerSummary(_ blockers: [String]) -> String {
        guard let first = blockers.first else { return lang.t("未发现", "None detected") }
        let name = first.components(separatedBy: " — ").first ?? first
        if blockers.count == 1 {
            return name
        }
        return lang.t("\(name) 等 \(blockers.count) 项", "\(name) +\(blockers.count - 1)")
    }

    // MARK: - Apply All Bar（底部操作栏）
    // 左侧状态 + 右侧「全部应用」+「退出」按钮

    private var applyAllBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                // 全部应用（最左）
                Button(action: {
                    Task { await viewModel.applyAll() }
                }) {
                    HStack(spacing: 5) {
                        if viewModel.applyAllStatus.isApplying {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "bolt.circle.fill")
                                .font(.system(size: 13))
                        }
                        Text(lang.t("全部应用", "Apply All"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(viewModel.applyAllStatus.isApplying)

                applyAllStatusView
                Spacer()

                // 立即休眠（图标，退出左边）
                Button(action: {
                    Task { await viewModel.hibernateNow() }
                }) {
                    Group {
                        if viewModel.hibernateNowStatus.isApplying {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        } else {
                            Image(systemName: "moon.zzz.fill")
                                .font(.system(size: 14, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .help(lang.t("按当前睡眠深度立即睡眠", "Sleep using the selected depth"))
                .disabled(viewModel.hibernateNowStatus.isApplying || viewModel.sleepNoWakeStatus.isApplying)

                // 放入书包：混合睡眠 + 关闭唤醒源
                Button(action: {
                    Task { await viewModel.sleepNoWake() }
                }) {
                    Group {
                        if viewModel.sleepNoWakeStatus.isApplying {
                            ProgressView().controlSize(.small).scaleEffect(0.7)
                        } else {
                            Image(systemName: "bag.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .help(lang.t("进入睡眠并关闭网络/后台唤醒源，适合合盖放入书包", "Sleep and disable network/background wake sources before putting the Mac in a bag"))
                .disabled(viewModel.hibernateNowStatus.isApplying || viewModel.sleepNoWakeStatus.isApplying)

                // 退出（红色电源图标，最右）
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    @ViewBuilder
    private var applyAllStatusView: some View {
        switch viewModel.applyAllStatus {
        case .idle:
            EmptyView()
        case .applying:
            HStack(spacing: 4) {
                Circle().fill(.blue).frame(width: 6, height: 6)
                    .opacity(0.8)
                Text(lang.t("应用中...", "Applying..."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .applied:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text(lang.t("已全部应用", "All Applied"))
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }
        case .error(let msg):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Reusable Components（可复用 UI 组件）

    /// 模式选择器 — 水平排列的分段按钮组，选中后立即执行 onSelect 回调
    /// - selection: 绑定的状态变量
    /// - options: 元组数组 (枚举值, 显示文本, SF Symbol 图标名)
    /// - onSelect: 选中某项后立即触发的异步操作（即点即应用）
    private func modePicker<T: Hashable>(
        selection: Binding<T>,
        options: [(T, String, String)],
        onSelect: @escaping () async -> Void = {}
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<options.count, id: \.self) { i in
                let option = options[i]
                let isSelected = selection.wrappedValue == option.0
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) { selection.wrappedValue = option.0 }
                    Task { await onSelect() }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: option.2)
                            .font(.system(size: 10, weight: .medium))
                        Text(option.1)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        isSelected
                            ? AnyShapeStyle(.tint.opacity(0.12))
                            : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .contentShape(Rectangle())
                    .foregroundStyle(isSelected ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color(nsColor: .separatorColor).opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    private func minuteRow(
        icon: String,
        label: String,
        value: Binding<Int>,
        accent: Color
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(accent)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 4) {
                Button(action: { if value.wrappedValue > 1 { value.wrappedValue -= 1 } }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Text("\(value.wrappedValue) \(lang.t("分钟", "min"))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(width: 52)

                Button(action: { if value.wrappedValue < 180 { value.wrappedValue += 1 } }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Config Row View（可展开说明的配置行）

struct ConfigRowView: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let valueColor: Color
    let detail: (cmd: String, explain: String)?
    let actionIcon: String?
    let actionHelp: String?
    let action: (() -> Void)?

    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            // 主行
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)
                    .frame(width: 16, alignment: .center)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 180, alignment: .trailing)
                if let actionIcon, let action {
                    Button(action: action) {
                        Image(systemName: actionIcon)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(actionHelp ?? "")
                }
                // 展开箭头（仅当有 detail 时显示）
                if detail != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.18), value: expanded)
                        .padding(.leading, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture {
                if detail != nil {
                    withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                }
            }

            // 展开的说明栏
            if expanded, let d = detail {
                VStack(alignment: .leading, spacing: 4) {
                    // 指令行
                    HStack(spacing: 4) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(d.cmd)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    // 解读行
                    Text(d.explain)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 7)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Setting Card（通用设置卡片组件）
// 包含：图标 + 标题 + 状态徽标 + 可选的「应用」按钮 + 自定义内容区域。

struct SettingCard<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let status: ActionStatus
    var showApplyButton: Bool = true
    var isCollapsible: Bool = false
    var collapsedSummary: String? = nil   // 折叠时在标题旁显示的摘要文字
    var alwaysShowSummary: Bool = false   // true = 展开时标题行也常驻显示摘要
    @ViewBuilder let content: () -> Content
    let applyAction: () async -> Void
    @EnvironmentObject private var lang: LanguageManager
    @State private var collapsed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: collapsed ? 0 : 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                // 折叠时显示摘要胶囊（或 alwaysShowSummary=true 时始终显示）
                if (collapsed || alwaysShowSummary), let summary = collapsedSummary {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(iconColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(iconColor.opacity(0.1), in: Capsule())
                        .transition(.opacity)
                }
                statusBadge
                if isCollapsible {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(collapsed ? 0 : 90))
                        .animation(.easeInOut(duration: 0.2), value: collapsed)
                }
                if showApplyButton {
                    applyActionButton
                }
            }
            // 整个标题行可点击折叠（排除应用按钮区域）
            .contentShape(Rectangle())
            .onTapGesture {
                if isCollapsible {
                    withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() }
                }
            }
            if !collapsed {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .idle:
            EmptyView()
        case .applying:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.7)
        case .applied:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
        }
    }

    private var applyActionButton: some View {
        Button(action: { Task { await applyAction() } }) {
            Text(lang.t("应用", "Apply"))
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .disabled(status.isApplying)
    }
}
