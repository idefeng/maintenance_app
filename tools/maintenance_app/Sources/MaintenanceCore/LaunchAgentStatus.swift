import Foundation

public struct MaintenanceTaskDefinition: Equatable, Sendable, Identifiable {
    public var id: String { label }

    public let label: String
    public let installedPlistURL: URL
    public let templatePlistURL: URL
    public let logDirectoryURL: URL
    public let installerURL: URL
    public let reportURLs: [URL]

    public init(
        label: String,
        installedPlistURL: URL,
        templatePlistURL: URL,
        logDirectoryURL: URL,
        installerURL: URL,
        reportURLs: [URL]
    ) {
        self.label = label
        self.installedPlistURL = installedPlistURL
        self.templatePlistURL = templatePlistURL
        self.logDirectoryURL = logDirectoryURL
        self.installerURL = installerURL
        self.reportURLs = reportURLs
    }
}

public struct LaunchAgentState: Equatable, Sendable, Identifiable {
    public var id: String { label }

    public let definition: MaintenanceTaskDefinition
    public let label: String
    public let plistPath: String
    public let templatePlistPath: String
    public let logDirectoryPath: String
    public let installerPath: String
    public let reportPaths: [String]
    public let installed: Bool
    public let scheduleDescription: String
    public let commandDescription: String

    public init(label: String, plistURL: URL, payload: [String: Any]?, installed: Bool) {
        let fallbackDefinition = MaintenanceTaskDefinition(
            label: label,
            installedPlistURL: plistURL,
            templatePlistURL: plistURL,
            logDirectoryURL: plistURL.deletingLastPathComponent(),
            installerURL: plistURL,
            reportURLs: []
        )
        self.init(definition: fallbackDefinition, payload: payload, installed: installed)
    }

    public init(definition: MaintenanceTaskDefinition, payload: [String: Any]?, installed: Bool) {
        self.definition = definition
        self.label = definition.label
        self.plistPath = definition.installedPlistURL.path
        self.templatePlistPath = definition.templatePlistURL.path
        self.logDirectoryPath = definition.logDirectoryURL.path
        self.installerPath = definition.installerURL.path
        self.reportPaths = definition.reportURLs.map(\.path)
        self.installed = installed
        self.scheduleDescription = Self.describeSchedule(payload?["StartCalendarInterval"])
        self.commandDescription = Self.describeCommand(payload?["ProgramArguments"])
    }

    public static func knownStates(paths: MaintenancePaths = .default) -> [LaunchAgentState] {
        knownDefinitions(paths: paths).map { definition in
            let payload = readPlist(at: definition.installedPlistURL)
            return LaunchAgentState(
                definition: definition,
                payload: payload,
                installed: payload != nil
            )
        }
    }

    public static func knownDefinitions(paths: MaintenancePaths = .default) -> [MaintenanceTaskDefinition] {
        let launchRoot = paths.userLaunchAgentsDirectory
        return [
            MaintenanceTaskDefinition(
                label: "com.idefeng.disk-cleanup",
                installedPlistURL: launchRoot.appendingPathComponent("com.idefeng.disk-cleanup.plist"),
                templatePlistURL: paths.diskCleanupToolRoot
                    .appendingPathComponent("launchd")
                    .appendingPathComponent("com.idefeng.disk-cleanup.plist"),
                logDirectoryURL: paths.diskCleanupToolRoot
                    .appendingPathComponent("runtime")
                    .appendingPathComponent("logs"),
                installerURL: paths.diskCleanupToolRoot
                    .appendingPathComponent("scripts")
                    .appendingPathComponent("install_launch_agent.sh"),
                reportURLs: [
                    paths.latestReport,
                    paths.diskCleanupToolRoot
                        .appendingPathComponent("runtime")
                        .appendingPathComponent("reports")
                ]
            ),
            MaintenanceTaskDefinition(
                label: "com.idefeng.file-organizer",
                installedPlistURL: launchRoot.appendingPathComponent("com.idefeng.file-organizer.plist"),
                templatePlistURL: paths.fileOrganizerToolRoot
                    .appendingPathComponent("launchd")
                    .appendingPathComponent("com.idefeng.file-organizer.plist"),
                logDirectoryURL: paths.fileOrganizerToolRoot
                    .appendingPathComponent("runtime")
                    .appendingPathComponent("logs"),
                installerURL: paths.fileOrganizerToolRoot
                    .appendingPathComponent("scripts")
                    .appendingPathComponent("install_launch_agent.sh"),
                reportURLs: [
                    paths.fileOrganizerToolRoot
                        .appendingPathComponent("runtime")
                        .appendingPathComponent("reports")
                        .appendingPathComponent("latest.json"),
                    paths.fileOrganizerToolRoot
                        .appendingPathComponent("runtime")
                        .appendingPathComponent("reports")
                        .appendingPathComponent("pending-directories-latest.json")
                ]
            ),
            MaintenanceTaskDefinition(
                label: "com.idefeng.app-cleanup",
                installedPlistURL: launchRoot.appendingPathComponent("com.idefeng.app-cleanup.plist"),
                templatePlistURL: paths.appCleanupToolRoot
                    .appendingPathComponent("launchd")
                    .appendingPathComponent("com.idefeng.app-cleanup.plist"),
                logDirectoryURL: paths.appCleanupToolRoot
                    .appendingPathComponent("runtime")
                    .appendingPathComponent("logs"),
                installerURL: paths.appCleanupToolRoot
                    .appendingPathComponent("scripts")
                    .appendingPathComponent("install_launch_agent.sh"),
                reportURLs: [
                    paths.appCleanupToolRoot
                        .appendingPathComponent("runtime")
                        .appendingPathComponent("reports")
                ]
            )
        ]
    }

    private static func readPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }

    private static func describeSchedule(_ value: Any?) -> String {
        if let list = value as? [[String: Any]], let first = list.first {
            return describeScheduleDictionary(first)
        }
        if let dictionary = value as? [String: Any] {
            return describeScheduleDictionary(dictionary)
        }
        return "未设置"
    }

    private static func describeScheduleDictionary(_ dictionary: [String: Any]) -> String {
        let hour = dictionary["Hour"] as? Int
        let minute = dictionary["Minute"] as? Int
        let time = formatTime(hour: hour, minute: minute)

        if let weekday = dictionary["Weekday"] as? Int {
            return "\(weekdayName(weekday)) \(time)"
        }
        return "每天 \(time)"
    }

    private static func formatTime(hour: Int?, minute: Int?) -> String {
        let safeHour = hour ?? 0
        let safeMinute = minute ?? 0
        return String(format: "%02d:%02d", safeHour, safeMinute)
    }

    private static func weekdayName(_ weekday: Int) -> String {
        switch weekday {
        case 0, 7: return "周日"
        case 1: return "周一"
        case 2: return "周二"
        case 3: return "周三"
        case 4: return "周四"
        case 5: return "周五"
        case 6: return "周六"
        default: return "周\(weekday)"
        }
    }

    private static func describeCommand(_ value: Any?) -> String {
        guard let arguments = value as? [String], !arguments.isEmpty else {
            return "未设置"
        }
        return arguments.joined(separator: " ")
    }
}
