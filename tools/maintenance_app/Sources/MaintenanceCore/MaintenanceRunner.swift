import Foundation

public enum MaintenanceRunMode: Sendable {
    case scan
    case conservativeMaintenance

    public var title: String {
        switch self {
        case .scan:
            return "扫描"
        case .conservativeMaintenance:
            return "执行保守维护"
        }
    }
}

public struct MaintenanceCommand: Equatable, Sendable {
    public let executable: URL
    public let arguments: [String]

    public func shellCommand(title: String) -> ShellCommand {
        ShellCommand(title: title, executable: executable, arguments: arguments)
    }
}

public struct MaintenanceRunResult: Equatable, Sendable {
    public let report: MaintenanceReport?
    public let details: CommandRunDetails
    public let errorMessage: String?

    public var succeeded: Bool {
        errorMessage == nil
    }
}

public enum MaintenanceRunnerError: Error, Equatable, Sendable, LocalizedError {
    case processFailed(status: Int32, stderr: String)
    case noJSONOutput

    public var errorDescription: String? {
        switch self {
        case let .processFailed(status, stderr):
            return "维护脚本执行失败，退出码 \(status)：\(stderr)"
        case .noJSONOutput:
            return "维护脚本没有输出 JSON 报告"
        }
    }
}

public struct MaintenanceRunner: Sendable {
    public let paths: MaintenancePaths
    public let pythonExecutable: URL

    public init(
        paths: MaintenancePaths = .default,
        pythonExecutable: URL = URL(fileURLWithPath: "/usr/bin/python3")
    ) {
        self.paths = paths
        self.pythonExecutable = pythonExecutable
    }

    public func command(for mode: MaintenanceRunMode) -> MaintenanceCommand {
        var arguments = [paths.unifiedScript.path]
        switch mode {
        case .scan:
            arguments.append(contentsOf: ["--login-items", "--organize-files", "--json"])
        case .conservativeMaintenance:
            arguments.append(contentsOf: ["--apply", "--login-items", "--organize-files", "--json"])
        }
        return MaintenanceCommand(executable: pythonExecutable, arguments: arguments)
    }

    public func run(_ mode: MaintenanceRunMode) throws -> MaintenanceReport {
        let result = try runDetailed(mode)
        if let errorMessage = result.errorMessage {
            throw MaintenanceRunnerError.processFailed(status: result.details.exitStatus, stderr: errorMessage)
        }
        guard let report = result.report else {
            throw MaintenanceRunnerError.noJSONOutput
        }
        return report
    }

    public func runDetailed(_ mode: MaintenanceRunMode) throws -> MaintenanceRunResult {
        let command = command(for: mode)
        let details = try ShellCommandRunner.run(command.shellCommand(title: mode.title))
        guard details.succeeded else {
            return MaintenanceRunResult(report: nil, details: details, errorMessage: details.stderr)
        }
        guard !details.stdout.isEmpty, let data = details.stdout.data(using: .utf8) else {
            return MaintenanceRunResult(report: nil, details: details, errorMessage: MaintenanceRunnerError.noJSONOutput.localizedDescription)
        }
        do {
            return MaintenanceRunResult(
                report: try MaintenanceReport.decode(from: data),
                details: details,
                errorMessage: nil
            )
        } catch {
            return MaintenanceRunResult(report: nil, details: details, errorMessage: error.localizedDescription)
        }
    }

    public func runAppCleanup(appName: String, apply: Bool) throws -> AppCleanupReport {
        let scriptPath = paths.appCleanupToolRoot
            .appendingPathComponent("scripts")
            .appendingPathComponent("app_cleanup.py")
        var arguments = [scriptPath.path, appName, "--json"]
        if apply {
            arguments.append("--apply")
        }
        let command = ShellCommand(
            title: apply ? "执行应用残留清理：\(appName)" : "扫描应用残留：\(appName)",
            executable: pythonExecutable,
            arguments: arguments
        )
        let details = try ShellCommandRunner.run(command)
        guard details.succeeded else {
            throw MaintenanceRunnerError.processFailed(status: details.exitStatus, stderr: details.stderr)
        }
        guard !details.stdout.isEmpty, let data = details.stdout.data(using: .utf8) else {
            throw MaintenanceRunnerError.noJSONOutput
        }
        return try JSONDecoder().decode(AppCleanupReport.self, from: data)
    }
}

