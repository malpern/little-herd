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
        case ssh(host: String, identityFile: String?)
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

        var measured: [FolderEntry] = []
        for child in children {
            // Cancelling has to be felt between children rather than only at
            // the end: the whole point of measuring one at a time is that the
            // work can be abandoned partway without waiting minutes for a
            // single command to give up.
            try Task.checkCancellation()

            if let entry = try? await measure(path: child.path, isDirectory: child.isDirectory) {
                measured.append(entry)
            }
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

    /// `du -sk` answers for a file as readily as a directory, so one command
    /// serves both and there is no second code path to keep in step.
    private func measure(path: String, isDirectory: Bool) async throws -> FolderEntry {
        guard let output = try await run("du -sk -x \(quoted(path))"),
              let kilobytes = output
                  .split(whereSeparator: \.isNewline).first?
                  .split(separator: "\t").first
                  .flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) })
        else {
            throw FolderScanError.unreadable(path)
        }
        return FolderEntry(
            name: (path as NSString).lastPathComponent,
            path: path,
            sizeBytes: kilobytes * 1_024,
            isDirectory: isDirectory
        )
    }

    private func run(_ script: String) async throws -> String? {
        switch location {
        case .local:
            return await LocalProcessRunner.run(
                executablePath: "/bin/sh",
                arguments: ["-c", script],
                environment: ["LC_ALL": "C"]
            )
        case let .ssh(host, identityFile):
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
