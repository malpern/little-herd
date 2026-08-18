import Foundation

/// Remembers what folders were measured, so a scan is paid for once.
///
/// A top-level scan costs tens of seconds. Losing that on quit means the first
/// look every morning is a wait, for numbers that barely moved overnight —
/// so completed scans are written down and come back instantly, labelled with
/// when they were taken.
///
/// Only finished scans are kept. A scan that was cancelled or failed halfway
/// describes nothing in particular, and restoring it would present a partial
/// list as though it were the whole folder.
///
/// Deliberately not invalidated by directory modification times, though those
/// are already collected. A directory's mtime changes when its own entries
/// change, not when a file three levels down grows by ten gigabytes — so an
/// mtime check would confidently serve a stale size. Age is the honest signal,
/// and the interface offers a refresh rather than pretending to know.
nonisolated struct StoredFolderScan: Codable, Equatable, Sendable {
    let measuredAt: Date
    let entries: [FolderEntry]
}

@MainActor
final class FolderSizeStore {
    private let fileURL: URL?
    private var scans: [String: StoredFolderScan]

    /// How long a remembered scan is worth restoring at all. Past this it is
    /// less "what is on the disk" than "what was on the disk", and re-measuring
    /// is the better answer.
    static let retention: TimeInterval = 30 * 24 * 3_600

    init(fileURL: URL? = FolderSizeStore.defaultFileURL()) {
        self.fileURL = fileURL
        scans = Self.load(from: fileURL)
    }

    static func defaultFileURL() -> URL? {
        let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("LittleHerd", isDirectory: true)
        guard let directory else { return nil }
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory.appendingPathComponent("folder-sizes.json")
    }

    /// Keyed by machine as well as path, because "/" means something different
    /// on each of them and one machine's answer must never be shown as
    /// another's.
    private func key(machine: MachineID, path: String) -> String {
        "\(machine.rawValue)\u{0000}\(path)"
    }

    func scan(machine: MachineID, path: String) -> StoredFolderScan? {
        guard let stored = scans[key(machine: machine, path: path)] else { return nil }
        guard Date().timeIntervalSince(stored.measuredAt) <= Self.retention else {
            return nil
        }
        return stored
    }

    func record(
        _ entries: [FolderEntry],
        machine: MachineID,
        path: String,
        measuredAt: Date = Date()
    ) {
        scans[key(machine: machine, path: path)] = StoredFolderScan(
            measuredAt: measuredAt,
            entries: entries
        )
        persist()
    }

    /// Forgetting a machine's readings when it is removed from the herd, so a
    /// file does not accumulate answers about machines that are no longer here.
    func forget(machine: MachineID) {
        let prefix = "\(machine.rawValue)\u{0000}"
        scans = scans.filter { !$0.key.hasPrefix(prefix) }
        persist()
    }

    private func persist() {
        guard let fileURL else { return }
        let fresh = scans.filter {
            Date().timeIntervalSince($0.value.measuredAt) <= Self.retention
        }
        scans = fresh
        guard let data = try? JSONEncoder().encode(fresh) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func load(from fileURL: URL?) -> [String: StoredFolderScan] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(
                  [String: StoredFolderScan].self,
                  from: data
              )
        else {
            return [:]
        }
        let cutoff = Date().addingTimeInterval(-retention)
        return decoded.filter { $0.value.measuredAt >= cutoff }
    }
}
