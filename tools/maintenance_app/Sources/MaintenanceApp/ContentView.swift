import SwiftUI
import AppKit
import MaintenanceCore

enum MaintenanceSection: String, CaseIterable, Identifiable {
    case overview = "总览"
    case diskCleanup = "磁盘清理"
    case fileOrganizer = "文件整理"
    case loginItems = "登录项"
    case scheduledTasks = "定时任务"

    var id: String { rawValue }
}

enum MaintenanceDesign {
    static let contentWidth: CGFloat = 880
    static let sidebarWidth: CGFloat = 176
    static let metricColumnWidth: CGFloat = 150
    static let rowMinHeight: CGFloat = 64
    static let accent = Color(red: 0.12, green: 0.43, blue: 0.92)

    // 与 Figma 稿一致，主内容保持窄宽度，避免工具界面在大屏上铺满。
    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    static let paneBackground = Color(nsColor: .controlBackgroundColor)
    static let divider = Color(nsColor: .separatorColor).opacity(0.65)
}

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var selection: MaintenanceSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(MaintenanceSection.allCases, selection: $selection) { section in
                Text(section.rawValue)
                    .font(.callout.weight(selection == section ? .semibold : .regular))
                    .padding(.vertical, 4)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("本机维护")
            .navigationSplitViewColumnWidth(
                min: 160,
                ideal: MaintenanceDesign.sidebarWidth,
                max: 220
            )
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Divider()
                    detailView
                }
                .padding(.horizontal, 34)
                .padding(.top, 36)
                .padding(.bottom, 32)
                .frame(maxWidth: MaintenanceDesign.contentWidth, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(MaintenanceDesign.pageBackground)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 980, minHeight: 660)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.refreshFromDisk()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                Button {
                    viewModel.isShowingRunDetails.toggle()
                } label: {
                    Label("运行详情", systemImage: "terminal")
                }
                .disabled(viewModel.lastRunDetails == nil)
            }
        }
        .inspector(isPresented: $viewModel.isShowingRunDetails) {
            RunDetailsView(details: viewModel.lastRunDetails)
                .inspectorColumnWidth(min: 360, ideal: 460, max: 640)
        }
        .sheet(isPresented: $viewModel.isShowingLogPreview) {
            LogPreviewSheet(title: viewModel.logPreviewTitle, logs: viewModel.logPreviews)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(selection?.rawValue ?? "总览")
                        .font(.system(size: 32, weight: .bold))
                    HStack(spacing: 10) {
                        if viewModel.isRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(2)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 16)
                HStack(spacing: 8) {
                    Button("扫描") {
                        viewModel.runScan()
                    }
                    .disabled(viewModel.isRunning)
                    Button("执行保守维护") {
                        viewModel.runConservativeMaintenance()
                    }
                    .disabled(viewModel.isRunning)
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.small)
            }
            ReportActionBar(
                reportAvailable: viewModel.report != nil,
                openReport: viewModel.openLatestReport,
                copySummary: viewModel.copyReportSummary,
                exportSummary: viewModel.exportReportSummary
            )
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .overview {
        case .overview:
            OverviewView(
                report: viewModel.report,
                healthSummary: viewModel.healthSummary,
                launchAgents: viewModel.launchAgents,
                onOpenPlist: viewModel.openInstalledPlist,
                onOpenLogs: viewModel.openLogDirectory,
                onPreviewLogs: viewModel.previewLogs,
                onReinstall: viewModel.reinstallLaunchAgent
            )
        case .diskCleanup:
            DiskCleanupView(report: viewModel.report, diskUsage: viewModel.diskUsage)
        case .fileOrganizer:
            FileOrganizerView(
                report: viewModel.report,
                configuredSources: viewModel.fileOrganizerSourceConfig.sources,
                onAddSource: viewModel.addFileOrganizerSource,
                onRemoveSource: viewModel.removeFileOrganizerSource
            )
        case .loginItems:
            LoginItemsView(report: viewModel.report)
        case .scheduledTasks:
            ScheduledTasksView(
                launchAgents: viewModel.launchAgents,
                onOpenPlist: viewModel.openInstalledPlist,
                onOpenLogs: viewModel.openLogDirectory,
                onPreviewLogs: viewModel.previewLogs,
                onReinstall: viewModel.reinstallLaunchAgent
            )
        }
    }
}

