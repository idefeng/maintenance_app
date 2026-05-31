import SwiftUI
import MaintenanceCore

struct AppCleanupView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedMatch: AppCleanupMatch?
    @State private var statusFilter = FilterConstants.allValue
    @State private var categoryFilter = FilterConstants.allValue

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 搜索与清理主面板
            searchAndControlPanel
                .glassCard()
                .hoverScale()
                .padding(.bottom, 4)

            if let report = viewModel.appCleanupReport {
                let categories = FilterConstants.sortedValues(report.matches.map(\.category))
                let filteredMatches = report.matches.filter { match in
                    let categoryMatch = categoryFilter == FilterConstants.allValue || match.category == categoryFilter
                    return categoryMatch
                }

                // 统计面板
                MetricGrid(metrics: [
                    ("匹配项总数", "\(report.matchCount)", "magnifyingglass.circle"),
                    ("可安全清理项", "\(report.actionSummary.safeDelete)", "trash.circle"),
                    ("建议保留项", "\(report.actionSummary.reportOnly)", "exclamationmark.shield"),
                    ("已删除残留", "\(report.actionSummary.deleted)", "checkmark.circle"),
                    ("当前筛选显示", "\(filteredMatches.count)", "line.3.horizontal.decrease.circle")
                ])
                .padding(.bottom, 4)

                // 筛选栏
                HStack(spacing: 12) {
                    Picker("残留类别", selection: $categoryFilter) {
                        Text("全部").tag(FilterConstants.allValue)
                        ForEach(categories, id: \.self) { category in
                            Text(categoryLabel(category)).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                    .controlSize(.small)
                }

                SectionTitle("应用残留匹配项清单")

                if report.matches.isEmpty {
                    ContentUnavailableView(
                        "未发现该应用的残留文件",
                        systemImage: "checkmark.circle.fill",
                        description: Text("很好，当前扫描未发现与该应用匹配的残留文件或相关配置。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .glassCard()
                } else if filteredMatches.isEmpty {
                    ContentUnavailableView(
                        "无符合条件的残留项",
                        systemImage: "questionmark.folder.dashed",
                        description: Text("尝试调整类别筛选选项。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .glassCard()
                } else {
                    let lowRisk = filteredMatches.filter { $0.riskLevel == "low" || $0.plannedAction == "safe_delete" }
                    let highRisk = filteredMatches.filter { $0.riskLevel == "high" || $0.plannedAction == "report_only" }

                    VStack(alignment: .leading, spacing: 16) {
                        if !lowRisk.isEmpty {
                            AppCleanupRiskGroupView(
                                title: "低风险残留（多为缓存、系统日志等，可放心清理）",
                                color: .green,
                                matches: lowRisk
                            ) { match in
                                selectedMatch = match
                            }
                        }

                        if !highRisk.isEmpty {
                            AppCleanupRiskGroupView(
                                title: "建议保留或人工复核（涉及应用核心数据、偏好设置，建议谨慎）",
                                color: .orange,
                                matches: highRisk
                            ) { match in
                                selectedMatch = match
                            }
                        }
                    }
                }
            } else {
                initialEmptyState
            }
        }
        .sheet(item: $selectedMatch) { match in
            AppCleanupMatchDetailView(match: match)
        }
    }

    private var searchAndControlPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("应用残留深度清理")
                .font(.headline)
            
            Text("输入已卸载或准备卸载的 macOS 应用程序名称，我们将深度扫描其分布在 Application Support、Caches、Preferences、Logs 及 LaunchAgents 等目录下的孤立残留文件，协助您实现一键彻底净空。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
            
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("输入应用名称（例如: WeChat, Docker, Xcode）", text: $viewModel.appCleanupSearchText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            viewModel.runAppCleanupScan(appName: viewModel.appCleanupSearchText)
                        }
                    if !viewModel.appCleanupSearchText.isEmpty {
                        Button {
                            viewModel.appCleanupSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                
                if viewModel.isRunning && viewModel.statusMessage.contains("扫描") {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("扫描中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                } else {
                    Button("开始扫描") {
                        viewModel.runAppCleanupScan(appName: viewModel.appCleanupSearchText)
                    }
                    .disabled(viewModel.isRunning || viewModel.appCleanupSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                
                if viewModel.isRunning && viewModel.statusMessage.contains("清理") {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("清理中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 6)
                } else {
                    Button("一键安全清理") {
                        viewModel.runAppCleanupApply(appName: viewModel.appCleanupSearchText)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(viewModel.isRunning || viewModel.appCleanupReport == nil || viewModel.appCleanupReport?.actionSummary.safeDelete == 0)
                }
            }
            .controlSize(.small)
            
            HStack(spacing: 8) {
                Text("快速选择:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                ForEach(["Xcode", "Docker", "WeChat", "VS Code", "Chrome"], id: \.self) { app in
                    Button {
                        viewModel.appCleanupSearchText = app
                        viewModel.runAppCleanupScan(appName: app)
                    } label: {
                        Text(app)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .hoverScale()
                }
            }
            .padding(.top, 4)
        }
    }

    private var initialEmptyState: some View {
        ContentUnavailableView(
            "查找应用程序残留",
            systemImage: "trash.fill",
            description: Text("在上方输入应用名称（如 Docker 或 WeChat）并点击“开始扫描”来探测系统中的遗留文件。")
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glassCard()
    }

    private func categoryLabel(_ value: String) -> String {
        switch value {
        case "user_applications": return "应用包 (Applications)"
        case "application_support", "app_support": return "应用数据支持 (Application Support)"
        case "caches": return "缓存目录 (Caches)"
        case "http_storages": return "网络存储 (HTTPStorages)"
        case "logs": return "日志文件 (Logs)"
        case "preferences": return "偏好设置 (Preferences)"
        case "saved_application_state": return "保存的应用状态 (Saved State)"
        case "launch_agents": return "开机自启代理 (LaunchAgents)"
        case "webkit": return "网页核心缓存 (WebKit)"
        case "containers": return "沙盒容器 (Containers)"
        case "group_containers": return "应用共享沙盒 (Group Containers)"
        default: return value
        }
    }
}

// MARK: - AppCleanupRiskGroupView
struct AppCleanupRiskGroupView: View {
    let title: String
    let color: Color
    let matches: [AppCleanupMatch]
    let onDetails: (AppCleanupMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                PulseGlowIndicator(color: color, active: false)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                    ActionRowView(
                        title: match.path,
                        subtitle: "\(categoryText(match.category)) · \(reasonText(match.matchReason))",
                        trailing: "\(statusText(match.actionStatus)) · \(match.pathType == "directory" ? "文件夹" : "文件")",
                        actionTitle: "详情",
                        action: {
                            onDetails(match)
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(index % 2 == 0 ? Color.primary.opacity(0.015) : Color.clear)

                    if index < matches.count - 1 {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func categoryText(_ category: String) -> String {
        switch category {
        case "caches": return "缓存"
        case "logs": return "日志"
        case "preferences": return "偏好"
        case "application_support", "app_support": return "应用数据支持"
        case "launch_agents": return "自启项"
        case "saved_application_state": return "应用临时状态"
        case "containers": return "独立沙盒"
        case "group_containers": return "共享沙盒"
        default: return category
        }
    }

    private func reasonText(_ reason: String) -> String {
        switch reason {
        case "bundle_id_match": return "包名标识符合"
        case "name_match": return "路径名模糊命中"
        default: return reason
        }
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "pending": return "待处理"
        case "deleted": return "已删除"
        case "reported": return "仅报告"
        case "failed": return "失败"
        default: return status
        }
    }
}

// MARK: - AppCleanupMatchDetailView
struct AppCleanupMatchDetailView: View {
    let match: AppCleanupMatch

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("应用残留项详情")
                    .font(.title2.bold())
                
                DetailField(title: "完整路径", value: match.path, monospaced: true)
                DetailField(title: "文件名", value: match.name)
                DetailField(title: "所在分类", value: match.category)
                DetailField(title: "路径类型", value: match.pathType == "directory" ? "文件夹 (Directory)" : "普通文件 (File)")
                DetailField(title: "匹配原因", value: match.matchReason == "bundle_id_match" ? "包标识码匹配 (Bundle ID Match)" : "应用名称关键字模糊匹配")
                DetailField(title: "风险等级", value: match.riskLevel == "low" ? "低风险 (安全清除)" : "高风险 (建议保留/复核)")
                DetailField(title: "清理规划", value: match.plannedAction == "safe_delete" ? "计划安全删除 (Safe Delete)" : "仅报告/需人工处理 (Report Only)")
                DetailField(title: "执行状态", value: statusLabel(match.actionStatus))
                
                if let error = match.actionError, !error.isEmpty {
                    DetailField(title: "执行失败详情", value: error)
                        .foregroundStyle(.red)
                }
            }
            .padding(24)
            .frame(width: 580, alignment: .leading)
        }
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "pending": return "待执行扫描/清理"
        case "deleted": return "已成功安全删除"
        case "reported": return "仅记录报告，未执行物理删除"
        case "failed": return "清理执行失败"
        default: return status
        }
    }
}
