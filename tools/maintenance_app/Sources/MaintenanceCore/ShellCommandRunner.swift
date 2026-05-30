import Foundation

public struct ShellCommand: Equatable, Sendable {
    public let title: String
    public let executable: URL
    public let arguments: [String]

    public init(title: String, executable: URL, arguments: [String]) {
        self.title = title
        self.executable = executable
        self.arguments = arguments
    }

    public var commandLine: String {
        ([executable.path] + arguments).map(Self.shellQuoted).joined(separator: " ")
    }

    private static func shellQuoted(_ value: String) -> String {
        if value.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "\"'\\$`"))) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct CommandRunDetails: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let commandLine: String
    public let startedAt: Date
    public let finishedAt: Date
    public let exitStatus: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool {
        exitStatus == 0
    }

    public var outputText: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

public enum ShellCommandRunner {
    public static func run(_ command: ShellCommand) throws -> CommandRunDetails {
        let startedAt = Date()
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return CommandRunDetails(
            id: UUID().uuidString,
            title: command.title,
            commandLine: command.commandLine,
            startedAt: startedAt,
            finishedAt: Date(),
            exitStatus: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}