struct ReportActionBar: View {
    let reportAvailable: Bool
    let openReport: () -> Void
    let copySummary: () -> Void
    let exportSummary: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("打开报告", action: openReport)
            Button("复制摘要", action: copySummary)
                .disabled(!reportAvailable)
            Button("导出摘要", action: exportSummary)
                .disabled(!reportAvailable)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct OverviewView: View {
    let report: MaintenanceReport?
    let healthSummary: MaintenanceHealthSummary
    let launchAgents: [LaunchAgentState]
    let onOpenPlist: (LaunchAgentState) -> Void
    let onOpenLogs: (LaunchAgentState) -> Void
    let onPreviewLogs: (LaunchAgentState) -> Void
    let onReinstall: (LaunchAgentState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HealthSummaryPanel(summary: healthSummary)
            if let report {
                MetricGrid(metrics: [
                    ("待清理项", "\(report.summary.planned)"),
                    ("预计释放", ByteFormatter.string(from: report.summary.bytesPlanned)),
                    ("文件整理动作", "\(report.fileOrganizer?.summary.actionCount ?? 0)"),
                    ("登录项复核", "\(report.loginItems?.summary.manualReviewCount ?? 0)")
                ])
                Text("最近报告：\(report.generatedAt)")
                    .foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("暂无报告", systemImage: "doc.text.magnifyingglass", description: Text("点击“扫描”生成第一份维护报告。"))
            }

            SectionTitle("定时任务状态")
            ScheduledTasksView(
                launchAgents: launchAgents,
                showsManagementActions: false,
                onOpenPlist: onOpenPlist,
                onOpenLogs: onOpenLogs,
                onPreviewLogs: onPreviewLogs,
                onReinstall: onReinstall
            )
        }
    }
}

