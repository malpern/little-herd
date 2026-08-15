import Foundation

nonisolated struct StorageVolume: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let mountPath: String
    let availableBytes: Double
    let totalBytes: Double

    var usedBytes: Double {
        max(totalBytes - availableBytes, 0)
    }

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(usedBytes / totalBytes * 100, 0), 100)
    }
}
