import Foundation

/// Measures what is taking up space on a machine, one child at a time.
///
/// The two-step shape — list the children, then measure each — is what makes a
/// slow job readable. A single `du` over the whole tree costs the same and
/// tells you nothing until it finishes; this way each folder's size lands as
/// soon as it is known, the list can be ranked while it fills, and progress is
/// a real count rather than a spinner.
///
/// Not supported on a NAS reached through DSM. `SYNO.FileStation.DirSize`
/// starts a task and then answers 599 — "no such task" — to every status call
/// on this DSM, so there is no way to read the result. Rather than ship a
/// button that spins forever, storage machines say plainly that they cannot
/// answer this. Measured against the live NAS, not assumed.
nonisolated struct FolderSizeScanner: Sendable {
    /// Where the command runs. A remote machine is reached the same way its
    /// metrics are; there is no second transport to keep in step.
    enum Location: Sendable, Equatable {
        case local
        case ssh(host: String, identityFile: String?, platform: RemotePlatform)

        /// BSD and GNU `stat` disagree on everything except what they can tell
        /// you. Verified against both machines rather than assumed.
        var statArguments: String {
            switch self {
            case .local: "-f '%m%t%N'"
            case .ssh(_, _, .macOS): "-f '%m%t%N'"
            case .ssh(_, _, .linux): "-c '%Y\t%n'"
            }
        }
    }

    let location: Location

    /// Children of `path`, largest first, delivered as each is measured.
    ///
    /// - Parameter onProgress: called after every child, so the interface can
    ///   show what is known so far rather than waiting for the whole folder.
    func scan(
        path: String,
        onProgress: @Sendable @escaping ([FolderEntry], FolderScanProgress) -> Void
    ) async throws -> [FolderEntry] {
        let started = ContinuousClock().now
        let children = try await listChildren(of: path)
        guard !children.isEmpty else {
            onProgress([], FolderScanProgress(measured: 0, total: 0, elapsed: 0))
            return []
        }

        let dates = await modificationDates(for: children.map(\.path))
        var measured: [FolderEntry] = []

        // Measured in small groups rather than one at a time. A round trip to
        // the mini costs about 90ms, which is nothing against a folder's dozen
        // children and eighty seconds of pure waiting against eight hundred of
        // them — the shape of `node_modules`, and exactly where someone would
        // drill in. Batching flattens that without giving up streaming: the
        // list still fills as it goes, just a handful of rows at a time.
        for start in stride(from: 0, to: children.count, by: Self.batchSize) {
            try Task.checkCancellation()

            let batch = Array(children[start ..< min(start + Self.batchSize, children.count)])
            let sizes = await measure(paths: batch.map(\.path))
            for child in batch {
                guard let bytes = sizes[child.path] else { continue }
                measured.append(
                    FolderEntry(
                        name: (child.path as NSString).lastPathComponent,
                        path: child.path,
                        sizeBytes: bytes,
                        isDirectory: child.isDirectory,
                        modifiedAt: dates[child.path]
                    )
                )
            }

            let elapsed = started.duration(to: ContinuousClock().now)
            onProgress(
                measured.sorted { $0.sizeBytes > $1.sizeBytes },
                FolderScanProgress(
                    measured: min(start + batch.count, children.count),
                    total: children.count,
                    elapsed: TimeInterval(elapsed.components.seconds)
                        + Double(elapsed.components.attoseconds) / 1e18
                )
            )
        }
        return measured.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - Steps

    /// Names first, sizes later. Listing is cheap — it is reading one
    /// directory — and knowing how many children there are is what turns the
    /// wait into a fraction.
    private func listChildren(of path: String) async throws -> [(path: String, isDirectory: Bool)] {
        // Two `find` runs rather than one with a per-entry shell: spawning a
        // shell for every child costs more than the listing itself on a folder
        // with hundreds of them. `-print` keeps one path per line, so names
        // containing spaces survive.
        async let directories = run(
            "find \(quoted(path)) -maxdepth 1 -mindepth 1 -type d -print"
        )
        async let files = run(
            "find \(quoted(path)) -maxdepth 1 -mindepth 1 ! -type d -print"
        )
        guard let directoryOutput = try await directories else {
            throw FolderScanError.unreadable(path)
        }
        let fileOutput = (try? await files) ?? ""

        func paths(_ output: String?) -> [String] {
            (output ?? "")
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .filter { !$0.isEmpty }
        }
        return paths(directoryOutput).map { ($0, true) }
            + paths(fileOutput).map { ($0, false) }
    }

    /// One `stat` for the whole listing rather than one per child: a folder
    /// with a hundred entries would otherwise pay a hundred round trips over
    /// SSH to learn something the filesystem hands over in a single call.
    private func modificationDates(for paths: [String]) async -> [String: Date] {
        guard !paths.isEmpty else { return [:] }
        let arguments = paths.map(quoted).joined(separator: " ")
        guard let output = try? await run("stat \(location.statArguments) \(arguments)") ?? nil
        else {
            // Dates are an enrichment, not the point. A machine that cannot
            // stat still gets its sizes.
            return [:]
        }
        var dates: [String: Date] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let seconds = Double(parts[0]) else { continue }
            dates[String(parts[1])] = Date(timeIntervalSince1970: seconds)
        }
        return dates
    }

    /// Small enough that the list still visibly fills, large enough that the
    /// round trips stop dominating.
    private static let batchSize = 8

    /// `du -sk` answers for a file as readily as a directory and takes as many
    /// paths as you give it, printing one line each — so one command serves the
    /// whole batch and there is no second code path to keep in step.
    private func measure(paths: [String]) async -> [String: Double] {
        guard !paths.isEmpty else { return [:] }
        let arguments = paths.map(quoted).joined(separator: " ")
        guard let output = try? await run("du -sk -x \(arguments)") ?? nil else {
            return [:]
        }
        var sizes: [String: Double] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2,
                  let kilobytes = Double(parts[0].trimmingCharacters(in: .whitespaces))
            else { continue }
            sizes[String(parts[1])] = kilobytes * 1_024
        }
        return sizes
    }

    private func run(_ script: String) async throws -> String? {
        switch location {
        case .local:
            return await LocalProcessRunner.run(
                executablePath: "/bin/sh",
                arguments: ["-c", script],
                environment: ["LC_ALL": "C"]
            )
        case let .ssh(host, identityFile, _):
            return try await SSHCommandRunner.run(
                host: host,
                command: "export LC_ALL=C\n" + script,
                identityFile: identityFile
            )
        }
    }

    /// Single quotes, with any embedded quote closed and reopened. Volume names
    /// here include "KeyPath Lab" and "Backups of Micah's M1" — a space and an
    /// apostrophe — so neither can be left to chance.
    private func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

nonisolated enum FolderScanError: LocalizedError, Equatable {
    case unreadable(String)
    case unsupported

    var errorDescription: String? {
        switch self {
        case .unreadable(let path):
            "Couldn’t read \(path)."
        case .unsupported:
            "This machine can’t report folder sizes."
        }
    }
}
