import Foundation

public struct FileOrganizerSourceConfig: Codable, Equatable, Sendable {
    public var sources: [FileOrganizerConfiguredSource]

    public init(sources: [FileOrganizerConfiguredSource]) {
        self.sources = sources
    }

    public mutating func add(path: String, recursive: Bool = false) {
        let normalizedPath = Self.normalize(path)
        guard !normalizedPath.isEmpty else {
            return
        }
        if sources.contains(where: { $0.path == normalizedPath }) {
            return
        }
        sources.append(FileOrganizerConfiguredSource(path: normalizedPath, recursive: recursive))
    }

    public mutating func remove(_ source: FileOrganizerConfiguredSource) {
        sources.removeAll { $0.path == source.path }
    }

    static func normalize(_ path: String) -> String {
        ((path as NSString).expandingTildeInPath as NSString).standardizingPath
    }
}

public struct FileOrganizerConfiguredSource: Codable, Equatable, Identifiable, Sendable {
    public var id: String { path }

    public let path: String
    public let recursive: Bool

    public init(path: String, recursive: Bool = false) {
        self.path = FileOrganizerSourceConfig.normalize(path)
        self.recursive = recursive
    }
}

public enum FileOrganizerSourceConfigStore {
    public static func read(from url: URL) throws -> FileOrganizerSourceConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return FileOrganizerSourceConfig(sources: [])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FileOrganizerSourceConfig.self, from: data)
    }

    public static func write(_ config: FileOrganizerSourceConfig, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
}
