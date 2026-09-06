import Foundation

/// `little-herd transfers` — what has been carried, and whether anyone kept it.
///
/// **Deliberately not the running app's list.** `TransferCoordinator` holds the
/// phases of transfers *this process* started, in memory, and the command line
/// is a different process — reading it would need IPC and a running app, and
/// item 15 settled that question the other way: independence from the GUI is
/// the entire point, and a tool that only works while a menu-bar app is open is
/// not the thing `ACCESS.md` describes.
///
/// So it asks the repository instead, which is where a transfer's evidence
/// actually lives and outlives every process involved. A transfer *is* a
/// branch: the departure pushes one before the destination is asked for
/// anything, and the successor pushes onto it. That makes the durable question
/// — **what has been moved and is still sitting unmerged** — answerable with no
/// daemon, no IPC, and after a reboot.
///
/// The live question ("what is running right now") is the dashboard's, and it
/// is the one that genuinely needs the app: a transfer in flight exists only as
/// a task in the process driving it.
extension HerdCommand {
    /// One transfer branch, as the repository describes it.
    nonisolated struct CarriedWork: Equatable {
        let branch: String
        let date: String
        let subject: String
        /// Whether `main` already contains it — the difference between work
        /// that was kept and work still waiting for somebody.
        let merged: Bool

        /// The branch without its `transfer/` prefix or its remote, which is
        /// the part somebody named.
        var shortName: String {
            let withoutRemote = branch.hasPrefix("origin/")
                ? String(branch.dropFirst("origin/".count))
                : branch
            return withoutRemote.hasPrefix("transfer/")
                ? String(withoutRemote.dropFirst("transfer/".count))
                : withoutRemote
        }
    }

    /// Parses `git for-each-ref` output.
    ///
    /// Tab-separated and parsed here rather than in the shell, because a commit
    /// subject can contain anything at all — including tabs — so the split is
    /// bounded to the two fields in front of it and the rest is the subject.
    static func carriedWork(
        fromRefs refs: String,
        mergedRefs: String
    ) -> [CarriedWork] {
        let merged = Set(
            mergedRefs.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        let rows = refs.split(whereSeparator: \.isNewline).compactMap { line -> CarriedWork? in
            let fields = line.split(separator: "\t", maxSplits: 2)
            guard fields.count == 3 else { return nil }
            let branch = String(fields[0])
            return CarriedWork(
                branch: branch,
                date: String(fields[1]),
                subject: String(fields[2]),
                merged: merged.contains(branch)
            )
        }

        // **One row per piece of work, not one per ref.** A branch that has
        // been pushed exists twice — `transfer/x` here and `origin/transfer/x`
        // there — and listing both reads as two transfers of the same thing. It
        // is worse than noise: the two carry *different* subjects, because the
        // successor's commit is on the remote and the local ref is still at the
        // departure, so the pair looks like one transfer that happened twice
        // and disagrees with itself.
        //
        // The refs arrive newest first, so the first of a name is the one that
        // has got furthest — which is the remote once a successor has pushed,
        // and the local one before that.
        var seen: Set<String> = []
        return rows.filter { seen.insert($0.shortName).inserted }
    }

    static func transfers(_ carried: [CarriedWork], json: Bool) -> String {
        if json {
            return jsonArray(carried.map { work in
                [
                    "branch": work.branch,
                    "name": work.shortName,
                    "date": work.date,
                    "subject": work.subject,
                    "merged": work.merged ? "true" : "false",
                ]
            })
        }
        guard !carried.isEmpty else {
            // Not an error. Nothing has been carried out of this repository,
            // which is a true and ordinary answer — unlike `destinations`,
            // where an empty result would be read as "nowhere to send it".
            return "no work has been carried out of this repository"
        }
        return carried.map { work in
            let state = work.merged ? "merged " : "waiting"
            return "\(state)  \(work.date)  \(work.shortName)\n"
                + "          \(work.subject)"
        }.joined(separator: "\n")
    }
}

extension HerdCommand {
    /// Asks git, in the repository the command was run in.
    ///
    /// **The working directory, the way `git` itself works.** A transfer branch
    /// belongs to one repository and the command has no other way to know which
    /// — the herd's sessions name several. Running it outside a checkout is a
    /// usage error rather than an empty list, because an empty list would read
    /// as "nothing has been carried" when the truth is "you are not standing
    /// anywhere".
    static func transfers(json: Bool) -> (output: String, code: Int32) {
        guard git(["rev-parse", "--git-dir"]) != nil else {
            return (
                "little-herd: run this inside a checkout — transfer branches "
                    + "belong to a repository, and this is not one",
                1
            )
        }

        let format = "%(refname:short)\t%(committerdate:short)\t%(subject)"
        let patterns = ["refs/heads/transfer", "refs/remotes/origin/transfer"]
        guard let refs = git(
            ["for-each-ref", "--sort=-committerdate", "--format=\(format)"] + patterns
        ) else {
            return ("little-herd: could not read this repository's branches", 1)
        }
        // Merged into whatever this repository calls its trunk. Asked of the
        // same refs so the two answers cannot describe different branches.
        let merged = git(
            ["for-each-ref", "--merged", "main", "--format=%(refname:short)"] + patterns
        ) ?? ""

        return (
            transfers(carriedWork(fromRefs: refs, mergedRefs: merged), json: json),
            0
        )
    }

    /// One git call, with no shell in front of it: the arguments are a list, so
    /// nothing here has to think about quoting.
    private static func git(_ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