struct HealthSummaryPanel: View {
    let summary: MaintenanceHealthSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SectionTitle("健康检查")
                HealthSeverityBadge(severity: summary.highestSeverity)
                Spacer(minLength: 12)
                HealthCountStrip(summary: summary)
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.highestSeverity.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(summary.highestSeverity.tint)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.statusTitle)
                        .font(.headline)
                    Text(summary.statusDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            if summary.issues.isEmpty {
                Text("继续保持当前定时任务和保守清理节奏。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(summary.issues.prefix(6)) { issue in
                        HealthIssueRow(issue: issue)
                    }
                    if summary.issues.count > 6 {
                        Text("另有 \(summary.issues.count - 6) 条提醒未展开。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 34)
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }
}

struct HealthCountStrip: View {
    let summary: MaintenanceHealthSummary

    var body: some View {
        HStack(spacing: 10) {
            ForEach([MaintenanceHealthSeverity.critical, .warning, .info], id: \.self) { severity in
                let count = summary.count(for: severity)
                if count > 0 {
                    Text("\(severity.label) \(count)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(severity.tint)
                }
            }
        }
    }
}

struct HealthSeverityBadge: View {
    let severity: MaintenanceHealthSeverity

    var body: some View {
        Text(severity.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(severity.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(severity.tint.opacity(0.12)))
    }
}

struct HealthIssueRow: View {
    let issue: MaintenanceHealthIssue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(issue.severity.tint)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(issue.title)
                        .font(.callout.weight(.semibold))
                    Text(issue.severity.label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(issue.severity.tint)
                }
                Text(issue.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(issue.recommendedAction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let affectedPath = issue.affectedPath, !affectedPath.isEmpty {
                    Text(affectedPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 5)
    }
}

extension MaintenanceHealthSeverity {
    var tint: Color {
        switch self {
        case .ok:
            return .green
        case .info:
            return MaintenanceDesign.accent
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    var systemImage: String {
        switch self {
        case .ok:
            return "checkmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .critical:
            return "xmark.octagon.fill"
        }
    }
}

struct MetricGrid: View {
    let metrics: [(String, String)]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 12) {
            GridRow {
                ForEach(metrics, id: \.0) { metric in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(metric.1)
                            .font(.system(size: 26, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(metric.0)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: MaintenanceDesign.metricColumnWidth, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

struct DiskCleanupView: View {
    let report: MaintenanceReport?
    let diskUsage: DiskUsageSnapshot?
    @State private var searchText = ""
    @State private var statusFilter = FilterConstants.allValue
    @State private var categoryFilter = FilterConstants.allValue
    @State private var selectedCandidate: CleanupCandidate?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let report {
                let statuses = FilterConstants.sortedValues(report.candidates.map(\.status))
                let categories = FilterConstants.sortedValues(report.candidates.map(\.category))
                let filteredCandidates = CleanupCandidateFilter(
                    searchText: searchText,
                    status: FilterConstants.filterValue(statusFilter),
                    category: FilterConstants.filterValue(categoryFilter)
                ).apply(to: report.candidates)

                MetricGrid(metrics: [
                    ("计划删除", "\(report.summary.planned)"),
                    ("已删除", "\(report.summary.deleted)"),
                    ("跳过", "\(report.summary.skipped)"),
                    ("失败", "\(report.summary.failed)"),
                    ("当前显示", "\(filteredCandidates.count)")
                ])
                FilterBar(
                    searchText: $searchText,
                    searchPrompt: "搜索路径、类别或原因",
                    filters: [
                        FilterMenu(
                            title: "状态",
                            selection: $statusFilter,
                            options: statuses,
                            label: DiskCleanupLabels.status
                        ),
                        FilterMenu(
                            title: "类别",
                            selection: $categoryFilter,
                            options: categories,
                            label: { $0 }
                        )
                    ]
                )
                DiskUsagePanel(snapshot: diskUsage)
                SectionTitle("候选项")
                if report.candidates.isEmpty {
                    Text("当前没有磁盘清理候选项。").foregroundStyle(.secondary)
                } else if filteredCandidates.isEmpty {
                    Text("没有匹配当前筛选条件的候选项。").foregroundStyle(.secondary)
                } else {
                    ForEach(filteredCandidates) { candidate in
                        ActionRowView(
                            title: candidate.path,
                            subtitle: "\(candidate.category) · \(candidate.reason)",
                            trailing: "\(DiskCleanupLabels.status(candidate.status)) · \(ByteFormatter.string(from: candidate.sizeBytes))",
                            actionTitle: "详情",
                            action: {
                                selectedCandidate = candidate
                            }
                        )
                    }
                }
            } else {
                EmptyReportView()
            }
        }
        .sheet(item: $selectedCandidate) { candidate in
            CleanupCandidateDetailView(candidate: candidate)
        }
    }
}

struct DiskUsagePanel: View {
    let snapshot: DiskUsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("磁盘空间使用")
            if let snapshot {
                HStack(alignment: .center, spacing: 24) {
                    DiskUsageRingChart(fraction: snapshot.usedFraction)
                        .frame(width: 112, height: 112)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(snapshot.volumeName)
                            .font(.headline)
                        Text(snapshot.mountPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        HStack(spacing: 28) {
                            DiskUsageValue(title: "总容量", bytes: snapshot.totalBytes)
                            DiskUsageValue(title: "已使用", bytes: snapshot.usedBytes)
                            DiskUsageValue(title: "可用", bytes: snapshot.availableBytes)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("暂时无法读取磁盘容量。")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct DiskUsageRingChart: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.14), lineWidth: 16)
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(
                    MaintenanceDesign.accent,
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.title3.bold())
        }
        .accessibilityLabel("磁盘已使用 \(Int((fraction * 100).rounded()))%")
    }
}

struct DiskUsageValue: View {
    let title: String
    let bytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ByteFormatter.string(from: bytes))
                .font(.callout.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct FileOrganizerView: View {
    let report: MaintenanceReport?
    let configuredSources: [FileOrganizerConfiguredSource]
    let onAddSource: () -> Void
    let onRemoveSource: (FileOrganizerConfiguredSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FileOrganizerSourceConfigView(
                configuredSources: configuredSources,
                onAddSource: onAddSource,
                onRemoveSource: onRemoveSource
            )
            if let organizer = report?.fileOrganizer {
                MetricGrid(metrics: [
                    ("来源目录", "\(organizer.summary.sourceCount)"),
                    ("整理动作", "\(organizer.summary.actionCount)"),
                    ("待处理目录", "\(organizer.summary.pendingDirectoryCount)"),
                    ("跳过条目", "\(organizer.summary.skippedCount)")
                ])
                ForEach(organizer.sources) { source in
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(source.source)
                        Text("动作 \(source.actionCount)，待处理目录 \(source.pendingDirectoryCount)，跳过 \(source.skippedCount)")
                            .foregroundStyle(.secondary)
                        ForEach(source.actions) { action in
                            RowView(title: action.source, subtitle: action.destination, trailing: action.status)
                        }
                        ForEach(source.pendingDirectories) { directory in
                            RowView(title: directory.directory, subtitle: "待人工处理", trailing: "")
                        }
                    }
                }
            } else {
                EmptyReportView()
            }
        }
    }
}

struct FileOrganizerSourceConfigView: View {
    let configuredSources: [FileOrganizerConfiguredSource]
    let onAddSource: () -> Void
    let onRemoveSource: (FileOrganizerConfiguredSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle("用户添加路径")
                Spacer()
                Button("添加路径", action: onAddSource)
                    .controlSize(.small)
            }
            if configuredSources.isEmpty {
                Text("未添加额外整理路径。默认仍会整理 Desktop、Downloads、Documents 第一层。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(configuredSources) { source in
                    HStack(spacing: 12) {
                        Image(systemName: "folder")
                            .foregroundStyle(MaintenanceDesign.accent)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.path)
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Text(source.recursive ? "递归整理" : "只整理第一层")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Button("移除") {
                            onRemoveSource(source)
                        }
                        .controlSize(.small)
                    }
                    .frame(minHeight: 38)
                }
            }
        }
        .padding(.bottom, 4)
    }
}

struct LoginItemsView: View {
    let report: MaintenanceReport?
    @State private var searchText = ""
    @State private var selectedScope = LoginItemScope.all
    @State private var selectedItem: LoginItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let loginItems = report?.loginItems {
                let filteredItems = LoginItemFilter(
                    searchText: searchText,
                    category: selectedScope.category,
                    duplicateOnly: selectedScope.duplicateOnly
                ).apply(to: loginItems)

                MetricGrid(metrics: [
                    ("总项数", "\(loginItems.summary.itemCount)"),
                    ("plist", "\(loginItems.summary.launchPlistCount)"),
                    ("自有自动化", "\(loginItems.summary.ownAutomationCount)"),
                    ("人工复核", "\(loginItems.summary.manualReviewCount)"),
                    ("当前显示", "\(filteredItems.count)")
                ])
                LoginItemFilterBar(searchText: $searchText, selectedScope: $selectedScope)
                SectionTitle("重复显示名")
                if loginItems.duplicateDisplayNames.isEmpty {
                    Text("当前没有重复显示名。").foregroundStyle(.secondary)
                } else {
                    ForEach(loginItems.duplicateDisplayNames) { duplicate in
                        RowView(
                            title: duplicate.displayName,
                            subtitle: duplicate.identifiers.compactMap { $0 }.joined(separator: ", "),
                            trailing: "\(duplicate.count)"
                        )
                    }
                }
                SectionTitle("登录项明细")
                if filteredItems.isEmpty {
                    Text("没有匹配当前筛选条件的登录项。").foregroundStyle(.secondary)
                } else {
                    ForEach(filteredItems) { item in
                        LoginItemRowView(item: item) {
                            selectedItem = item
                        }
                    }
                    if filteredItems.count > 80 {
                        Text("当前筛选结果较多，可继续输入关键词缩小范围。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                SectionTitle("Launch plist")
                ForEach(loginItems.launchPlists.prefix(40)) { plist in
                    RowView(
                        title: plist.label ?? plist.path,
                        subtitle: plist.path,
                        trailing: plist.rootLevel ? "系统级" : "用户级"
                    )
                }
            } else {
                EmptyReportView()
            }
        }
        .sheet(item: $selectedItem) { item in
            LoginItemDetailView(item: item)
        }
    }
}

struct LoginItemRowView: View {
    let item: LoginItem
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LoginItemIconView(item: item)
                .frame(width: 28, height: 28)
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.body)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    let subtitle = item.urlPath ?? item.executablePath ?? item.identifier ?? ""
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                Spacer(minLength: 16)
                Text("\(LoginItemLabels.category(item.category)) · \(LoginItemLabels.action(item.suggestedAction))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                Button("详情", action: action)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
    }
}

struct LoginItemIconView: View {
    let item: LoginItem

    var body: some View {
        if let image = iconImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
                .padding(3)
        }
    }

    private var iconImage: NSImage? {
        for path in [item.urlPath, item.executablePath].compactMap({ $0 }) {
            if FileManager.default.fileExists(atPath: path) {
                return NSWorkspace.shared.icon(forFile: path)
            }
        }
        return nil
    }
}

struct ScheduledTasksView: View {
    let launchAgents: [LaunchAgentState]
    var showsManagementActions = true
    let onOpenPlist: (LaunchAgentState) -> Void
    let onOpenLogs: (LaunchAgentState) -> Void
    let onPreviewLogs: (LaunchAgentState) -> Void
    let onReinstall: (LaunchAgentState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if launchAgents.isEmpty {
                Text("未找到本地自动化任务。").foregroundStyle(.secondary)
            } else {
                ForEach(launchAgents) { task in
                    ScheduledTaskRow(
                        task: task,
                        showsManagementActions: showsManagementActions,
                        onOpenPlist: onOpenPlist,
                        onOpenLogs: onOpenLogs,
                        onPreviewLogs: onPreviewLogs,
                        onReinstall: onReinstall
                    )
                }
            }
        }
    }
}

struct ScheduledTaskRow: View {
    let task: LaunchAgentState
    let showsManagementActions: Bool
    let onOpenPlist: (LaunchAgentState) -> Void
    let onOpenLogs: (LaunchAgentState) -> Void
    let onPreviewLogs: (LaunchAgentState) -> Void
    let onReinstall: (LaunchAgentState) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ScheduledTaskIcon(label: task.label)
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.label)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(task.plistPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 16)
            Text(task.installed ? task.scheduleDescription : "未安装")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            HStack(spacing: 8) {
                if showsManagementActions {
                    Button("打开 plist") {
                        onOpenPlist(task)
                    }
                    .disabled(!task.installed)
                    Button("查看日志") {
                        onOpenLogs(task)
                    }
                }
                Button("预览日志") {
                    onPreviewLogs(task)
                }
                if showsManagementActions {
                    Button("重新安装") {
                        onReinstall(task)
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(minHeight: MaintenanceDesign.rowMinHeight)
    }
}

struct ScheduledTaskIcon: View {
    let label: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(MaintenanceDesign.accent)
            .frame(width: 20, height: 20)
            .background(Circle().fill(MaintenanceDesign.accent.opacity(0.12)))
            .accessibilityHidden(true)
    }

    private var systemImage: String {
        if label.contains("disk-cleanup") {
            return "externaldrive"
        }
        if label.contains("file-organizer") {
            return "folder"
        }
        if label.contains("app-cleanup") {
            return "app.badge"
        }
        return "clock"
    }
}

struct FilterBar: View {
    @Binding var searchText: String
    let searchPrompt: String
    let filters: [FilterMenu]

    var body: some View {
        HStack(spacing: 12) {
            TextField(searchPrompt, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 260, maxWidth: 420)
            ForEach(Array(filters.enumerated()), id: \.offset) { _, filter in
                filter
            }
        }
        .controlSize(.small)
    }
}

struct FilterMenu: View {
    let title: String
    @Binding var selection: String
    let options: [String]
    let label: (String) -> String

    var body: some View {
        Picker(title, selection: $selection) {
            Text("全部").tag(FilterConstants.allValue)
            ForEach(options, id: \.self) { option in
                Text(label(option)).tag(option)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 150)
    }
}

struct LoginItemFilterBar: View {
    @Binding var searchText: String
    @Binding var selectedScope: LoginItemScope

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("搜索名称、开发者、identifier、路径或建议动作", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 360, maxWidth: 560)
            Picker("范围", selection: $selectedScope) {
                ForEach(LoginItemScope.allCases) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)
        }
        .controlSize(.small)
    }
}
enum LoginItemScope: String, CaseIterable, Identifiable {
    case all
    case possibleRemnant
    case ownAutomation
    case duplicate
    case manualReview

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return "全部"
        case .possibleRemnant:
            return "残留"
        case .ownAutomation:
            return "自有"
        case .duplicate:
            return "重复"
        case .manualReview:
            return "复核"
        }
    }

    var category: String? {
        switch self {
        case .all, .duplicate:
            return nil
        case .possibleRemnant:
            return "possible_remnant"
        case .ownAutomation:
            return "own_automation"
        case .manualReview:
            return "manual_review"
        }
    }

    var duplicateOnly: Bool {
        self == .duplicate
    }
}

enum FilterConstants {
    static let allValue = "__all__"

    static func filterValue(_ value: String) -> String? {
        value == allValue ? nil : value
    }

    static func sortedValues(_ values: [String]) -> [String] {
        Array(Set(values)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

enum DiskCleanupLabels {
    static func status(_ value: String) -> String {
        switch value {
        case "planned":
            return "计划"
        case "deleted":
            return "已删"
        case "skipped":
            return "跳过"
        case "missing":
            return "缺失"
        case "failed":
            return "失败"
        default:
            return value
        }
    }
}

enum LoginItemLabels {
    static func category(_ value: String) -> String {
        switch value {
        case "own_automation":
            return "自有自动化"
        case "possible_remnant":
            return "疑似残留"
        case "manual_review":
            return "人工复核"
        case "system_background_item":
            return "系统后台"
        default:
            return value
        }
    }

    static func action(_ value: String) -> String {
        switch value {
        case "keep":
            return "保留"
        case "review", "manual_review":
            return "复核"
        case "remove_if_unused":
            return "不用则移除"
        default:
            return value
        }
    }
}

struct ActionRowView: View {
    let title: String
    let subtitle: String
    let trailing: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 16)
            Text(trailing)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            Button(actionTitle, action: action)
                .controlSize(.small)
        }
        .padding(.vertical, 6)
    }
}

struct RowView: View {
    let title: String
    let subtitle: String
    let trailing: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .lineLimit(2)
                    .textSelection(.enabled)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 16)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 6)
    }
}

struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
    }
}

struct EmptyReportView: View {
    var body: some View {
        ContentUnavailableView("暂无报告", systemImage: "doc.text", description: Text("请先点击“扫描”。"))
    }
}

struct CleanupCandidateDetailView: View {
    let candidate: CleanupCandidate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("清理候选项详情")
                    .font(.title2.bold())
                DetailField(title: "路径", value: candidate.path, monospaced: true)
                DetailField(title: "状态", value: DiskCleanupLabels.status(candidate.status))
                DetailField(title: "类别", value: candidate.category)
                DetailField(title: "原因", value: candidate.reason)
                DetailField(title: "风险等级", value: candidate.riskLevel)
                DetailField(title: "大小", value: ByteFormatter.string(from: candidate.sizeBytes))
                OptionalDetailField(title: "错误", value: candidate.error)
            }
            .padding(24)
            .frame(width: 560, alignment: .leading)
        }
    }
}

struct LoginItemDetailView: View {
    let item: LoginItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("登录项详情")
                    .font(.title2.bold())
                DetailField(title: "显示名", value: item.displayName)
                OptionalDetailField(title: "名称", value: item.name)
                OptionalDetailField(title: "开发者", value: item.developerName)
                OptionalDetailField(title: "identifier", value: item.identifier, monospaced: true)
                OptionalDetailField(title: "URL 路径", value: item.urlPath, monospaced: true)
                OptionalDetailField(title: "可执行路径", value: item.executablePath, monospaced: true)
                OptionalDetailField(title: "类型", value: item.itemType)
                OptionalDetailField(title: "启用状态", value: item.disposition)
                DetailField(title: "分类", value: LoginItemLabels.category(item.category))
                DetailField(title: "建议动作", value: LoginItemLabels.action(item.suggestedAction))
                DetailField(title: "风险等级", value: item.riskLevel)
                DetailField(title: "分类原因", value: item.classificationReason)
            }
            .padding(24)
            .frame(width: 620, alignment: .leading)
        }
    }
}

