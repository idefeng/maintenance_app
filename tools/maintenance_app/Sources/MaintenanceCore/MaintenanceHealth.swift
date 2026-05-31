import Foundation

public enum MaintenanceHealthSeverity: Int, Comparable, CaseIterable, Sendable {
    case ok = 0
    case info = 1
    case warning = 2
    case critical = 3

    public static func < (lhs: MaintenanceHealthSeverity, rhs: MaintenanceHealthSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .ok:
            return "正常"
        case .info:
            return "建议"
        case .warning:
            return "关注"
        case .critical:
            return "处理"
        }
    }
}

public struct MaintenanceHealthIssue: Equatable, Identifiable, Sendable {
    public let id: String
    public let severity: MaintenanceHealthSeverity
    public let title: String
    public let message: String
    public let recommendedAction: String
    public let affectedPath: String?
    public let priority: Int

    public init(
        id: String,
        severity: MaintenanceHealthSeverity,
        title: String,
        message: String,
        recommendedAction: String,
        affectedPath: String? = nil,
        priority: Int = 100
    ) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
        self.recommendedAction = recommendedAction
        self.affectedPath = affectedPath
        self.priority = priority
    }
}

public struct MaintenanceHealthSummary: Equatable, Sendable {
    public let issues: [MaintenanceHealthIssue]
    public let highestSeverity: MaintenanceHealthSeverity
    public let statusTitle: String
    public let statusDescription: String

    public init(issues: [MaintenanceHealthIssue]) {
        self.issues = issues.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        self.highestSeverity = self.issues.map(\.severity).max() ?? .ok
        self.statusTitle = Self.title(for: highestSeverity)
        self.statusDescription = Self.description(for: highestSeverity, issueCount: self.issues.count)
    }

    public func count(for severity: MaintenanceHealthSeverity) -> Int {
        issues.filter { $0.severity == severity }.count
    }

    private static func title(for severity: MaintenanceHealthSeverity) -> String {
        switch severity {
        case .ok:
            return "状态正常"
        case .info:
            return "有可执行建议"
        case .warning:
            return "需要关注"
        case .critical:
            return "需要处理"
        }
    }

    private static func description(for severity: MaintenanceHealthSeverity, issueCount: Int) -> String {
        switch severity {
        case .ok:
            return "当前没有发现需要处理的维护风险。"
        case .info:
            return "发现 \(issueCount) 条可选优化建议。"
        case .warning:
            return "发现 \(issueCount) 条维护提醒，建议在方便时处理。"
        case .critical:
            return "发现 \(issueCount) 条维护风险，建议优先处理严重项。"
        }
    }
}

public enum MaintenanceHealthAnalyzer {
    private static let bytesInGiB: Int64 = 1024 * 1024 * 1024
    // 报告超过两天未更新时提示用户重新扫描，避免基于过期数据做清理判断。
    private static let staleReportInterval: TimeInterval = 48 * 60 * 60

    // 汇总跨模块风险：磁盘、报告、登录项、文件整理路径和定时任务统一在总览展示。
    public static func analyze(
        report: MaintenanceReport?,
        diskUsage: DiskUsageSnapshot?,
        launchAgents: [LaunchAgentState],
        fileOrganizerSources: [FileOrganizerConfiguredSource],
        now: Date = Date(),
        fileManager: FileManager = .default
    ) -> MaintenanceHealthSummary {
        var issues: [MaintenanceHealthIssue] = []
        appendDiskUsageIssues(to: &issues, diskUsage: diskUsage)
        appendReportIssues(to: &issues, report: report, now: now)
        appendLaunchAgentIssues(to: &issues, launchAgents: launchAgents, now: now, fileManager: fileManager)
        appendFileOrganizerSourceIssues(to: &issues, sources: fileOrganizerSources, fileManager: fileManager)
        return MaintenanceHealthSummary(issues: issues)
    }

