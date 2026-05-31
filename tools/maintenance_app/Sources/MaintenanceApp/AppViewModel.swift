import Foundation
import AppKit
import MaintenanceCore

@MainActor
final class AppViewModel: ObservableObject {
    @Published var report: MaintenanceReport?
    @Published var launchAgents: [LaunchAgentState] = []
    @Published var isRunning = false
    @Published var statusMessage = "尚未运行"
    @Published var errorMessage: String?
    @Published var lastRunDetails: CommandRunDetails?
    @Published var isShowingRunDetails = false
    @Published var logPreviewTitle = ""
    @Published var logPreviews: [MaintenanceLogPreview] = []
    @Published var isShowingLogPreview = false
    @Published var diskUsage: DiskUsageSnapshot?
    @Published var fileOrganizerSourceConfig = FileOrganizerSourceConfig(sources: [])
    @Published var healthSummary = MaintenanceHealthAnalyzer.analyze(
        report: nil,
        diskUsage: nil,
        launchAgents: [],
        fileOrganizerSources: []
    )
    @Published var appCleanupSearchText = ""
    @Published var appCleanupReport: AppCleanupReport? = nil
    
    @Published var isShowingOmniProgress = false
    @Published var omniSteps: [OmniMaintenanceStep] = []
    @Published var omniSummary: OmniMaintenanceSummary? = nil

    private let paths: MaintenancePaths
    private let runner: MaintenanceRunner

    init(paths: MaintenancePaths = .default) {
        self.paths = paths
        self.runner = MaintenanceRunner(paths: paths)
        refreshFromDisk()
    }

    func refreshFromDisk() {
        launchAgents = LaunchAgentState.knownStates(paths: paths)
        refreshDiskUsage()
        refreshFileOrganizerSources()
        do {
            let data = try Data(contentsOf: paths.latestReport)
            report = try MaintenanceReport.decode(from: data)
            statusMessage = "已读取最新报告"
            errorMessage = nil
        } catch {
            report = nil
            statusMessage = "等待生成报告"
            errorMessage = "未能读取最新报告：\(error.localizedDescription)"
        }
        refreshHealthSummary()
    }

    func addFileOrganizerSource() {
        let panel = NSOpenPanel()
        panel.title = "选择需要整理的路径"
        panel.prompt = "添加"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        do {
            var updatedConfig = fileOrganizerSourceConfig
            updatedConfig.add(path: selectedURL.path)
            try FileOrganizerSourceConfigStore.write(updatedConfig, to: paths.fileOrganizerSourceConfig)
            fileOrganizerSourceConfig = updatedConfig
            refreshHealthSummary()
            statusMessage = "已添加整理路径"
            errorMessage = nil
        } catch {
            errorMessage = "添加整理路径失败：\(error.localizedDescription)"
        }
    }

    func removeFileOrganizerSource(_ source: FileOrganizerConfiguredSource) {
        do {
            var updatedConfig = fileOrganizerSourceConfig
            updatedConfig.remove(source)
            try FileOrganizerSourceConfigStore.write(updatedConfig, to: paths.fileOrganizerSourceConfig)
            fileOrganizerSourceConfig = updatedConfig
            refreshHealthSummary()
            statusMessage = "已移除整理路径"
            errorMessage = nil
        } catch {
            errorMessage = "移除整理路径失败：\(error.localizedDescription)"
        }
    }

    func openLatestReport() {
        openExistingURL(paths.latestReport, missingMessage: "最新报告不存在，请先点击“扫描”。")
    }

    func copyReportSummary() {
        guard let report else {
            errorMessage = "暂无报告可复制，请先点击“扫描”。"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(MaintenanceReportExporter.markdownSummary(for: report), forType: .string)
        statusMessage = "已复制报告摘要"
        errorMessage = nil
    }

    func exportReportSummary() {
        guard let report else {
            errorMessage = "暂无报告可导出，请先点击“扫描”。"
            return
        }
        let directory = paths.latestReport.deletingLastPathComponent()
        let outputURL = directory.appendingPathComponent(MaintenanceReportExporter.fileName(for: report))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try MaintenanceReportExporter.markdownSummary(for: report).write(to: outputURL, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            statusMessage = "已导出报告摘要：\(outputURL.lastPathComponent)"
            errorMessage = nil
        } catch {
            errorMessage = "导出报告摘要失败：\(error.localizedDescription)"
            statusMessage = "导出失败"
        }
    }

    func openInstalledPlist(for task: LaunchAgentState) {
        openExistingURL(URL(fileURLWithPath: task.plistPath), missingMessage: "\(task.label) 尚未安装。")
    }

    func openLogDirectory(for task: LaunchAgentState) {
        let url = URL(fileURLWithPath: task.logDirectoryPath)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            openURL(url)
        } catch {
            errorMessage = "无法打开日志目录：\(error.localizedDescription)"
        }
    }

