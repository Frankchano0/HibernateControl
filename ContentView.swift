import SwiftUI

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
}

// MARK: - Content View（主界面）
// 应用的主视图，采用上中下三段式布局：
// 1. 顶部标题栏 (headerView)
// 2. 中间可滚动的设置卡片区域（睡眠模式、磁盘睡眠、合盖模式、系统状态）
// 3. 底部"全部应用"操作栏 (applyAllBar)

struct ContentView: View {
    @StateObject private var viewModel = HibernateViewModel()
    @EnvironmentObject private var lang: LanguageManager
    @State private var showPmsetInfo = false
    @State private var hibernateModeExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: AppTheme.sectionSpacing) {
                    sleepModeCard
                    diskSleepCard
                    lidModeCard
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
            title: lang.t("自动休眠", "Auto Sleep"),
            status: viewModel.sleepStatus
        ) {
            VStack(spacing: 10) {
                modePicker(selection: $viewModel.sleepMode, options: [
                    (SleepMode.neverSleep, lang.t("永不休眠", "Never"), "infinity"),
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

    // MARK: - Disk Sleep Card（磁盘睡眠设置卡片）
    // 控制硬盘空闲后自动休眠的时间。
    // - "Never Sleep"：磁盘永不休眠（pmset disksleep 0）
    // - "Custom"：自定义磁盘休眠超时分钟数

    private var diskSleepCard: some View {
        SettingCard(
            icon: "internaldrive.fill",
            iconColor: AppTheme.disk.icon,
            title: lang.t("磁盘休眠", "Disk Hibernate"),
            status: viewModel.diskSleepStatus
        ) {
            VStack(spacing: 10) {
                modePicker(selection: $viewModel.diskSleepMode, options: [
                    (DiskSleepMode.neverSleep, lang.t("永不休眠", "Never"), "infinity"),
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
                (LidMode.sleepOnLidClose, lang.t("合盖休眠", "Sleep on Close"), "moon.fill"),
                (LidMode.noSleepOnLidClose, lang.t("合盖不休眠", "Stay Awake"), "eye.fill"),
            ])
        } applyAction: {
            await viewModel.applyLidMode()
        }
    }

    // MARK: - Power Button Hibernate Card（电源键休眠设置卡片）
    // MARK: - Hibernate Mode Card（休眠模式设置卡片）

    private var hibernateModeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题行（可点击折叠）
            HStack(spacing: 8) {
                Image(systemName: "sleep")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.powerHibernate.icon)
                Text(lang.t("休眠模式", "Hibernate Mode"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()

                // 缩起时显示当前模式名
                if !hibernateModeExpanded {
                    Text(currentHibernateModeName)
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.powerHibernate.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(AppTheme.powerHibernate.accent.opacity(0.1), in: Capsule())
                }

                // 状态徽标
                hibernateModeStatusBadge

                // 折叠箭头
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(hibernateModeExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: hibernateModeExpanded)

                // 应用按钮
                Button(action: { Task { await viewModel.applyHibernateMode() } }) {
                    Text(lang.t("应用", "Apply"))
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(viewModel.hibernateModeStatus.isApplying)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    hibernateModeExpanded.toggle()
                }
            }

            // 展开内容
            if hibernateModeExpanded {
                VStack(spacing: 8) {
                    ForEach([HibernateMode.memoryOnly, .hybrid, .deepHibernate], id: \.self) { mode in
                        hibernateModeRow(mode: mode)
                    }
                }
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(AppTheme.cardPadding)
        .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))
    }

    @ViewBuilder
    private var hibernateModeStatusBadge: some View {
        switch viewModel.hibernateModeStatus {
        case .idle: EmptyView()
        case .applying:
            ProgressView().controlSize(.mini).scaleEffect(0.7)
        case .applied:
            Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(.red)
        }
    }

    private var currentHibernateModeName: String {
        switch viewModel.hibernateMode {
        case .memoryOnly:    return lang.t("纯内存", "Memory Only")
        case .hybrid:        return lang.t("混合", "Hybrid")
        case .deepHibernate: return lang.t("深度休眠", "Deep Hibernate")
        }
    }

    @ViewBuilder
    private func hibernateModeRow(mode: HibernateMode) -> some View {
        let isSelected = viewModel.hibernateMode == mode
        let (icon, title, desc): (String, String, String) = {
            switch mode {
            case .memoryOnly:
                return ("bolt.fill",
                        lang.t("纯内存", "Memory Only"),
                        lang.t("唤醒最快，断电会丢数据，适合短时休眠", "Fastest wake. Data lost if power cut. Best for short naps."))
            case .hybrid:
                return ("square.stack.fill",
                        lang.t("混合（默认）", "Hybrid (Default)"),
                        lang.t("内存+磁盘双写，唤醒快，断电也能恢复", "Writes RAM + disk. Fast wake, safe if power cuts."))
            case .deepHibernate:
                return ("moon.zzz.fill",
                        lang.t("深度休眠", "Deep Hibernate"),
                        lang.t("RAM 完全断电，零耗电，唤醒慢，适合长时间不用", "RAM off, zero draw. Slow wake. Best for long periods."))
            }
        }()

        Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.hibernateMode = mode
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.powerHibernate.accent : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    Text(desc)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.powerHibernate.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSelected
                    ? AnyShapeStyle(AppTheme.powerHibernate.accent.opacity(0.08))
                    : AnyShapeStyle(Color.clear),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pmset Info Card（系统电源状态信息卡片）
    // 可折叠的面板，点击展开后显示当前 pmset 电源管理设置。
    // 执行 `pmset -g` 命令获取 sleep / displaysleep / disksleep 的当前值。

    private var pmsetInfoCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showPmsetInfo.toggle()
                    }
                    if showPmsetInfo { viewModel.refreshPmsetInfo() }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(lang.t("系统状态", "System State"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showPmsetInfo ? 90 : 0))
                    }
                }
                .buttonStyle(.plain)

                // 刷新按钮 — 重新读取 pmset 当前状态
                if showPmsetInfo {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.refreshPmsetInfo()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.blue)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, AppTheme.cardPadding)
            .padding(.vertical, 8)
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius))

            if showPmsetInfo {
                Text(viewModel.currentPmsetInfo.isEmpty ? "Loading..." : viewModel.currentPmsetInfo)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Apply All Bar（底部操作栏）
    // 左侧状态 + 右侧「全部应用」+「退出」按钮

    private var applyAllBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                applyAllStatusView
                Spacer()

                // 全部应用
                Button(action: {
                    Task { await viewModel.applyAll() }
                }) {
                    HStack(spacing: 6) {
                        if viewModel.applyAllStatus.isApplying {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "bolt.circle.fill")
                                .font(.system(size: 14))
                        }
                        Text(lang.t("全部应用", "Apply All"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(viewModel.applyAllStatus.isApplying)

                // 退出
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Text(lang.t("退出", "Quit"))
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                }
                .buttonStyle(.bordered)
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

// MARK: - Setting Card（通用设置卡片组件）
// 包含：图标 + 标题 + 状态徽标 + 可选的「应用」按钮 + 自定义内容区域。

struct SettingCard<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let status: ActionStatus
    var showApplyButton: Bool = true
    @ViewBuilder let content: () -> Content
    let applyAction: () async -> Void
    @EnvironmentObject private var lang: LanguageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                statusBadge
                if showApplyButton {
                    applyActionButton
                }
            }
            content()
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
