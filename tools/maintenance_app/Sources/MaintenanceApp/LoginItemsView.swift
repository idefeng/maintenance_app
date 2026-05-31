import SwiftUI
import MaintenanceCore

public struct LoginItemsView: View {
    let report: MaintenanceReport?
    
    @State private var searchText = ""
    @State private var selectedScope = LoginItemScope.all
    @State private var selectedItem: LoginItem?
    @State private var expandedDuplicates: Set<String> = []

    public init(report: MaintenanceReport?) {
        self.report = report
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let loginItems = report?.loginItems {
                let filteredItems = LoginItemFilter(
                    searchText: searchText,
                    category: selectedScope.category,
                    duplicateOnly: selectedScope.duplicateOnly
                ).apply(to: loginItems)

                MetricGrid(metrics: [
                    ("自启总项数", "\(loginItems.summary.itemCount)", "list.bullet.rectangle"),
                    ("Launch plist", "\(loginItems.summary.launchPlistCount)", "doc.plaintext"),
                    ("自有自动化", "\(loginItems.summary.ownAutomationCount)", "terminal"),
                    ("待复核项", "\(loginItems.summary.manualReviewCount)", "eye.trianglebadge.exclamationmark"),
                    ("筛选明细", "\(filteredItems.count)", "line.3.horizontal.decrease.circle")
                ])
                .padding(.bottom, 4)

                LoginItemFilterBar(searchText: $searchText, selectedScope: $selectedScope)
                
                // 重复自启项手风琴折叠面板
                SectionTitle("重名自启服务项目（重点复核）")
                if loginItems.duplicateDisplayNames.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("优秀！当前未在系统后台检测到重名自启垃圾项。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                } else {
                    VStack(spacing: 6) {
                        ForEach(loginItems.duplicateDisplayNames) { duplicate in
                            let isExpanded = expandedDuplicates.contains(duplicate.displayName)
                            VStack(alignment: .leading, spacing: 0) {
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        if isExpanded {
                                            expandedDuplicates.remove(duplicate.displayName)
                                        } else {
                                            expandedDuplicates.insert(duplicate.displayName)
                                        }
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "app.dashed")
                                            .font(.headline)
                                            .foregroundStyle(MaintenanceDesign.accent)
                                        Text(duplicate.displayName)
                                            .font(.body.bold())
                                        Spacer()
                                        Text("\(duplicate.count) 个进程重名")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                
                                if isExpanded {
                                    Divider().padding(.horizontal, 16)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("检测到以下独立后台注册项使用了相同的显示名称，可能造成混淆：")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(.bottom, 2)
                                        
                                        ForEach(duplicate.identifiers.indices, id: \.self) { idx in
                                            let identifier = duplicate.identifiers[idx]
                                            HStack(spacing: 6) {
                                                Image(systemName: "link.badge.plus")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                Text(identifier ?? "未知服务 Bundle ID")
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .textSelection(.enabled)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.primary.opacity(0.02))
                                }
                            }
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                
                SectionTitle("登录项与常驻后台明细")
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        "无符合条件的登录项",
                        systemImage: "magnifyingglass",
                        description: Text("没有搜索到匹配当前筛选条件的后台服务项目。")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .glassCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            HStack(alignment: .center, spacing: 12) {
                                LoginItemIconView(item: item)
                                    .frame(width: 30, height: 30)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(alignment: .center, spacing: 8) {
                                        Text(item.displayName)
                                            .font(.body.bold())
                                            .lineLimit(1)
                                            .textSelection(.enabled)
                                        
                                        // 极其精致的色彩分类标签
                                        TagBadgeView(category: item.category)
                                    }
                                    
                                    let subtitle = item.urlPath ?? item.executablePath ?? item.identifier ?? ""
                                    if !subtitle.isEmpty {
                                        Text(subtitle)
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                    }
                                }
                                
                                Spacer(minLength: 12)
                                
                                // 建议动作视觉优化
                                ActionBadgeView(action: item.suggestedAction)
                                
                                Button("详情") {
                                    selectedItem = item
                                }
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(index % 2 == 0 ? Color.primary.opacity(0.015) : Color.clear)
                            
                            if index < filteredItems.count - 1 {
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    
                    if filteredItems.count > 60 {
                        Text("当前列出项目较多，可在上方输入框中键入开发者名字或 identifier 缩窄范围。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)
                            .padding(.top, 4)
                    }
                }
                
                SectionTitle("底层 Launch plist 配置清单")
                VStack(spacing: 0) {
                    ForEach(Array(loginItems.launchPlists.prefix(20).enumerated()), id: \.element.id) { index, plist in
                        RowView(
                            title: plist.label ?? plist.path.split(separator: "/").last.map(String.init) ?? plist.path,
                            subtitle: plist.path,
                            trailing: plist.rootLevel ? "系统守护进程 (Daemon)" : "用户代理进程 (Agent)"
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(index % 2 == 0 ? Color.primary.opacity(0.015) : Color.clear)
                        
                        if index < min(loginItems.launchPlists.count, 20) - 1 {
                            Divider().padding(.horizontal, 16)
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                EmptyReportView()
            }
        }
        .sheet(item: $selectedItem) { item in
            LoginItemDetailView(item: item)
        }
    }
}

// MARK: - TagBadgeView
struct TagBadgeView: View {
    let category: String
    
    var body: some View {
        let label = LoginItemLabels.category(category)
        let color: Color = {
            switch category {
            case "own_automation": return .green
            case "possible_remnant": return .red
            case "manual_review": return .orange
            case "system_background_item": return .indigo
            default: return .secondary
            }
        }()
        
        return Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

// MARK: - ActionBadgeView
struct ActionBadgeView: View {
    let action: String
    
    var body: some View {
        let label = LoginItemLabels.action(action)
        let color: Color = {
            switch action {
            case "keep": return .green
            case "review", "manual_review": return .orange
            case "remove_if_unused": return .red
            default: return .secondary
            }
        }()
        
        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.04)))
        .padding(.trailing, 4)
    }
}
