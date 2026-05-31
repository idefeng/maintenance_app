import SwiftUI
import MaintenanceCore

public struct DiskCleanupView: View {
    let report: MaintenanceReport?
    let diskUsage: DiskUsageSnapshot?
    
    @State private var searchText = ""
    @State private var statusFilter = FilterConstants.allValue
    @State private var categoryFilter = FilterConstants.allValue
    @State private var selectedCandidate: CleanupCandidate?

    public init(report: MaintenanceReport?, diskUsage: DiskUsageSnapshot?) {
        self.report = report
        self.diskUsage = diskUsage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let report {
                let statuses = FilterConstants.sortedValues(report.candidates.map(\.status))
                let categories = FilterConstants.sortedValues(report.candidates.map(\.category))
                let filteredCandidates = CleanupCandidateFilter(
                    searchText: searchText,
                    status: FilterConstants.filterValue(statusFilter),
                    category: FilterConstants.filterValue(categoryFilter)
                ).apply(to: report.candidates)

                MetricGrid(metrics: [
                    ("计划删除", "\(report.summary.planned)", "plus.circle"),
                    ("已释放空间", ByteFormatter.string(from: report.summary.bytesDeleted), "checkmark.circle"),
                    ("跳过项", "\(report.summary.skipped)", "exclamationmark.arrow.triangle.2.circlepath"),
                    ("执行失败", "\(report.summary.failed)", "xmark.octagon"),
                    ("匹配当前筛选", "\(filteredCandidates.count)", "line.3.horizontal.decrease.circle")
                ])
                .padding(.bottom, 4)

                FilterBar(
                    searchText: $searchText,
                    searchPrompt: "输入文件名、缓存类别或删除原因进行过滤...",
                    filters: [
                        FilterMenu(
                            title: "执行状态",
                            selection: $statusFilter,
                            options: statuses,
                            label: DiskCleanupLabels.status
                        ),
                        FilterMenu(
                            title: "候选项类别",
                            selection: $categoryFilter,
                            options: categories,
                            label: { $0 }
                        )
                    ]
                )
                
                DiskUsagePanel(snapshot: diskUsage)
                    .glassCard()
                    .hoverScale()
                    .padding(.vertical, 4)

                SectionTitle("清理候选项清单")
                
                if report.candidates.isEmpty {
                    ContentUnavailableView(
                        "没有扫描出可清理空间",
                        systemImage: "checkmark.circle.fill",
                        description: Text("很好，当前没有发现大文件残留或无用的缓存堆积。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .glassCard()
                } else if filteredCandidates.isEmpty {
                    ContentUnavailableView(
                        "无符合条件的候选项",
                        systemImage: "questionmark.folder.dashed",
                        description: Text("尝试清空搜索框或调整状态/类别筛选选项。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .glassCard()
                } else {
                    // 按照风险等级进行人性化分组展示，使用户对操作拥有最高掌控度
                    let lowRisk = filteredCandidates.filter { $0.riskLevel == "low" }
                    let mediumRisk = filteredCandidates.filter { $0.riskLevel == "medium" }
                    let highRisk = filteredCandidates.filter { $0.riskLevel == "high" }
                    
                    VStack(alignment: .leading, spacing: 16) {
                        if !lowRisk.isEmpty {
                            RiskGroupView(title: "低风险清理项（主要为重建缓存，可放心清理）", color: .green, candidates: lowRisk) { candidate in
                                selectedCandidate = candidate
                            }
                        }
                        
                        if !mediumRisk.isEmpty {
                            RiskGroupView(title: "中风险清理项（建议双击查看，不用时建议清理）", color: .orange, candidates: mediumRisk) { candidate in
                                selectedCandidate = candidate
                            }
                        }
                        
                        if !highRisk.isEmpty {
                            RiskGroupView(title: "高风险清理项（涉及应用重要资源，谨慎清理）", color: .red, candidates: highRisk) { candidate in
                                selectedCandidate = candidate
                            }
                        }
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

// MARK: - RiskGroupView
struct RiskGroupView: View {
    let title: String
    let color: Color
    let candidates: [CleanupCandidate]
    let onDetails: (CleanupCandidate) -> Void
    
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
                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    ActionRowView(
                        title: candidate.path,
                        subtitle: "\(candidate.category) · \(candidate.reason)",
                        trailing: "\(DiskCleanupLabels.status(candidate.status)) · \(ByteFormatter.string(from: candidate.sizeBytes))",
                        actionTitle: "详情",
                        action: {
                            onDetails(candidate)
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(index % 2 == 0 ? Color.primary.opacity(0.015) : Color.clear)
                    
                    if index < candidates.count - 1 {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - DiskUsagePanel
struct DiskUsagePanel: View {
    let snapshot: DiskUsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("系统主磁盘使用率")
            if let snapshot {
                HStack(alignment: .center, spacing: 32) {
                    DiskUsageRingChart(fraction: snapshot.usedFraction)
                        .frame(width: 108, height: 108)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "internaldrive")
                                .font(.headline)
                                .foregroundStyle(MaintenanceDesign.accent)
                            Text(snapshot.volumeName)
                                .font(.headline)
                        }
                        
                        Text(snapshot.mountPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        
                        HStack(spacing: 24) {
                            DiskUsageValue(title: "总容量", bytes: snapshot.totalBytes, systemImage: "info.circle")
                            DiskUsageValue(title: "已使用", bytes: snapshot.usedBytes, systemImage: "chart.pie")
                            DiskUsageValue(title: "可使用空间", bytes: snapshot.availableBytes, systemImage: "checkmark.circle")
                        }
                        .padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            } else {
                Text("暂时无法读取本地磁盘卷的详细容量快照。")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - DiskUsageRingChart
struct DiskUsageRingChart: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.12), lineWidth: 10)
            
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(
                    LinearGradient(
                        colors: [MaintenanceDesign.accent, MaintenanceDesign.accent.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.8), value: fraction)
            
            VStack(spacing: 2) {
                Image(systemName: "harddrive.stack.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(MaintenanceDesign.accent.opacity(0.8))
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.title3.bold())
            }
        }
        .accessibilityLabel("磁盘已使用 \(Int((fraction * 100).rounded()))%")
    }
}

// MARK: - DiskUsageValue
struct DiskUsageValue: View {
    let title: String
    let bytes: Int64
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(ByteFormatter.string(from: bytes))
                .font(.callout.weight(.bold))
        }
    }
}
