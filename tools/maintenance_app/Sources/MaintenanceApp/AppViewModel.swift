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
}
