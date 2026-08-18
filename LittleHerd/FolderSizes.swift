import Foundation

/// Measuring what is actually taking up a volume.
///
/// Deliberately not part of the sampling loop. A top-level scan of a 286 GB
/// volume took 43 seconds on the mini, and the NAS holds 5.9 TB — this is work
/// someone asks for, watches, and can call off, not something that happens
/// every ten seconds behind their back.
///
/// The children are measured one at a time rather than in a single `du` over
/// the whole tree. It costs the same in total, but it buys the two things that
/// make a slow job bearable: rows appear as they are counted, and progress is a
/// real fraction rather than a spinner that says nothing.

nonisolated struct FolderEntry: Identifiable, Equatable, Codable, Sendable {
    let name: String
    let path: String
    let sizeBytes: Double
    /// Only a directory can be opened further; a large file is a leaf.
    let isDirectory: Bool
    /// When it last changed, where the machine could say. Finder's second
    /// column, and the one that answers "what have I been filling this with
    /// lately" rather than "what is biggest".
    var modifiedAt: Date?

    var id: String { path }
}

/// How far along a scan is, and how much longer it is likely to take.
nonisolated struct FolderScanProgress: Equatable, Sendable {
    let measured: Int
    let total: Int
    let elapsed: TimeInterval

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(measured) / Double(total), 0), 1)
    }

    var isComplete: Bool { total > 0 && measured >= total }

    /// Projected from the rate so far, which is the only rate anyone can know.
    ///
    /// Nothing is offered until a couple of children are done: an estimate
    /// drawn from a single sample is a guess wearing a number's clothes, and
    /// folders differ enough in size that the first one is a poor predictor.
    /// Directories are counted, not bytes, so a huge folder late in the list
    /// will make this optimistic — which is why it is phrased as "about".
    var estimatedRemaining: TimeInterval? {
        guard measured >= 2, total > measured, elapsed > 0 else { return nil }
        let perItem = elapsed / Double(measured)
        return perItem * Double(total - measured)
    }
}

/// What a scan is doing, from the interface's point of view.
nonisolated enum FolderScanState: Equatable, Sendable {
    case idle
    case listing
    case measuring(FolderScanProgress)
    case done(measuredAt: Date)
    case failed(String)
    case cancelled

    var isRunning: Bool {
        switch self {
        case .listing, .measuring: true
        case .idle, .done, .failed, .cancelled: false
        }
    }
}

/// A folder's contents, measured, with whatever is known so far.
///
/// Entries accumulate as they are counted, so the list is useful before it is
/// finished — the biggest thing on a volume is usually visible long before the
/// last folder has been walked.
nonisolated struct FolderScan: Equatable, Sendable {
    let path: String
    var entries: [FolderEntry] = []
    var state: FolderScanState = .idle

    /// Largest first: the question being asked is always "what is eating this".
    var rankedEntries: [FolderEntry] {
        entries.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    var totalMeasuredBytes: Double {
        entries.reduce(0) { $0 + $1.sizeBytes }
    }

    /// Worth offering a refresh rather than trusting: folder sizes drift, and a
    /// reading from this morning describes this morning.
    func isStale(now: Date, after age: TimeInterval = 3_600) -> Bool {
        guard case .done(let measuredAt) = state else { return false }
        return now.timeIntervalSince(measuredAt) > age
    }
}

/// How the list is ordered, and which way.
///
/// Finder's columns, because this is Finder's job: what is biggest, what
/// changed recently, and what it is called. Each field has an order that is
/// obviously the useful one — largest first, newest first, but names A to Z —
/// so clicking a column heading for the first time does the expected thing
/// rather than the alphabetically consistent one.
nonisolated enum FolderSortField: String, CaseIterable, Sendable {
    case name
    case size
    case dateModified

    var defaultAscending: Bool {
        switch self {
        case .name: true
        case .size, .dateModified: false
        }
    }

    var title: String {
        switch self {
        case .name: "Name"
        case .size: "Size"
        case .dateModified: "Date Modified"
        }
    }
}

nonisolated struct FolderSort: Equatable, Sendable {
    var field: FolderSortField = .size
    var ascending: Bool = false

    /// Clicking the column you are already sorted by reverses it; clicking a
    /// different one starts from that column's own sensible direction.
    mutating func toggle(_ field: FolderSortField) {
        if self.field == field {
            ascending.toggle()
        } else {
            self.field = field
            ascending = field.defaultAscending
        }
    }

    func sorted(_ entries: [FolderEntry]) -> [FolderEntry] {
        let ordered = entries.sorted { first, second in
            switch field {
            case .name:
                first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .size:
                first.sizeBytes < second.sizeBytes
            case .dateModified:
                // Anything undated sorts as oldest, so a folder the machine
                // could not stat sinks rather than jumping to the top.
                (first.modifiedAt ?? .distantPast) < (second.modifiedAt ?? .distantPast)
            }
        }
        return ascending ? ordered : ordered.reversed()
    }
}

/// Dates the way Finder writes them.
///
/// "Today at 2:30 PM" reads at a glance; "2026-08-17 14:30:00" has to be
/// decoded, and decoded against today's date to mean anything.
nonisolated enum FolderDateFormatter {
    static func string(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time)"
        }
        // The Finder writes "Aug 14, 2026 at 6:50 PM" because it has a window
        // wide enough to spend on it. This pane is a few hundred points across,
        // and a date column that leaves a folder called Library rendered as "L"
        // has its priorities backwards. The year appears only when it is not
        // this one, which is when it carries information.
        let sameYear = calendar.component(.year, from: date)
            == calendar.component(.year, from: now)
        return date.formatted(
            .dateTime.month(.abbreviated).day()
                .year(sameYear ? .omitted : .defaultDigits)
        )
    }
}

/// Reads `du -k` output, which is what both Macs and Linux answer with.
nonisolated enum DiskUsageParser {
    /// - Parameter output: lines of "<kilobytes>\t<path>".
    /// - Parameter parent: the folder being listed, so it can be dropped — `du`
    ///   reports the directory it was asked about alongside its children, and
    ///   including it would list the folder inside itself.
    static func entries(
        from output: String,
        parent: String,
        directories: Set<String> = []
    ) -> [FolderEntry] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> FolderEntry? in
                let parts = line.split(separator: "\t", maxSplits: 1)
                guard parts.count == 2,
                      let kilobytes = Double(parts[0].trimmingCharacters(in: .whitespaces))
                else {
                    return nil
                }
                let path = String(parts[1])
                guard path != parent, !path.isEmpty else { return nil }

                return FolderEntry(
                    name: (path as NSString).lastPathComponent,
                    path: path,
                    sizeBytes: kilobytes * 1_024,
                    // `du` walks directories, so anything it reports is one
                    // unless the caller has learned otherwise.
                    isDirectory: directories.isEmpty || directories.contains(path)
                )
            }
    }
}
