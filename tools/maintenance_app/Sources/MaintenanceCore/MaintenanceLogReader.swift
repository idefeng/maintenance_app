import Foundation

public struct MaintenanceLogPreview: Equatable, Sendable, Identifiable {
    public var id: String { path }

    public let path: String
    public let fileName: String
    public let modifiedAt: Date
    public let sizeBytes: Int64
    public let content: String
    public let isTruncated: Bool
}

public enum MaintenanceLogReader {
    public static func recentLogs(
        in directory: URL,
        limit: Int = 8,
        maxBytes: Int = 120_000
    ) throws -> [MaintenanceLogPreview] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsSubdirectoryDescendants]
        )
        .filter { !$0.lastPathComponent.hasPrefix(".") }
        .compactMap { url -> LogFileMetadata? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else {
                return nil
            }
            return LogFileMetadata(
                url: url,
                modifiedAt: values.contentModificationDate ?? Date.distantPast,
                sizeBytes: Int64(values.fileSize ?? 0)
            )
        }
        .sorted {
            if $0.modifiedAt == $1.modifiedAt {
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
            return $0.modifiedAt > $1.modifiedAt
        }
        .prefix(max(0, limit))

        return try files.map { metadata in
            let tail = try readTail(url: metadata.url, sizeBytes: metadata.sizeBytes, maxBytes: maxBytes)
            return MaintenanceLogPreview(
                path: metadata.url.path,
                fileName: metadata.url.lastPathComponent,
                modifiedAt: metadata.modifiedAt,
                sizeBytes: metadata.sizeBytes,
                content: tail.content,
                isTruncated: tail.isTruncated
            )
        }
    }

    private static func readTail(url: URL, sizeBytes: Int64, maxBytes: Int) throws -> (content: String, isTruncated: Bool) {
        let safeMaxBytes = max(1, maxBytes)
        let readSize = min(Int64(safeMaxBytes), max(0, sizeBytes))
        let offset = max(0, sizeBytes - readSize)
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: UInt64(offset))
        let data = try handle.readToEnd() ?? Data()

        // 只保留尾部内容，避免 App 内预览大日志时卡住界面。
        let content = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return (content, offset > 0)
    }
}

private struct LogFileMetadata {
    let url: URL
    let modifiedAt: Date
    let sizeBytes: Int64
}
