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
    /// What the machine says about this volume's condition, when it says
    /// anything. Only a NAS does: macOS reports capacity but has no opinion on
    /// whether a volume is degraded. A volume can be healthy-looking and nearly
    /// empty while its pool is falling apart underneath.
    var health: SynologyHealth?

    /// Deliberately the total less what is free, rather than what the volume
    /// says it is using.
    ///
    /// The two disagree, and the obvious-looking correction is wrong. A Mac's
    /// startup row is one volume of an APFS container whose siblings — Data, VM,
    /// Preboot — are not listed, so what it reports using is the sealed system
    /// alone: 17 GB on a mini whose container holds 945 GB and has 46 GB left.
    /// Believing that figure reads a nearly full disk as a quarter full, which
    /// is the dangerous direction to be wrong in. Subtracting from the total
    /// counts every sibling, listed or not, and gets the container right.
    ///
    /// It fails only where the total is fiction — a sparse disk image, whose
    /// size is a ceiling rather than storage that exists. Those are excluded
    /// before they reach here, which is the honest fix: their bytes belong to
    /// whatever holds the image, and are counted there already.
    var usedBytes: Double {
        max(totalBytes - availableBytes, 0)
    }

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(usedBytes / totalBytes * 100, 0), 100)
    }
}