struct OptionalDetailField: View {
    let title: String
    let value: String?
    var monospaced = false

    var body: some View {
        if let value, !value.isEmpty {
            DetailField(title: title, value: value, monospaced: monospaced)
        }
    }
}

struct LogPreviewSheet: View {
    let title: String
    let logs: [MaintenanceLogPreview]
    @State private var selectedPath: String?

    private var selectedLog: MaintenanceLogPreview? {
        logs.first { $0.path == selectedPath } ?? logs.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            LogPreviewListPane(
                logs: logs,
                selectedPath: $selectedPath
            )
            .frame(width: 294)

            if let selectedLog {
                LogPreviewDetailView(log: selectedLog)
            } else {
                ContentUnavailableView("暂无日志", systemImage: "doc.text.magnifyingglass", description: Text("对应日志目录中没有可预览的日志文件。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(15)
        .frame(width: 812, height: 556)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            selectedPath = logs.first?.path
        }
    }
}

struct LogPreviewListPane: View {
    let logs: [MaintenanceLogPreview]
    @Binding var selectedPath: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(logs) { log in
                    LogPreviewListItem(
                        log: log,
                        isSelected: selectedPath == log.path || (selectedPath == nil && logs.first?.path == log.path)
                    ) {
                        selectedPath = log.path
                    }
                }
            }
            .padding(10)
        }
        .background(MaintenanceDesign.paneBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxHeight: .infinity)
    }
}

