import Foundation

/// Little Herd, asked a question from a shell.
///
/// **Why the app is also the command.** Every file a transfer runs through is
/// free of SwiftUI and AppKit, so the logic was always reachable from a command
/// line; what was missing was a door. A separate executable target would have
/// wanted the shared code in a library first — a move of sixty-odd files, and a
/// large change to make before knowing whether anybody wants this. Reading the
/// arguments before the `App` starts costs nothing and can be undone in a line.
///
/// The shape follows `attgw` and `yarm` rather than inventing one, because this
/// machine already has a convention for tools an agent drives and the value of
/// a convention is that it is the same everywhere:
///
/// - reads are automatic, writes will refuse without `--yes`
/// - `--json` on every verb
/// - **the exit code carries the contract**: `0` read or applied, `1` error,
///   `2` refused and *nothing changed*. The third exists so that "I declined"
///   cannot be read as "I did it", which is a silent wrong answer waiting to
///   happen in anything scripting this.
nonisolated enum HerdCommand {
    /// What the process should do about a set of arguments.
    enum Disposition: Equatable {
        /// Print this and exit with that code.
        case respond(output: String, code: Int32)
        /// Not a command at all — carry on and be an app.
        case launchTheApp
    }

    static let usage = """
        usage: little-herd <verb> [--json]

          machines        the machines in the herd, as configured
          sessions        agent sessions, per machine
          destinations    where a session could go, and why not

        Reads are automatic. Writes, when they exist, will print the change
        and refuse without --yes. Exit 0 read, 1 error, 2 refused.
        """

    /// **Anything that is not plainly a verb leaves the app alone.**
    ///
    /// This runs on every launch, including the ones from Finder and from the
    /// login item, and macOS passes its own arguments there — `-psn_0_…` when
    /// opened by Launch Services, `-NSDocumentRevisions…` and friends under a
    /// debugger. Treating one of those as an unknown verb would exit instead of
    /// starting, which is the whole app failing to open for the sake of a
    /// feature nobody asked for at that moment. So: a leading `-` is never a
    /// verb, and an empty argument list is never a command.
    static func disposition(for arguments: [String]) -> Disposition {
        let arguments = Array(arguments.dropFirst())
        guard let verb = arguments.first, !verb.hasPrefix("-") else {
            return .launchTheApp
        }

        let wantsJSON = arguments.contains("--json")

        switch verb {
        case "help", "--help":
            return .respond(output: usage, code: 0)
        case "machines", "sessions", "destinations":
            // The verbs are recognised here and answered by the caller, which
            // is the only part that needs to read a machine.
            return .respond(output: "", code: 0)
        default:
            _ = wantsJSON
            return .respond(
                output: "little-herd: unknown verb “\(verb)”\n\n\(usage)",
                code: 1
            )
        }
    }

    /// Whether a set of arguments asks for machine-readable output.
    static func wantsJSON(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains("--json")
    }

    /// The configured herd, as a person reads it.
    ///
    /// Deliberately the *configuration* rather than a probe: it is the one
    /// answer that needs no machine to be reachable, and a tool whose first
    /// verb hangs when the network is down teaches people not to use it.
    static func machines(
        _ configurations: [MachineConfiguration],
        json: Bool
    ) -> String {
        if json {
            let rows = configurations.map { machine in
                [
                    "id": machine.id.rawValue,
                    "name": machine.name,
                    "hostname": machine.hostname,
                    "user": machine.sshUser ?? "",
                    "local": machine.connection == .local ? "true" : "false",
                ]
            }
            return jsonArray(rows)
        }

        guard !configurations.isEmpty else { return "no machines configured" }
        let width = configurations.map(\.name.count).max() ?? 0
        return configurations.map { machine in
            let name = machine.name.padding(
                toLength: max(width, machine.name.count),
                withPad: " ",
                startingAt: 0
            )
            let address = machine.connection == .local
                ? "this Mac"
                : machine.sshDestination
            return "\(name)  \(address)"
        }.joined(separator: "\n")
    }

    /// A tiny encoder, because the alternative is making every value type
    /// `Codable` for the sake of one verb and then keeping that true.
    ///
    /// Escaping is the part worth writing rather than assuming: a machine name
    /// is whatever somebody typed, and an unescaped quote in it would produce
    /// output that parses as something else entirely.
    static func jsonArray(_ rows: [[String: String]]) -> String {
        let objects = rows.map { row in
            let fields = row.keys.sorted().map { key in
                "\"\(escape(key))\": \"\(escape(row[key] ?? ""))\""
            }
            return "  { " + fields.joined(separator: ", ") + " }"
        }
        return "[\n" + objects.joined(separator: ",\n") + "\n]"
    }

    static func escape(_ value: String) -> String {
        var escaped = ""
        for character in value.unicodeScalars {
            switch character {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default:
                if character.value < 0x20 {
                    escaped += String(format: "\\u%04x", character.value)
                } else {
                    escaped.unicodeScalars.append(character)
                }
            }
        }
        return escaped
    }
}

extension HerdCommand {
    /// The verbs that need to read something, answered here so the entry point
    /// stays a switch and nothing else.
    ///
    /// `machines` reads the same store the app writes, which is the whole of
    /// why this needs no daemon and no IPC: the herd's configuration is on
    /// disk, and both readers see it.
    static func answer(for arguments: [String], fallback: String) -> String {
        let verb = Array(arguments.dropFirst()).first ?? ""
        let json = wantsJSON(arguments)

        switch verb {
        case "machines":
            return machines(MachineConfigurationStore().machines, json: json)
        case "sessions", "destinations":
            // Both want a live probe, which is the next slice. Saying so beats
            // printing an empty list that reads like an answer.
            return "little-herd: “\(verb)” is not built yet"
        default:
            return fallback
        }
    }
}
