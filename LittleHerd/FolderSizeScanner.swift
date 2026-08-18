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

        // Say how many there are the moment they are known. Otherwise the
        // first batch — which can contain /System — leaves a spinner on screen
        // for minutes with nothing to say how long it might last.
        onProgress([], FolderScanProgress(measured: 0, total: children.count, elapsed: 0))

        let dates = await modificationDates(for: children.map(\.path))
        var measured: [FolderEntry] = []

        // Measured in small groups rather than one at a time. A round trip to
        // the mini costs about 90ms, which is nothing against a folder's dozen
        // children and eighty seconds of pure waiting against eight hundred of
        // them — the shape of `node_modules`, and exactly where someone would
        // drill in. Batching flattens that without giving up streaming: the
        // list still fills as it goes, just a handful of rows at a time.
        var byPath: [String: (isDirectory: Bool, name: String)] = [:]
        for child in children {
            byPath[child.path] = (
                child.isDirectory,
                (child.path as NSString).lastPathComponent
            )
        }

        for start in stride(from: 0, to: children.count, by: Self.batchSize) {
            try Task.checkCancellation()
            let batch = Array(children[start ..< min(start + Self.batchSize, children.count)])

            for try await (path, bytes) in measuredLines(paths: batch.map(\.path)) {
                try Task.checkCancellation()
                guard let known = byPath[path] else { continue }
                measured.append(
                    FolderEntry(
                        name: known.name,
                        path: path,
                        sizeBytes: bytes,
                        isDirectory: known.isDirectory,
                        modifiedAt: dates[path]
                    )
                )

                // Per child now, not per batch. The whole point: a folder that
                // finishes quickly appears immediately, even while a sibling
                // walks /System.
                let elapsed = started.duration(to: ContinuousClock().now)
                onProgress(
                    measured.sorted { $0.sizeBytes > $1.sizeBytes },
                    FolderScanProgress(
                        measured: measured.count,
                        total: children.count,
                        elapsed: TimeInterval(elapsed.components.seconds)
                            + Double(elapsed.components.attoseconds) / 1e18
                    )
                )
            }
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

    /// Large enough that round trips stop dominating, small enough that a slow
    /// member cannot hold too many others behind it. With streaming, a batch no
    /// longer gates its own results — each path reports as it finishes — so this
    /// is now only about how many round trips are paid.
    private static let batchSize = 8

    /// `du -sk` takes as many paths as you give it and prints each line the
    /// moment that path is done, so one command yields a stream of answers
    /// rather than a single verdict at the end.
    private func measuredLines(paths: [String]) -> AsyncThrowingStream<(String, Double), Error> {
        // One `du` per path, inside one shell command.
        //
        // A single `du` over many paths would be fewer processes, but it
        // full-buffers its output when writing to a pipe and so prints nothing
        // until it exits — measured: batched, /bin /sbin /usr all arrived in
        // the same millisecond; invoked separately, /usr came 160ms after the
        // others. Streaming the pipe cannot help if the writer never writes.
        //
        // A `du` that exits flushes, so each path reports as it finishes, and
        // wrapping the loop in one command keeps this to a single SSH round
        // trip — which is what the batching was for in the first place.
        // The loop runs each `du` in the background and waits on it, so a TERM
        // to the shell can pass the signal on. Terminating the shell alone
        // leaves the `du` orphaned and still walking /System — measured, after
        // quitting the app entirely.
        let command = "trap 'test -n \"$child\" && kill \"$child\" 2>/dev/null; exit 143' TERM INT; "
            + "child=''; for p in " + paths.map(quoted).joined(separator: " ")
            + "; do du -sk -x \"$p\" & child=$!; wait \"$child\"; done"
        let raw: AsyncThrowingStream<String, Error>
        switch location {
        case .local:
            raw = StreamingProcessRunner.lines(
                executablePath: "/bin/sh",
                arguments: ["-c", command],
                environment: ["LC_ALL": "C"]
            )
        case let .ssh(host, identityFile, _):
            raw = StreamingProcessRunner.lines(
                executablePath: "/usr/bin/ssh",
                arguments: SSHCommandRunner.arguments(
                    host: host,
                    command: "export LC_ALL=C\n" + command,
                    identityFile: identityFile
                )
            )
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in raw {
                        let parts = line.split(separator: "\t", maxSplits: 1)
                        guard parts.count == 2,
                              let kilobytes = Double(
                                  parts[0].trimmingCharacters(in: .whitespaces)
                              )
                        else { continue }
                        continuation.yield((String(parts[1]), kilobytes * 1_024))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