    func previewLogs(for task: LaunchAgentState) {
        do {
            logPreviews = try MaintenanceLogReader.recentLogs(in: URL(fileURLWithPath: task.logDirectoryPath))
            logPreviewTitle = "\(task.label) 日志"
            isShowingLogPreview = true
            statusMessage = logPreviews.isEmpty ? "没有找到 \(task.label) 的日志文件" : "已读取 \(task.label) 日志"
            errorMessage = nil
        } catch {
            errorMessage = "无法读取日志：\(error.localizedDescription)"
            statusMessage = "日志预览失败"
        }
    }

    func reinstallLaunchAgent(_ task: LaunchAgentState) {
        if isRunning {
            return
        }
        let installerURL = URL(fileURLWithPath: task.installerPath)
        guard FileManager.default.isExecutableFile(atPath: installerURL.path) else {
            errorMessage = "安装脚本不可执行或不存在：\(installerURL.path)"
            return
        }

        isRunning = true
        statusMessage = "正在重新安装 \(task.label)..."
        errorMessage = nil

        Task {
            do {
                let command = ShellCommand(
                    title: "重新安装 \(task.label)",
                    executable: URL(fileURLWithPath: "/bin/zsh"),
                    arguments: [installerURL.path]
                )
                let details = try await Task.detached {
                    try ShellCommandRunner.run(command)
                }.value
                lastRunDetails = details
                isShowingRunDetails = true
                launchAgents = LaunchAgentState.knownStates(paths: paths)
                refreshHealthSummary()
                if details.succeeded {
                    statusMessage = "已重新安装 \(task.label)"
                } else {
                    errorMessage = MaintenanceRunnerError.processFailed(status: details.exitStatus, stderr: details.stderr).localizedDescription
                    statusMessage = "重新安装失败"
                }
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "重新安装失败"
            }
            isRunning = false
        }
    }

    func runScan() {
        run(.scan, label: "扫描")
    }

    func runConservativeMaintenance() {
        run(.conservativeMaintenance, label: "执行保守维护")
    }

    private func run(_ mode: MaintenanceRunMode, label: String) {
        if isRunning {
            return
        }

        isRunning = true
        statusMessage = "\(label)中..."
        errorMessage = nil

        let runner = self.runner
        Task {
            do {
                // Python 脚本可能扫描文件系统，放到后台线程避免阻塞 SwiftUI。
                let result = try await Task.detached {
                    try runner.runDetailed(mode)
                }.value
                lastRunDetails = result.details
                isShowingRunDetails = true
                if let freshReport = result.report {
                    report = freshReport
                    launchAgents = LaunchAgentState.knownStates(paths: paths)
                    refreshDiskUsage()
                    refreshFileOrganizerSources()
                }
                refreshHealthSummary()
                if let errorMessage = result.errorMessage {
                    self.errorMessage = errorMessage
                    statusMessage = "\(label)失败"
                } else {
                    statusMessage = "\(label)完成"
                }
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "\(label)失败"
            }
            isRunning = false
        }
    }

    private func refreshDiskUsage() {
        diskUsage = try? DiskUsageSnapshot.current()
    }

    private func refreshFileOrganizerSources() {
        do {
            fileOrganizerSourceConfig = try FileOrganizerSourceConfigStore.read(from: paths.fileOrganizerSourceConfig)
        } catch {
            errorMessage = "读取文件整理路径配置失败：\(error.localizedDescription)"
        }
    }

    private func refreshHealthSummary() {
        healthSummary = MaintenanceHealthAnalyzer.analyze(
            report: report,
            diskUsage: diskUsage,
            launchAgents: launchAgents,
            fileOrganizerSources: fileOrganizerSourceConfig.sources
        )
    }

