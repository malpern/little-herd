import AppKit

/// Whether this app may read the whole disk, and how to ask.
///
/// Measuring what fills a volume means walking it, and on a Mac that means
/// walking into Photos, iCloud Drive, Desktop, Documents and Downloads. macOS
/// gates each of those separately and attributes the attempt to whichever app
/// spawned the command — so a scan without this permission does not fail
/// quietly, it raises a permission dialog per protected folder. That is a poor
/// way to answer a question someone asked once.
///
/// Remote machines are unaffected: their commands run under sshd, which macOS
/// already grants this. Only this Mac needs asking.
nonisolated enum FullDiskAccess {
    /// Reading a file only this permission can open, which macOS answers
    /// without a prompt — the point being to find out *before* triggering the
    /// dialogs, rather than discovering it one folder at a time.
    static var isGranted: Bool {
        for path in probePaths {
            guard let handle = FileHandle(forReadingAtPath: path) else { continue }
            defer { try? handle.close() }
            if (try? handle.read(upToCount: 1)) != nil { return true }
        }
        return false
    }

    /// The system database first, a Safari file second. Neither prompts, and
    /// having two means an empty or moved database does not read as a refusal.
    private static let probePaths = [
        "/Library/Application Support/com.apple.TCC/TCC.db",
        NSHomeDirectory() + "/Library/Safari/Bookmarks.plist",
    ]

    @MainActor
    static func openSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Whether a machine can be asked what fills its disks, and why not when it
/// cannot. Three different answers that used to be one silent `nil`.
nonisolated enum FolderScanAvailability {
    case available(FolderSizeScanner)
    /// This Mac, without permission to read the whole disk.
    case needsFullDiskAccess
    /// A NAS reached through DSM, whose DirSize API starts a task and then
    /// denies that task exists.
    case unsupported

    var scanner: FolderSizeScanner? {
        if case .available(let scanner) = self { return scanner }
        return nil
    }
}
