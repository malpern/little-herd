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

/// Runs `codex cloud list` wherever Codex actually is.
///
/// **Codex is not on `PATH` here, and looking for it there finds nothing.** On this Mac
/// it lives inside the ChatGPT and Codex application bundles; on the mini it is a
/// standalone binary in `~/.local/bin`. The probe already knows how to find an agent, so
/// this asks the same places in the same order and takes the first that answers.
nonisolated enum CodexCloudReader {
    static var candidatePaths: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/.local/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
        ]
    }

    static func list(limit: Int = 20) -> String {
        guard let binary = candidatePaths.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) else { return "" }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["cloud", "list", "--limit", String(limit)]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
