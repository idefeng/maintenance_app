import SwiftUI
import MaintenanceCore

public struct OverviewView: View {
    let report: MaintenanceReport?
    let healthSummary: MaintenanceHealthSummary
    let launchAgents: [LaunchAgentState]
    let onOpenPlist: (LaunchAgentState) -> Void
    let onOpenLogs: (LaunchAgentState) -> Void
    let onPreviewLogs: (LaunchAgentState) -> Void
    let onReinstall: (LaunchAgentState) -> Void
    let onOmniMaintenance: () -> Void

    public init(
        report: MaintenanceReport?,
        healthSummary: MaintenanceHealthSummary,
        launchAgents: [LaunchAgentState],
        onOpenPlist: @escaping (LaunchAgentState) -> Void,
        onOpenLogs: @escaping (LaunchAgentState) -> Void,
        onPreviewLogs: @escaping (LaunchAgentState) -> Void,
        onReinstall: @escaping (LaunchAgentState) -> Void,
        onOmniMaintenance: @escaping () -> Void
    ) {
        self.report = report
        self.healthSummary = healthSummary
        self.launchAgents = launchAgents
        self.onOpenPlist = onOpenPlist
        self.onOpenLogs = onOpenLogs
        self.onPreviewLogs = onPreviewLogs
        self.onReinstall = onReinstall
        self.onOmniMaintenance = onOmniMaintenance
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HealthSummaryPanel(summary: healthSummary, onOmniMaintenance: onOmniMaintenance)
                .glassCard()
                .hoverScale()
            
            if let report {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle("统计摘要")
                    MetricGrid(metrics: [
                        ("待清理项", "\(report.summary.planned)", "externaldrive"),
                        ("预计释放", ByteFormatter.string(from: report.summary.bytesPlanned), "arrow.down.circle"),
                        ("文件整理动作", "\(report.fileOrganizer?.summary.actionCount ?? 0)", "arrow.triangle.2.circlepath"),
                        ("登录项复核", "\(report.loginItems?.summary.manualReviewCount ?? 0)", "key.viewfinder")
                    ])
                    
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("最近报告生成于：\(report.generatedAt)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
            } else {
                ContentUnavailableView(
                    "暂无运行报告",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("点击右上角“扫描”生成第一份本机状态报告。")
                )
                .padding(.vertical, 20)
                .glassCard()
            }

            VStack(alignment: .leading, spacing: 12) {
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
            .padding(.top, 8)
        }
    }
}

// MARK: - HealthSummaryPanel
struct HealthSummaryPanel: View {
    let summary: MaintenanceHealthSummary
    let onOmniMaintenance: () -> Void

    // 根据问题数量与严重程度，动态计算出系统健康得分（100分为满分）
    private var healthScore: Int {
        let criticalCount = summary.count(for: .critical)
        let warningCount = summary.count(for: .warning)
        let infoCount = summary.count(for: .info)
        let deduction = (criticalCount * 25) + (warningCount * 10) + (infoCount * 3)
        return max(100 - deduction, 0)
    }

    private var scoreColor: Color {
        if healthScore >= 90 {
            return .green
        } else if healthScore >= 70 {
            return .orange
        } else {
            return .red
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 32) {
            // 左侧：优雅的系统得分健康进度环
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 10)
                    .frame(width: 108, height: 108)
                
                Circle()
                    .trim(from: 0, to: CGFloat(healthScore) / 100.0)
                    .stroke(
                        AngularGradient(
                            colors: [scoreColor, scoreColor.opacity(0.7), scoreColor],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 108, height: 108)
                    .animation(.easeOut(duration: 0.8), value: healthScore)
                
                VStack(spacing: 2) {
                    Text("\(healthScore)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("系统评分")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 8)
            
            // 右侧：异常提醒详情
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("安全检测中心")
                        .font(.title3.bold())
                    HealthSeverityBadge(severity: summary.highestSeverity)
                    Spacer()
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
                    Text("极好！本机当前没有发现维护隐患，请继续保持良好的使用习惯。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.issues.prefix(3)) { issue in
                            HealthIssueRow(issue: issue)
                        }
                        if summary.issues.count > 3 {
                            Text("另有 \(summary.issues.count - 3) 条维护建议已收拢，可在具体菜单页分项查看。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 32)
                                .padding(.top, 2)
                        }
                    }
                }
                
                Button {
                    onOmniMaintenance()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("一键全景智能深度净化")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .tint(MaintenanceDesign.accent)
                .controlSize(.small)
                .hoverScale()
                .padding(.top, 4)
            }
        }
    }
}
