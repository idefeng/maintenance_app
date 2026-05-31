import SwiftUI
import MaintenanceCore

struct OmniMaintenanceSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // 头部栏
            headerView
            
            Divider()

            // 维护步骤进展列表
            stepsListView
                .padding(.vertical, 4)

            // 完成总结面板
            if let summary = viewModel.omniSummary {
                summaryPanelView(summary)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                runningLoaderView
            }
        }
        .padding(24)
        .frame(width: 580)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.omniSummary != nil)
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles.system")
                .font(.title)
                .foregroundStyle(
                    LinearGradient(
                        colors: [MaintenanceDesign.accent, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("一键全景智能深度净化")
                    .font(.title2.bold())
                Text("全自动化扫描系统高速垃圾、应用程序卸载残留并全面审计系统自启代理")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var stepsListView: some View {
        VStack(spacing: 12) {
            ForEach(viewModel.omniSteps) { step in
                HStack(alignment: .center, spacing: 14) {
                    // 状态指示呼吸灯
                    PulseGlowIndicator(color: stepColor(step.status), active: step.status == .running)
                        .frame(width: 16, height: 16)
                    
                    Image(systemName: step.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(step.status == .completed ? MaintenanceDesign.accent : .secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(step.status == .completed ? MaintenanceDesign.accent.opacity(0.1) : Color.primary.opacity(0.04)))
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.name)
                            .font(.callout.bold())
                            .foregroundStyle(step.status == .pending ? .secondary : .primary)
                        Text(step.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // 进度文字
                    Text(step.status.rawValue)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(stepTextColor(step.status))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(stepBgColor(step.status)))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var runningLoaderView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("智能深度优化正在飞速处理中，请勿关闭电脑...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private func summaryPanelView(_ summary: OmniMaintenanceSummary) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // 空间释放卡片
                summaryGridItem(
                    value: ByteFormatter.string(from: summary.bytesFreed),
                    label: "释放磁盘缓存",
                    icon: "arrow.down.circle",
                    tint: .green
                )
                
                // 残留清理卡片
                summaryGridItem(
                    value: "\(summary.leftoversCleaned) 项",
                    label: "粉碎卸载残留",
                    icon: "trash.circle",
                    tint: .blue
                )
                
                // 自启审计卡片
                summaryGridItem(
                    value: "\(summary.itemsChecked) 组",
                    label: "就绪自启代理",
                    icon: "checkmark.shield",
                    tint: .purple
                )
            }
            
            Button {
                viewModel.isShowingOmniProgress = false
                dismiss()
            } label: {
                Text("深度净化圆满告捷")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .tint(MaintenanceDesign.accent)
            .controlSize(.large)
        }
        .padding(.top, 6)
    }

    private func summaryGridItem(value: String, label: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint.opacity(0.1)))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Color Match Helpers
    private func stepColor(_ status: OmniStepStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .running: return MaintenanceDesign.accent
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func stepTextColor(_ status: OmniStepStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .running: return MaintenanceDesign.accent
        case .completed: return .green
        case .failed: return .red
        }
    }

    private func stepBgColor(_ status: OmniStepStatus) -> Color {
        switch status {
        case .pending: return Color.primary.opacity(0.04)
        case .running: return MaintenanceDesign.accent.opacity(0.12)
        case .completed: return Color.green.opacity(0.12)
        case .failed: return Color.red.opacity(0.12)
        }
    }
}
