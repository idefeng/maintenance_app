import Foundation

public struct MaintenancePaths: Equatable, Sendable {
    public let workspaceRoot: URL

    public init(workspaceRoot: URL = URL(fileURLWithPath: "/Users/idefeng/Documents/work")) {
        self.workspaceRoot = workspaceRoot
    }

    public static let `default` = MaintenancePaths()

    public var unifiedScript: URL {
        workspaceRoot
            .appendingPathComponent("tools")
            .appendingPathComponent("disk_cleanup")
            .appendingPathComponent("scripts")
            .appendingPathComponent("disk_cleanup.py")
    }

    public var latestReport: URL {
        workspaceRoot
            .appendingPathComponent("tools")
            .appendingPathComponent("disk_cleanup")
            .appendingPathComponent("runtime")
            .appendingPathComponent("reports")
            .appendingPathComponent("latest.json")
    }

    public var diskCleanupToolRoot: URL {
        workspaceRoot.appendingPathComponent("tools").appendingPathComponent("disk_cleanup")
    }

    public var fileOrganizerToolRoot: URL {
        workspaceRoot.appendingPathComponent("tools").appendingPathComponent("file_organizer")
    }

    public var fileOrganizerSourceConfig: URL {
        fileOrganizerToolRoot
            .appendingPathComponent("runtime")
            .appendingPathComponent("config")
            .appendingPathComponent("source-rules.json")
    }

    public var appCleanupToolRoot: URL {
        workspaceRoot.appendingPathComponent("tools").appendingPathComponent("app_cleanup")
    }

    public var userLaunchAgentsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("LaunchAgents")
    }
}