struct LogPreviewListItem: View {
    let log: MaintenanceLogPreview
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(log.fileName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("\(AppDateFormatter.runTimestamp.string(from: log.modifiedAt)) · \(ByteFormatter.string(from: log.sizeBytes))")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(isSelected ? MaintenanceDesign.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct LogPreviewDetailView: View {
    let log: MaintenanceLogPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(log.fileName)
                .font(.system(size: 20, weight: .bold))
                .lineLimit(2)
                .textSelection(.enabled)
            HStack(spacing: 16) {
                Text(AppDateFormatter.runTimestamp.string(from: log.modifiedAt))
                Text(ByteFormatter.string(from: log.sizeBytes))
                if log.isTruncated {
                    Text("仅显示尾部")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            DetailField(title: "路径", value: log.path, monospaced: true)
            if log.content.isEmpty {
                Text("日志文件为空。")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    Text(log.content)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct RunDetailsView: View {
    let details: CommandRunDetails?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let details {
                    Text(details.title)
                        .font(.title2.bold())
                    RunStatusView(details: details)
                    DetailField(title: "开始时间", value: AppDateFormatter.runTimestamp.string(from: details.startedAt))
                    DetailField(title: "结束时间", value: AppDateFormatter.runTimestamp.string(from: details.finishedAt))
                    DetailField(title: "命令", value: details.commandLine, monospaced: true)
                    RunOutputSection(title: "stdout", text: details.stdout)
                    RunOutputSection(title: "stderr", text: details.stderr)
                } else {
                    ContentUnavailableView("暂无运行详情", systemImage: "terminal", description: Text("执行预览或维护后会显示命令输出。"))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RunStatusView: View {
    let details: CommandRunDetails

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(details.succeeded ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(details.succeeded ? "成功" : "失败")
                .font(.headline)
            Text("退出码 \(details.exitStatus)")
                .foregroundStyle(.secondary)
        }
        .textSelection(.enabled)
    }
}

struct DetailField: View {
    let title: String
    let value: String
    var monospaced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .body)
                .textSelection(.enabled)
        }
    }
}

struct RunOutputSection: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            if text.isEmpty {
                Text("无输出")
                    .foregroundStyle(.secondary)
            } else {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

enum AppDateFormatter {
    static let runTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

enum ByteFormatter {
    static func string(from bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
