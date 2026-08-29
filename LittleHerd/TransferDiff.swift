import Foundation

/// What a transfer actually changed.
///
/// The point of the whole feature is that work happened somewhere else, and
/// until you can read it you are trusting a green tick. A red run needs this
/// more than a green one: the edits are on the branch either way, and when the
/// tests did not pass they are the only thing there is to go on.
nonisolated struct TransferDiff: Equatable {
    struct File: Equatable, Identifiable {
        let path: String
        /// Nil for a binary file, which git counts in neither direction.
        let added: Int?
        let removed: Int?

        var id: String { path }
        var isBinary: Bool { added == nil }
    }

    let files: [File]
    let patch: String

    var isEmpty: Bool { files.isEmpty }
    var addedTotal: Int { files.compactMap(\.added).reduce(0, +) }
    var removedTotal: Int { files.compactMap(\.removed).reduce(0, +) }

    /// "3 files · +48 −12", or the honest alternative.
    var summary: String {
        guard !files.isEmpty else { return "No changes" }
        let count = files.count == 1 ? "1 file" : "\(files.count) files"
        return "\(count) · +\(addedTotal) −\(removedTotal)"
    }
}

/// Why a diff could not be read, in words a person can act on.
nonisolated struct TransferDiffFailure: Error, Equatable {
    let message: String
}

nonisolated enum TransferDiffReader {
    /// What to run, in order, to read a transfer's result.
    ///
    /// **Against the commit the source pushed, not against the branch's
    /// parent.** The branch carries the departure commit too — the brief and
    /// whatever was uncommitted when the session left — and diffing from its
    /// parent would show that as though the agent had written it. What the
    /// agent did is everything after the departure.
    ///
    /// Read on the machine the work came *from*: it has the repository, it is
    /// where somebody is sitting, and it means the destination can be asleep
    /// by the time anybody looks.
    static func commands(
        repository: String,
        branch: String,
        since departure: String
    ) -> [[String]] {
        [
            ["git", "-C", repository, "fetch", "--quiet", "origin", branch],
            ["git", "-C", repository, "diff", "--numstat", "\(departure)..FETCH_HEAD"],
            ["git", "-C", repository, "diff", "\(departure)..FETCH_HEAD"],
        ]
    }

    /// `--numstat` rather than `--stat`: three tab-separated fields instead of
    /// a drawn bar chart that has to be un-drawn to get the numbers back.
    static func parse(numstat: String, patch: String) -> TransferDiff {
        let files = numstat
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> TransferDiff.File? in
                let fields = line.split(separator: "\t", maxSplits: 2)
                guard fields.count == 3 else { return nil }
                // A binary file is reported as "-\t-\tpath".
                return TransferDiff.File(
                    path: String(fields[2]),
                    added: Int(fields[0]),
                    removed: Int(fields[1])
                )
            }
        return TransferDiff(files: files, patch: patch)
    }
}
