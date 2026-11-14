import Foundation

/// `little-herd cloud` — work sitting in Codex Cloud, and where it could land.
///
/// **The two vendors are shown differently on purpose.** Codex cloud tasks can be
/// listed, so they are rows. Claude cloud cannot be enumerated from here at all, so it
/// gets a sentence rather than an empty table — saying "no Claude cloud sessions" would
/// be a claim this app cannot make.
nonisolated extension HerdCommand {
    static func cloud(
        tasks: [CodexCloudTask],
        herd: [DestinationAccount],
        json: Bool
    ) -> String {
        if json {
            return jsonArray(tasks.map { task in
                let takers = CodexCloudPlacement.candidates(for: task, in: herd)
                    .filter(\.canTake).map(\.machine)
                var row = [
                    "id": task.id, "status": task.status.rawValue, "title": task.title,
                    "repository": task.repository, "when": task.when,
                    "can_land_on": takers.joined(separator: ","),
                ]
                if case .changes(let a, let r, let f) = task.diff {
                    row["added"] = String(a); row["removed"] = String(r); row["files"] = String(f)
                }
                return row
            })
        }

        guard !tasks.isEmpty else {
            return "no Codex cloud tasks\n\n" + claudeNote
        }
        var lines: [String] = []
        for task in tasks {
            lines.append("\(task.status.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(task.title)")
            let diff: String
            switch task.diff {
            case .none: diff = "no diff"
            case .changes(let a, let r, let f): diff = "+\(a)/-\(r) in \(f) file\(f == 1 ? "" : "s")"
            case .unreadable(let text): diff = text
            }
            lines.append("         \(task.repository)  ·  \(task.when)  ·  \(diff)")
            let takers = CodexCloudPlacement.candidates(for: task, in: herd).filter(\.canTake)
            lines.append(
                takers.isEmpty
                    // Naming the slug is the actionable half: it says what to clone.
                    ? "         nowhere to apply it — no machine has a checkout of \(task.repositorySlug)"
                    : "         apply on: \(takers.map(\.machine).joined(separator: ", "))"
            )
            lines.append("")
        }
        lines.append(claudeNote)
        return lines.joined(separator: "\n")
    }

    /// Said rather than shown, because it cannot be shown.
    static var claudeNote: String {
        "Claude cloud sessions cannot be listed from here — nothing enumerates them.\n"
            + "Pull one onto a machine by id with the vendor's own command."
    }
}

/// Runs the local Codex CLI, with a text fallback for builds that lack `--json`.
nonisolated enum CodexCloudReader {
    static func list(limit: Int = 20, binary: String? = nil) -> [CodexCloudTask]? {
        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("little-herd-cloud-\(UUID().uuidString)", isDirectory: true)
        // Codex Cloud writes error.log in its working directory even on success.
        // Use a private directory so a read never leaves that log in a checkout.
        do {
            try FileManager.default.createDirectory(
                at: workingDirectory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let command = binary.map { "exec \(RemoteShell.quoted($0)) \"$@\"" }
            ?? CodexInstallationPaths.execCommand(arguments: "\"$@\"")
        let arguments = ["cloud", "list", "--limit", String(limit)]
        let stderrURL = workingDirectory.appendingPathComponent("stderr")
        guard FileManager.default.createFile(atPath: stderrURL.path, contents: nil),
              let errors = try? FileHandle(forWritingTo: stderrURL)
        else { return nil }
        defer { try? errors.close() }

        if let output = run(command, arguments + ["--json"], in: workingDirectory, errors: errors) {
            return CodexCloudListParser.parseJSON(output)
        }

        let diagnostic = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
        guard diagnostic.contains("unexpected argument '--json'")
            || diagnostic.contains("unknown option '--json'")
        else { return nil }
        return run(command, arguments, in: workingDirectory, errors: errors)
            .map(CodexCloudListParser.parse)
    }

    private static func run(
        _ command: String, _ arguments: [String], in directory: URL, errors: FileHandle
    ) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command, "little-herd"] + arguments
        process.currentDirectoryURL = directory
        process.standardOutput = pipe
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let watchdog = ProbeWatchdog(process: process, after: 30)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let timedOut = watchdog.finish()
        guard !timedOut, process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
