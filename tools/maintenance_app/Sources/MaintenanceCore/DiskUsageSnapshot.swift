import Foundation

public struct DiskUsageSnapshot: Equatable, Sendable {
    public let volumeName: String
    public let mountPath: String
    public let totalBytes: Int64
    public let availableBytes: Int64

    public init(volumeName: String, mountPath: String, totalBytes: Int64, availableBytes: Int64) {
        self.volumeName = volumeName
        self.mountPath = mountPath
        self.totalBytes = max(totalBytes, 0)
        self.availableBytes = max(availableBytes, 0)
    }

    public var usedBytes: Int64 {
        max(totalBytes - availableBytes, 0)
    }

    public var usedFraction: Double {
        guard totalBytes > 0 else {
            return 0
        }
        return min(max(Double(usedBytes) / Double(totalBytes), 0), 1)
    }

    public static func current(for url: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> DiskUsageSnapshot {
        let resourceValues = try url.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeURLKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        let totalBytes = Int64(resourceValues.volumeTotalCapacity ?? 0)
        let availableBytes = resourceValues.volumeAvailableCapacityForImportantUsage
            ?? Int64(resourceValues.volumeAvailableCapacity ?? 0)
        return DiskUsageSnapshot(
            volumeName: resourceValues.volumeName ?? "Macintosh HD",
            mountPath: resourceValues.volume?.path ?? url.path,
            totalBytes: totalBytes,
            availableBytes: availableBytes
        )
    }
}
