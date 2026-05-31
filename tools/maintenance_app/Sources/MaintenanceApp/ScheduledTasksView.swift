import SwiftUI
import MaintenanceCore

public struct ScheduledTasksView: View {
    let launchAgents: [LaunchAgentState]
    var showsManagementActions: Bool
    let onOpenPlist: (LaunchAgentState) -> Void
    let onOpenLogs: (LaunchAgentState) -> Void
    let onPreviewLogs: (LaunchAgentState) -> Void
    let onReinstall: (LaunchAgentState) -> Void

    public init(
        launchAgents: [LaunchAgentState],
        showsManagementActions: Bool = true,
        onOpenPlist: @escaping (LaunchAgentState) -> Void,
        onOpenLogs: @escaping (LaunchAgentState) -> Void,
        onPreviewLogs: @escaping (LaunchAgentState) -> Void,
        onReinstall: @escaping (LaunchAgentState) -> Void
    ) {
        self.launchAgents = launchAgents
        self.showsManagementActions = showsManagementActions
        self.onOpenPlist = onOpenPlist
        self.onOpenLogs = onOpenLogs
        self.onPreviewLogs = onPreviewLogs
        self.onReinstall = onReinstall
    }

    public var body: some View {
        VStack(spacing: 8) {
            if launchAgents.isEmpty {
                ContentUnavailableView(
                    "暂无本地自动化任务",
                    systemImage: "clock.badge.exclamationmark",
                    description: Text("未检测到系统的后台自启定时服务。")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(launchAgents.enumerated()), id: \.element.id) { index, task in
                        ScheduledTaskRow(
                            task: task,
                            showsManagementActions: showsManagementActions,
                            onOpenPlist: onOpenPlist,
                            onOpenLogs: onOpenLogs,
                            onPreviewLogs: onPreviewLogs,
                            onReinstall: onReinstall
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(index % 2 == 0 ? Color.primary.opacity(0.015) : Color.clear)
                        
                        if index < launchAgents.count - 1 {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

// MARK: - ScheduledTaskRow
struct ScheduledTaskRow: View {
    let task: LaunchAgentState
    let showsManagementActions: Bool
    let onOpenPlist: (LaunchAgentState) -> Void
    let onOpenLogs: (LaunchAgentState) -> Void
    let onPreviewLogs: (LaunchAgentState) -> Void
    let onReinstall: (LaunchAgentState) -> Void

    private var statusColor: Color {
        if !task.installed {
            return .secondary
        }
        if task.commandDescription == "未设置" {
            return .red
        }
        return .green
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // 呼吸状态指示灯（翡翠绿=运行中/正常，置灰=未安装，红色=缺少指令配置）
            PulseGlowIndicator(color: statusColor, active: task.installed)
                .frame(width: 16, height: 16)
            
            ScheduledTaskIcon(label: task.label)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(task.label)
                    .font(.body.bold())
                    .lineLimit(1)
                    .textSelection(.enabled)
                Text(task.plistPath)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            
            Spacer(minLength: 16)
            
            VStack(alignment: .trailing, spacing: 3) {
                Text(task.installed ? task.scheduleDescription : "未安装定时任务")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(task.installed ? .primary : .secondary)
                
                Text(task.installed ? "进程就绪" : "等待安装")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .trailing)
            .padding(.trailing, 4)
            
            HStack(spacing: 6) {
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
                    .buttonStyle(.borderedProminent)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(minHeight: MaintenanceDesign.rowMinHeight)
    }
}
