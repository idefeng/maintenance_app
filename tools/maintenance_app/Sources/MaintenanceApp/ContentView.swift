import SwiftUI
import AppKit
import MaintenanceCore

// MARK: - Maintenance Section Enum
enum MaintenanceSection: String, CaseIterable, Identifiable {
    case overview = "总览"
    case diskCleanup = "磁盘清理"
    case fileOrganizer = "文件整理"
    case loginItems = "登录项"
    case appCleanup = "应用残留"
    case scheduledTasks = "定时任务"

    var id: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .overview: return "house"
        case .diskCleanup: return "externaldrive"
        case .fileOrganizer: return "arrow.triangle.2.circlepath"
        case .loginItems: return "key.viewfinder"
        case .appCleanup: return "trash"
        case .scheduledTasks: return "timer"
        }
    }
}

// MARK: - Design System Constants
enum MaintenanceDesign {
    static let contentWidth: CGFloat = 880
    static let sidebarWidth: CGFloat = 186
    static let rowMinHeight: CGFloat = 64
    static let accent = Color(red: 0.12, green: 0.43, blue: 0.92)

    static let pageBackground = Color(nsColor: .windowBackgroundColor)
    static let paneBackground = Color(nsColor: .controlBackgroundColor)
    static let divider = Color(nsColor: .separatorColor).opacity(0.65)
}

// MARK: - Main ContentView Struct
struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var selection: MaintenanceSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(MaintenanceSection.allCases, selection: $selection) { section in
                HStack(spacing: 8) {
                    Image(systemName: section.systemImage)
                        .foregroundStyle(selection == section ? .white : MaintenanceDesign.accent)
                        .frame(width: 18)
                    Text(section.rawValue)
                        .font(.callout.weight(selection == section ? .semibold : .regular))
                }
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
        .sheet(isPresented: $viewModel.isShowingOmniProgress) {
            OmniMaintenanceSheet(viewModel: viewModel)
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
                onReinstall: viewModel.reinstallLaunchAgent,
                onOmniMaintenance: viewModel.runOmniMaintenance
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
        case .appCleanup:
            AppCleanupView(viewModel: viewModel)
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

// MARK: - Generic Support Components
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

struct MetricGrid: View {
    let metrics: [(String, String, String)] // (label, value, systemImage)

    var body: some View {
        HStack(spacing: 16) {
            ForEach(metrics, id: \.0) { label, value, systemImage in
                HStack(spacing: 12) {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundStyle(MaintenanceDesign.accent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(MaintenanceDesign.accent.opacity(0.1)))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(value)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .hoverScale()
            }
        }
        .padding(.vertical, 4)
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
        ContentUnavailableView("暂无报告", systemImage: "doc.text", description: Text("请先点击右上角“扫描”生成第一份状态报告。"))
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
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPath: String?
    @State private var logSearchText = ""

    private var selectedLog: MaintenanceLogPreview? {
        logs.first { $0.path == selectedPath } ?? logs.first
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(MaintenanceDesign.accent)
                    Text(title)
                        .font(.headline)
                }
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 4)
            
            Divider()
            
            HStack(alignment: .top, spacing: 24) {
                LogPreviewListPane(
                    logs: logs,
                    selectedPath: $selectedPath
                )
                .frame(width: 260)

                if let selectedLog {
                    LogPreviewDetailView(log: selectedLog, searchText: $logSearchText)
                } else {
                    ContentUnavailableView("暂无日志", systemImage: "doc.text.magnifyingglass", description: Text("对应日志目录中没有可预览的日志文件。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(20)
        .frame(width: 880, height: 600)
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
    @Binding var searchText: String

    private var logLines: [(Int, String)] {
        log.content
            .components(separatedBy: .newlines)
            .enumerated()
            .map { ($0 + 1, $1) }
    }

    private var filteredLines: [(Int, String)] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return logLines
        }
        return logLines.filter { $0.1.lowercased().contains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(log.fileName)
                        .font(.system(size: 18, weight: .bold))
                        .lineLimit(1)
                    HStack(spacing: 12) {
                        Text(AppDateFormatter.runTimestamp.string(from: log.modifiedAt))
                        Text(ByteFormatter.string(from: log.sizeBytes))
                        if log.isTruncated {
                            Text("仅显示尾部")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // 搜索输入框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("过滤日志行 (如: error, fail)", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .frame(width: 220)
            }
            
            DetailField(title: "完整路径", value: log.path, monospaced: true)
                .font(.caption2)
            
            if log.content.isEmpty {
                Text("日志文件为空。")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else if filteredLines.isEmpty {
                ContentUnavailableView(
                    "无匹配的日志行",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("未找到包含关键字 [\(searchText)] 的日志行。")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(filteredLines, id: \.0) { lineNumber, content in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(lineNumber)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Color.secondary.opacity(0.5))
                                    .frame(width: 32, alignment: .trailing)
                                
                                Text(content)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.top, 14)
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
