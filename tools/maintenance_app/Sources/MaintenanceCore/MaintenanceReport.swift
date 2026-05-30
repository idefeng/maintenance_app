import Foundation

public struct MaintenanceReport: Decodable, Equatable, Sendable {
    public let generatedAt: String
    public let apply: Bool
    public let includeAssets: Bool
    public let includeLoginItems: Bool
    public let includeFileOrganizer: Bool
    public let skipDiskCleanup: Bool
    public let summary: DiskCleanupSummary
    public let candidates: [CleanupCandidate]
    public let loginItems: LoginItemsSection?
    public let fileOrganizer: FileOrganizerSection?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case apply
        case includeAssets = "include_assets"
        case includeLoginItems = "include_login_items"
        case includeFileOrganizer = "include_file_organizer"
        case skipDiskCleanup = "skip_disk_cleanup"
        case summary
        case candidates
        case loginItems = "login_items"
        case fileOrganizer = "file_organizer"
    }

    public static func decode(from data: Data) throws -> MaintenanceReport {
        try JSONDecoder().decode(MaintenanceReport.self, from: data)
    }
}

public struct DiskCleanupSummary: Decodable, Equatable, Sendable {
    public let planned: Int
    public let deleted: Int
    public let skipped: Int
    public let missing: Int
    public let failed: Int
    public let bytesPlanned: Int64
    public let bytesDeleted: Int64

    enum CodingKeys: String, CodingKey {
        case planned
        case deleted
        case skipped
        case missing
        case failed
        case bytesPlanned = "bytes_planned"
        case bytesDeleted = "bytes_deleted"
    }
}

public struct CleanupCandidate: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { path }

    public let path: String
    public let category: String
    public let reason: String
    public let riskLevel: String
    public let sizeBytes: Int64
    public let status: String
    public let error: String?

    enum CodingKeys: String, CodingKey {
        case path
        case category
        case reason
        case riskLevel = "risk_level"
        case sizeBytes = "size_bytes"
        case status
        case error
    }
}

public struct LoginItemsSection: Decodable, Equatable, Sendable {
    public let mode: String
    public let sfltoolError: String?
    public let summary: LoginItemsSummary
    public let duplicateDisplayNames: [DuplicateLoginDisplayName]
    public let items: [LoginItem]
    public let launchPlists: [LaunchPlistRecord]

    enum CodingKeys: String, CodingKey {
        case mode
        case sfltoolError = "sfltool_error"
        case summary
        case duplicateDisplayNames = "duplicate_display_names"
        case items
        case launchPlists = "launch_plists"
    }
}

public struct LoginItemsSummary: Decodable, Equatable, Sendable {
    public let itemCount: Int
    public let launchPlistCount: Int
    public let ownAutomationCount: Int
    public let possibleRemnantCount: Int
    public let manualReviewCount: Int

    enum CodingKeys: String, CodingKey {
        case itemCount = "item_count"
        case launchPlistCount = "launch_plist_count"
        case ownAutomationCount = "own_automation_count"
        case possibleRemnantCount = "possible_remnant_count"
        case manualReviewCount = "manual_review_count"
    }
}

public struct DuplicateLoginDisplayName: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { displayName }

    public let displayName: String
    public let count: Int
    public let identifiers: [String?]

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case count
        case identifiers
    }
}

public struct LoginItem: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { uuid ?? identifier ?? displayName }

    public let uid: String?
    public let uuid: String?
    public let displayName: String
    public let name: String?
    public let developerName: String?
    public let itemType: String?
    public let disposition: String?
    public let identifier: String?
    public let urlPath: String?
    public let executablePath: String?
    public let category: String
    public let suggestedAction: String
    public let riskLevel: String
    public let classificationReason: String

    enum CodingKeys: String, CodingKey {
        case uid
        case uuid
        case displayName = "display_name"
        case name
        case developerName = "developer_name"
        case itemType = "item_type"
        case disposition
        case identifier
        case urlPath = "url_path"
        case executablePath = "executable_path"
        case category
        case suggestedAction = "suggested_action"
        case riskLevel = "risk_level"
        case classificationReason = "classification_reason"
    }
}

public struct LaunchPlistRecord: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { path }

    public let path: String
    public let label: String?
    public let executable: String?
    public let rootLevel: Bool

    enum CodingKeys: String, CodingKey {
        case path
        case label
        case executable
        case rootLevel = "root_level"
    }
}

public struct FileOrganizerSection: Decodable, Equatable, Sendable {
    public let tool: String
    public let runAt: String
    public let dryRun: Bool
    public let summary: FileOrganizerSummary
    public let sources: [FileOrganizerSource]
    public let pendingDirectoriesPath: String?
    public let reportPath: String?

    enum CodingKeys: String, CodingKey {
        case tool
        case runAt = "run_at"
        case dryRun = "dry_run"
        case summary
        case sources
        case pendingDirectoriesPath = "pending_directories_path"
        case reportPath = "report_path"
    }
}

public struct FileOrganizerSummary: Decodable, Equatable, Sendable {
    public let sourceCount: Int
    public let actionCount: Int
    public let pendingDirectoryCount: Int
    public let skippedCount: Int

    enum CodingKeys: String, CodingKey {
        case sourceCount = "source_count"
        case actionCount = "action_count"
        case pendingDirectoryCount = "pending_directory_count"
        case skippedCount = "skipped_count"
    }
}

public struct FileOrganizerSource: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { source }

    public let source: String
    public let recursive: Bool
    public let actionCount: Int
    public let pendingDirectoryCount: Int
    public let skippedCount: Int
    public let actions: [FileOrganizerAction]
    public let pendingDirectories: [PendingDirectory]
    public let skippedEntries: [SkippedEntry]

    enum CodingKeys: String, CodingKey {
        case source
        case recursive
        case actionCount = "action_count"
        case pendingDirectoryCount = "pending_directory_count"
        case skippedCount = "skipped_count"
        case actions
        case pendingDirectories = "pending_directories"
        case skippedEntries = "skipped_entries"
    }
}

public struct FileOrganizerAction: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { "\(source)->\(destination)" }

    public let source: String
    public let destination: String
    public let category: String
    public let status: String
    public let reason: String
}

public struct PendingDirectory: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { directory }

    public let sourceRoot: String
    public let directory: String

    enum CodingKeys: String, CodingKey {
        case sourceRoot = "source_root"
        case directory
    }
}

public struct SkippedEntry: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { path }

    public let path: String
    public let reason: String
}
