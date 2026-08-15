import Foundation

nonisolated struct StorageVolume: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let mountPath: String
    let availableBytes: Double
    let totalBytes: Double
    /// How many volumes share this row. APFS volumes in one container share a
    /// free-space pool, so they are reported as one row — and the figures
    /// describe the container, not the volume the row is named after.
    var volumeCount: Int = 1

    var usedBytes: Double {
        max(totalBytes - availableBytes, 0)
    }

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(usedBytes / totalBytes * 100, 0), 100)
    }
}