    // 低于 10GB 或使用率超过 90% 视为需要优先处理，20GB/85% 作为提前预警线。
    private static func appendDiskUsageIssues(to issues: inout [MaintenanceHealthIssue], diskUsage: DiskUsageSnapshot?) {
        guard let diskUsage else {
            return
        }

        let availableGiB = max(diskUsage.availableBytes / bytesInGiB, 0)
        if diskUsage.availableBytes < 10 * bytesInGiB || diskUsage.usedFraction >= 0.90 {
            issues.append(MaintenanceHealthIssue(
                id: "low-disk-space",
                severity: .critical,
                title: "磁盘空间紧张",
                message: "\(diskUsage.volumeName) 仅剩 \(availableGiB) GB，可用空间低于保守阈值。",
                recommendedAction: "先执行扫描，确认候选项后再执行保守维护。",
                affectedPath: diskUsage.mountPath,
                priority: 0
            ))
        } else if diskUsage.availableBytes < 20 * bytesInGiB || diskUsage.usedFraction >= 0.85 {
            issues.append(MaintenanceHealthIssue(
                id: "disk-space-warning",
                severity: .warning,
                title: "磁盘空间接近警戒线",
                message: "\(diskUsage.volumeName) 可用空间约 \(availableGiB) GB。",
                recommendedAction: "关注磁盘清理页的预计释放空间，避免继续积累缓存。",
                affectedPath: diskUsage.mountPath,
                priority: 10
            ))
        }
    }

    private static func appendReportIssues(to issues: inout [MaintenanceHealthIssue], report: MaintenanceReport?, now: Date) {
        guard let report else {
            issues.append(MaintenanceHealthIssue(
                id: "missing-maintenance-report",
                severity: .warning,
                title: "尚未生成维护报告",
                message: "应用还没有可读取的统一维护报告。",
                recommendedAction: "点击“扫描”生成第一份报告。",
                priority: 20
            ))
            return
        }

        if report.summary.failed > 0 {
            issues.append(MaintenanceHealthIssue(
                id: "disk-cleanup-failures",
                severity: .critical,
                title: "磁盘清理存在失败项",
                message: "最近报告中有 \(report.summary.failed) 个清理候选项执行失败。",
                recommendedAction: "打开运行详情或候选项详情查看 stderr 与失败路径。",
                priority: 5
            ))
        }

        if let generatedAt = ReportDateParser.date(from: report.generatedAt) {
            if now.timeIntervalSince(generatedAt) > staleReportInterval {
                issues.append(MaintenanceHealthIssue(
                    id: "stale-maintenance-report",
                    severity: .warning,
                    title: "维护报告已经过期",
                    message: "最近报告生成于 \(report.generatedAt)，已超过 48 小时。",
                    recommendedAction: "点击“刷新”确认报告存在，必要时重新扫描。",
                    priority: 30
                ))
            }
        } else {
            issues.append(MaintenanceHealthIssue(
                id: "unreadable-report-date",
                severity: .warning,
                title: "报告时间无法解析",
                message: "最近报告的 generated_at 字段为 \(report.generatedAt)。",
                recommendedAction: "重新执行扫描，生成新的统一维护报告。",
                priority: 31
            ))
        }

        if report.summary.bytesPlanned >= 5 * bytesInGiB {
            issues.append(MaintenanceHealthIssue(
                id: "large-releasable-space",
                severity: .info,
                title: "存在较大可释放空间",
                message: "预览报告显示可释放 \(ByteCountFormatter.string(fromByteCount: report.summary.bytesPlanned, countStyle: .file))。",
                recommendedAction: "确认候选项均为可重建内容后，可执行保守维护。",
                priority: 50
            ))
        }

        if let loginItems = report.loginItems {
            if loginItems.summary.possibleRemnantCount > 0 {
                issues.append(MaintenanceHealthIssue(
                    id: "login-item-remnants",
                    severity: .warning,
                    title: "存在疑似卸载残留登录项",
                    message: "报告识别到 \(loginItems.summary.possibleRemnantCount) 个疑似残留项。",
                    recommendedAction: "进入登录项页筛选“残留”，结合系统设置人工复核。",
                    priority: 40
                ))
            }
            if loginItems.summary.manualReviewCount >= 50 {
                issues.append(MaintenanceHealthIssue(
                    id: "many-login-items-need-review",
                    severity: .warning,
                    title: "登录项复核数量较多",
                    message: "当前有 \(loginItems.summary.manualReviewCount) 个登录项需要人工复核。",
                    recommendedAction: "优先处理重复显示名和不再使用的后台项目。",
                    priority: 41
                ))
            }
        }

        if let organizer = report.fileOrganizer, organizer.summary.pendingDirectoryCount > 0 {
            issues.append(MaintenanceHealthIssue(
                id: "file-organizer-pending-directories",
                severity: .warning,
                title: "文件整理仍有待处理目录",
                message: "最近报告记录了 \(organizer.summary.pendingDirectoryCount) 个需要人工判断的子目录。",
                recommendedAction: "进入文件整理页查看待处理目录，决定是否新增规则或手动归档。",
                priority: 45
            ))
        }
    }

