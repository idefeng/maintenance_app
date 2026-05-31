import Foundation

public struct AppCleanupReport: Decodable, Equatable, Sendable {
    public let appName: String
    public let generatedAt: String
    public let cleanupMode: String
    public let scanRoots: [AppCleanupScanRoot]
    public let matches: [AppCleanupMatch]
    public let matchCount: Int
    public let actionSummary: AppCleanupActionSummary

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case generatedAt = "generated_at"
        case cleanupMode = "cleanup_mode"
        case scanRoots = "scan_roots"
        case matches
        case matchCount = "match_count"
        case actionSummary = "action_summary"
    }

    public static func decode(from data: Data) throws -> AppCleanupReport {
        try JSONDecoder().decode(AppCleanupReport.self, from: data)
    }
}

public struct AppCleanupScanRoot: Decodable, Equatable, Sendable {
    public let category: String
    public let path: String
    public let status: String
}

public struct AppCleanupMatch: Decodable, Equatable, Sendable, Identifiable {
    public var id: String { path }
    
    public let path: String
    public let category: String
    public let name: String
    public let matchReason: String
    public let pathType: String
    public let riskLevel: String
    public let plannedAction: String
    public let actionStatus: String
    public let actionError: String?

    enum CodingKeys: String, CodingKey {
        case path
        case category
        case name
        case matchReason = "match_reason"
        case pathType = "path_type"
        case riskLevel = "risk_level"
        case plannedAction = "planned_action"
        case actionStatus = "action_status"
        case actionError = "action_error"
    }
}

public struct AppCleanupActionSummary: Decodable, Equatable, Sendable {
    public let safeDelete: Int
    public let reportOnly: Int
    public let skip: Int
    public let deleted: Int
    public let reported: Int
    public let failed: Int

    enum CodingKeys: String, CodingKey {
        case safeDelete = "safe_delete"
        case reportOnly = "report_only"
        case skip
        case deleted
        case reported
        case failed
    }
}
