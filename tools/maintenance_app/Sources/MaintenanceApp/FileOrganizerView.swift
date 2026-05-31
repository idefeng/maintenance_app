import SwiftUI
import MaintenanceCore

public struct FileOrganizerView: View {
    let report: MaintenanceReport?
    let configuredSources: [FileOrganizerConfiguredSource]
    let onAddSource: () -> Void
    let onRemoveSource: (FileOrganizerConfiguredSource) -> Void

    public init(
        report: MaintenanceReport?,
        configuredSources: [FileOrganizerConfiguredSource],
        onAddSource: @escaping () -> Void,
        onRemoveSource: @escaping (FileOrganizerConfiguredSource) -> Void
    ) {
        self.report = report
        self.configuredSources = configuredSources
        self.onAddSource = onAddSource
        self.onRemoveSource = onRemoveSource
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 用户路径配置面板
            FileOrganizerSourceConfigView(
                configuredSources: configuredSources,
                onAddSource: onAddSource,
                onRemoveSource: onRemoveSource
            )
            .glassCard()
            .hoverScale()
            
            if let organizer = report?.fileOrganizer {
                MetricGrid(metrics: [
                    ("来源目录数", "\(organizer.summary.sourceCount)", "folder"),
                    ("已执行整理", "\(organizer.summary.actionCount)", "arrow.triangle.2.circlepath"),
                    ("待人工处理目录", "\(organizer.summary.pendingDirectoryCount)", "person.and.arrow.left.and.arrow.right"),
                    ("已跳过条目", "\(organizer.summary.skippedCount)", "forward.frame")
                ])
                .padding(.top, 4)
                
                ForEach(organizer.sources) { source in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(MaintenanceDesign.accent)
                            Text(source.source)
                                .font(.headline)
                        }
                        
                        Text("整理活动明细（共命中动作 \(source.actionCount) 项，待人工分类 \(source.pendingDirectoryCount) 项，跳过 \(source.skippedCount) 项）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 2)
                        
                        VStack(spacing: 0) {
                            // 整理文件流水展示
                            if !source.actions.isEmpty {
                                ForEach(Array(source.actions.enumerated()), id: \.element.id) { idx, action in
                                    RowView(
                                        title: action.source,
                                        subtitle: "移动至：\(action.destination)",
                                        trailing: action.status
                                    )
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(idx % 2 == 0 ? Color.primary.opacity(0.015) : Color.clear)
                                    
                                    if idx < source.actions.count - 1 || !source.pendingDirectories.isEmpty {
                                        Divider().padding(.horizontal, 16)
                                    }
                                }
                            }
                            
                            // 待分类目录提示显示
                            if !source.pendingDirectories.isEmpty {
                                ForEach(Array(source.pendingDirectories.enumerated()), id: \.element.id) { idx, directory in
                                    HStack(spacing: 12) {
                                        Image(systemName: "questionmark.folder.fill")
                                            .foregroundStyle(.orange)
                                            .font(.title3)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(directory.directory)
                                                .font(.body)
                                                .textSelection(.enabled)
                                            Text("新检测到的目录：由于无法精确匹配归档规则，已保留在原位，等待人工重命名或建档。")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color.orange.opacity(0.04))
                                    
                                    if idx < source.pendingDirectories.count - 1 {
                                        Divider().padding(.horizontal, 16)
                                    }
                                }
                            }
                        }
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(.vertical, 6)
                }
            } else {
                EmptyReportView()
            }
        }
    }
}

// MARK: - FileOrganizerSourceConfigView
struct FileOrganizerSourceConfigView: View {
    let configuredSources: [FileOrganizerConfiguredSource]
    let onAddSource: () -> Void
    let onRemoveSource: (FileOrganizerConfiguredSource) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline)
                            .foregroundStyle(MaintenanceDesign.accent)
                        Text("自定义文件监听来源")
                            .font(.headline)
                    }
                    Text("默认自动匹配 Desktop、Downloads、Documents 根目录，您可以在下方添加额外的监听路径。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onAddSource) {
                    Label("添加监听路径", systemImage: "plus.folder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            if configuredSources.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("未添加额外路径。当前仅使用默认策略。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(configuredSources) { source in
                        HStack(spacing: 12) {
                            Image(systemName: "folder.badge.plus")
                                .font(.title3)
                                .foregroundStyle(MaintenanceDesign.accent)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.path)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                Text(source.recursive ? "已启用深度递归整理" : "仅对首层结构执行归档")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer(minLength: 12)
                            
                            Button(action: {
                                onRemoveSource(source)
                            }) {
                                Text("移除")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }
}