    private static func appendLaunchAgentIssues(
        to issues: inout [MaintenanceHealthIssue],
        launchAgents: [LaunchAgentState],
        now: Date,
        fileManager: FileManager
    ) {
        for launchAgent in launchAgents {
            if !launchAgent.installed {
                issues.append(MaintenanceHealthIssue(
                    id: "missing-launch-agent-\(launchAgent.label)",
                    severity: .warning,
                    title: "定时任务未安装",
                    message: "\(launchAgent.label) 未安装到 LaunchAgents。",
                    recommendedAction: "进入定时任务页点击“重新安装”。",
                    affectedPath: launchAgent.plistPath,
                    priority: 60
                ))
                continue
            }

            if launchAgent.commandDescription == "未设置" {
                issues.append(MaintenanceHealthIssue(
                    id: "missing-launch-agent-command-\(launchAgent.label)",
                    severity: .warning,
                    title: "定时任务命令缺失",
                    message: "\(launchAgent.label) 已安装，但 plist 中没有 ProgramArguments。",
                    recommendedAction: "进入定时任务页重新安装该任务。",
                    affectedPath: launchAgent.plistPath,
                    priority: 61
                ))
            }

            guard let latestReportDate = latestReportModificationDate(for: launchAgent, fileManager: fileManager) else {
                if !launchAgent.reportPaths.isEmpty {
                    issues.append(MaintenanceHealthIssue(
                        id: "missing-launch-agent-output-\(launchAgent.label)",
                        severity: .warning,
                        title: "定时任务缺少报告产物",
                        message: "\(launchAgent.label) 没有找到可用于确认执行结果的报告文件。",
                        recommendedAction: "预览日志并确认任务是否已按计划触发。",
                        affectedPath: launchAgent.reportPaths.first,
                        priority: 62
                    ))
                }
                continue
            }

            let threshold = staleOutputInterval(for: launchAgent.label)
            if now.timeIntervalSince(latestReportDate) > threshold {
                issues.append(MaintenanceHealthIssue(
                    id: "stale-launch-agent-output-\(launchAgent.label)",
                    severity: .warning,
                    title: "定时任务报告过期",
                    message: "\(launchAgent.label) 最近报告更新时间为 \(ReportDateParser.string(from: latestReportDate))。",
                    recommendedAction: "进入定时任务页预览日志，确认最近一次计划执行是否成功。",
                    affectedPath: launchAgent.reportPaths.first,
                    priority: 63
                ))
            }
        }
    }

    // 每日文件整理给 36 小时容忍度；周任务给 8 天容忍度，避免时区和休眠造成误报。
    private static func staleOutputInterval(for label: String) -> TimeInterval {
        if label.contains("file-organizer") {
            return 36 * 60 * 60
        }
        return 8 * 24 * 60 * 60
    }

    private static func latestReportModificationDate(for launchAgent: LaunchAgentState, fileManager: FileManager) -> Date? {
        launchAgent.reportPaths
            .compactMap { latestModificationDate(atPath: $0, fileManager: fileManager) }
            .max()
    }

    private static func latestModificationDate(atPath path: String, fileManager: FileManager) -> Date? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            let directoryURL = URL(fileURLWithPath: path)
            let urls = (try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            return urls
                .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
                .max()
        }

        let attributes = try? fileManager.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date
    }

    private static func appendFileOrganizerSourceIssues(
        to issues: inout [MaintenanceHealthIssue],
        sources: [FileOrganizerConfiguredSource],
        fileManager: FileManager
    ) {
        for source in sources {
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory)
            guard !exists || !isDirectory.boolValue else {
                continue
            }
            issues.append(MaintenanceHealthIssue(
                id: "missing-file-organizer-source-\(source.path)",
                severity: .warning,
                title: "文件整理路径不可用",
                message: "\(source.path) 当前不存在或不是目录。",
                recommendedAction: "进入文件整理页移除该路径，或重新挂载对应磁盘/同步目录。",
                affectedPath: source.path,
                priority: 70
            ))
        }
    }
}

enum ReportDateParser {
    private static let localFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static func date(from value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        return localFormatter.date(from: value)
    }

    static func string(from date: Date) -> String {
        localFormatter.string(from: date)
    }
}