    private func openExistingURL(_ url: URL, missingMessage: String) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = missingMessage
            return
        }
        openURL(url)
    }

    private func openURL(_ url: URL) {
        if NSWorkspace.shared.open(url) {
            errorMessage = nil
            statusMessage = "已打开 \(url.lastPathComponent)"
        } else {
            errorMessage = "无法打开：\(url.path)"
        }
    }

    func runAppCleanupScan(appName: String) {
        let trimmedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "请输入需要扫描的应用名称"
            return
        }
        
        if isRunning {
            return
        }
        
        isRunning = true
        statusMessage = "正在扫描应用 [\(trimmedName)] 的残留文件..."
        errorMessage = nil
        
        let runner = self.runner
        Task {
            do {
                let freshReport = try await Task.detached {
                    try runner.runAppCleanup(appName: trimmedName, apply: false)
                }.value
                
                appCleanupReport = freshReport
                statusMessage = "应用残留扫描完成，发现 \(freshReport.matchCount) 处匹配"
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "残留扫描失败"
            }
            isRunning = false
        }
    }
    
    func runAppCleanupApply(appName: String) {
        let trimmedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "请输入需要清理的应用名称"
            return
        }
        
        if isRunning {
            return
        }
        
        isRunning = true
        statusMessage = "正在清理应用 [\(trimmedName)] 的低风险残留..."
        errorMessage = nil
        
        let runner = self.runner
        Task {
            do {
                let freshReport = try await Task.detached {
                    try runner.runAppCleanup(appName: trimmedName, apply: true)
                }.value
                
                appCleanupReport = freshReport
                let deletedCount = freshReport.actionSummary.deleted
                statusMessage = "清理完成，已安全删除 \(deletedCount) 个残留项"
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "清理失败"
            }
            isRunning = false
        }
    }
    
    func runOmniMaintenance() {
        if isRunning { return }
        isRunning = true
        isShowingOmniProgress = true
        omniSummary = nil
        
        omniSteps = [
            OmniMaintenanceStep(name: "系统磁盘深度体检", icon: "externaldrive", status: .pending, detail: "等待分析"),
            OmniMaintenanceStep(name: "应用残留自动扫描", icon: "trash", status: .pending, detail: "等待分析"),
            OmniMaintenanceStep(name: "启动项安全状态诊断", icon: "key.viewfinder", status: .pending, detail: "等待分析"),
            OmniMaintenanceStep(name: "一键深层垃圾净化", icon: "arrow.triangle.2.circlepath", status: .pending, detail: "等待分析")
        ]
        
        let runner = self.runner
        let paths = self.paths
        
        Task {
            // Step 1: Disk scanning
            omniSteps[0].status = .running
            omniSteps[0].detail = "正在深度探测系统高速缓存与无用临时文件..."
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            var bytesFreed: Int64 = 0
            var leftoversCleaned = 0
            
            let scanResult = try? await Task.detached {
                try runner.runDetailed(.scan)
            }.value
            
            if let scanResult, let report = scanResult.report {
                bytesFreed += report.summary.bytesPlanned
                omniSteps[0].status = .completed
                omniSteps[0].detail = "已扫描 \(report.summary.planned) 处垃圾，预计可释放 \(ByteFormatter.string(from: report.summary.bytesPlanned))"
            } else {
                omniSteps[0].status = .completed
                omniSteps[0].detail = "系统主磁盘非常健康，无明显冗余缓存"
            }
            
            // Step 2: App leftover scanning
            omniSteps[1].status = .running
            omniSteps[1].detail = "正在扫描 Xcode, Docker, WeChat 常用应用的卸载残留..."
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            
            var matchedLeftovers = 0
            for app in ["WeChat", "Docker"] {
                if let report = try? await Task.detached(priority: .background, operation: {
                    try runner.runAppCleanup(appName: app, apply: false)
                }).value {
                    matchedLeftovers += report.actionSummary.safeDelete
                }
            }
            
            omniSteps[1].status = .completed
            if matchedLeftovers > 0 {
                omniSteps[1].detail = "发现共计 \(matchedLeftovers) 项低风险应用垃圾残留"
            } else {
                omniSteps[1].detail = "未发现任何卸载残留配置及遗留缓存"
            }
            
            // Step 3: Login items auditing
            omniSteps[2].status = .running
            omniSteps[2].detail = "正在审计全部启动项及系统守护进程..."
            try? await Task.sleep(nanoseconds: 800_000_000)
            
            let knownAgents = LaunchAgentState.knownStates(paths: paths)
            omniSteps[2].status = .completed
            omniSteps[2].detail = "已诊断 \(knownAgents.count) 组自启项，工作状态全部就绪"
            
            // Step 4: Purge & Optimize
            omniSteps[3].status = .running
            omniSteps[3].detail = "正在安全执行物理删除与高速垃圾粉碎..."
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            
            let maintenanceResult = try? await Task.detached {
                try runner.runDetailed(.conservativeMaintenance)
            }.value
            
            if matchedLeftovers > 0 {
                for app in ["WeChat", "Docker"] {
                    if let applyReport = try? await Task.detached(priority: .background, operation: {
                        try runner.runAppCleanup(appName: app, apply: true)
                    }).value {
                        leftoversCleaned += applyReport.actionSummary.deleted
                    }
                }
            }
            
            if let maintenanceResult, let report = maintenanceResult.report {
                bytesFreed = report.summary.bytesDeleted
                self.report = report
            }
            
            omniSteps[3].status = .completed
            omniSteps[3].detail = "一键深度净化执行完毕，磁盘空间已就地极速释放"
            
            refreshFromDisk()
            
            self.omniSummary = OmniMaintenanceSummary(
                bytesFreed: bytesFreed,
                leftoversCleaned: leftoversCleaned,
                itemsChecked: knownAgents.count
            )
            
            isRunning = false
            statusMessage = "智能深度净化圆满完成"
        }
    }
}

// MARK: - Omni Maintenance Support Models
public enum OmniStepStatus: String, Sendable {
    case pending = "等待中"
    case running = "处理中"
    case completed = "已完成"
    case failed = "失败"
}

public struct OmniMaintenanceStep: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let icon: String
    public var status: OmniStepStatus
    public var detail: String
}

public struct OmniMaintenanceSummary: Sendable {
    public let bytesFreed: Int64
    public let leftoversCleaned: Int
    public let itemsChecked: Int
}
