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
    static func answer(
        for arguments: [String],
        fallback: String
    ) -> (output: String, code: Int32) {
        let rest = Array(arguments.dropFirst())
        let verb = rest.first ?? ""
        let json = wantsJSON(arguments)
        let configurations = MachineConfigurationStore().machines

        switch verb {
        case "machines":
            return (machines(configurations, json: json), 0)

        case "sessions":
            return (sessions(sampleBlocking(configurations), json: json), 0)

        case "destinations":
            guard let wanted = rest.dropFirst().first(where: {
                !$0.hasPrefix("-")
            }) else {
                return ("usage: little-herd destinations <session> [--json]", 1)
            }
            return destinations(
                matching: wanted,
                in: sampleBlocking(configurations),
                json: json
            )

        default:
            return (fallback, 1)
        }
    }

    /// Finds the session, then asks where it could go.
    ///
    /// **A prefix is enough to name one.** These identifiers are UUIDs, and
    /// nobody is going to type one — the app shows the first eight characters
    /// and so does `sessions`, so that is what this accepts. An ambiguous
    /// prefix is an error rather than a guess: picking one of two sessions for
    /// somebody would eventually move the wrong work.
    static func destinations(
        matching wanted: String,
        in sampled: [(MachineConfiguration, SystemSnapshot?)],
        json: Bool
    ) -> (output: String, code: Int32) {
        let found = sampled.flatMap { configuration, snapshot in
            (snapshot?.agentSessions ?? [])
                .filter { bareIdentifier($0.id).hasPrefix(wanted) || $0.id.hasPrefix(wanted) }
                .map { (configuration, $0) }
        }

        guard let (origin, session) = found.first else {
            // Nothing found is an error: a script that asked about a
            // session and got an empty list would read it as "nowhere
            // to send it", which is a different answer.
            return ("little-herd: no session starting “\(wanted)”", 1)
        }
        guard found.count == 1 else {
            let where_ = found.map { "\(shortIdentifier($0.1.id)) on \($0.0.name)" }
            return (
                "little-herd: “\(wanted)” matches \(found.count) sessions: "
                    + where_.joined(separator: ", "),
                1
            )
        }

        let herd = sampled.map { configuration, snapshot in
            DestinationAccount(
                machine: configuration.id,
                name: configuration.name,
                symbolName: "desktopcomputer",
                report: snapshot?.destination,
                mayHostSessions: configuration.mayHostSessions,
                auth: .unverified,
                isVerifying: false
            )
        }

        return (
            destinations(
                session: session,
                origin: origin.id,
                herd: herd,
                json: json
            ),
            0
        )
    }

    /// Runs an async answer from a synchronous entry point.
    ///
    /// A command-line process has no run loop to await on, and the alternative
    /// — making `main` async — starts the concurrency runtime before the
    /// argument check, which is work done on every launch of the app for the
    /// sake of two verbs.
    /// Takes one sample from a synchronous entry point.
    ///
    /// **The work handed here must not need the main actor.** This blocks the
    /// calling thread on a semaphore, and that thread is the main one — so a
    /// task that hops back to the main actor to finish would wait for a thread
    /// that is waiting for it. Only `probe` is run this way, and it touches
    /// nothing isolated; the formatting happens after, back where it started.
    nonisolated static func sampleBlocking(
        _ configurations: [MachineConfiguration]
    ) -> [(MachineConfiguration, SystemSnapshot?)] {
        let sampled = Handoff<[(MachineConfiguration, SystemSnapshot?)]>()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            sampled.value = await probe(configurations)
            semaphore.signal()
        }
        semaphore.wait()
        return sampled.value ?? []
    }

    /// One value handed from a detached task back to the thread waiting for it.
    ///
    /// **A `nonisolated(unsafe) var` captured by the task compiled here and not
    /// on CI**, whose toolchain is a release behind: "sending value of
    /// non-Sendable type '() async -> ()' risks causing data races". A local
    /// green suite is not a green build when the two compilers differ.
    ///
    /// `@unchecked` is doing real work rather than silencing a warning, and the
    /// semaphore is what earns it: the write happens before `signal`, the read
    /// after `wait`, so the two accesses cannot overlap. That ordering is the
    /// whole argument — take away the semaphore and this is unsound.
    private nonisolated final class Handoff<Value>: @unchecked Sendable {
        nonisolated(unsafe) var value: Value?
    }
}

extension HerdCommand {
    /// One sample of every machine that can be reached, taken concurrently.
    ///
    /// **The command re-probes rather than asking the running app**, which was
    /// settled before any of this was written. Independence from the GUI is the
    /// point: the app cannot run on the linux box at all, and a tool that only
    /// answers while a menu-bar app is open is not the thing `ACCESS.md`
    /// describes. The cost is a few seconds per verb, paid only when asked.
    nonisolated static func probe(
        _ configurations: [MachineConfiguration]
    ) async -> [(MachineConfiguration, SystemSnapshot?)] {
        await withTaskGroup(
            of: (Int, MachineConfiguration, SystemSnapshot?).self
        ) { group in
            for (index, configuration) in configurations.enumerated() {
                group.addTask {
                    (index, configuration, await snapshot(of: configuration))
                }
            }
            var results: [(Int, MachineConfiguration, SystemSnapshot?)] = []
            for await result in group { results.append(result) }
            // Concurrently sampled, reported in the order they were configured
            // — a list whose rows move between runs is one nobody can diff.
            return results.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2) }
        }
    }

    nonisolated private static func snapshot(
        of configuration: MachineConfiguration
    ) async -> SystemSnapshot? {
        switch configuration.connection {
        case .local:
            return await MetricsSampler().sample()
        case .ssh:
            guard let platform = configuration.remotePlatform else { return nil }
            return try? await RemoteMetricsSampler(
                host: configuration.sshDestination,
                platform: platform,
                identityFile: configuration.identityFile
            ).sample()
        case .smb, .dsm:
            // A share and a NAS have capacity and no sessions, and neither can
            // host work — DSM restricts a shell to administrators and has no
            // package manager. Nothing to probe for the verbs that exist here.
            return nil
        }
    }


    /// The part of a session's identifier a person could recognise or retype.
    ///
    /// **`id` carries the provider** — `claude:0d5f…` — so its first eight
    /// characters are all provider and no session, and every row printed the
    /// same `claude:1`. What identifies one is the transcript's own uuid, after
    /// the colon. Caught by printing real sessions rather than fixtures: the
    /// bug is invisible unless two of them are on screen together.
    static func shortIdentifier(_ id: String) -> String {
        String(bareIdentifier(id).prefix(8))
    }

    /// The identifier without its provider, which is what a prefix is matched
    /// against — nobody is going to type `claude:` first.
    static func bareIdentifier(_ id: String) -> String {
        id.split(separator: ":", maxSplits: 1).last.map(String.init) ?? id
    }

    /// The agent sessions on each machine.
    static func sessions(
        _ sampled: [(MachineConfiguration, SystemSnapshot?)],
        json: Bool
    ) -> String {
        if json {
            let rows = sampled.flatMap { configuration, snapshot in
                (snapshot?.agentSessions ?? []).map { session in
                    [
                        "machine": configuration.id.rawValue,
                        "id": session.id,
                        "short": shortIdentifier(session.id),
                        "provider": session.provider.rawValue,
                        "state": String(describing: session.state),
                        "title": session.title ?? session.projectName,
                        "directory": session.workingDirectory ?? "",
                    ]
                }
            }
            return jsonArray(rows)
        }

        var lines: [String] = []
        for (configuration, snapshot) in sampled {
            guard let snapshot else {
                // **"Not reachable" is a claim, and for a NAS it was a false
                // one.** Nothing here probes a share or a DSM box — they hold
                // capacity, run no agents, and cannot host work — so their
                // silence is this command declining to ask rather than a
                // machine failing to answer. Reporting the two the same way
                // said the Synology was down while it was serving perfectly.
                lines.append(
                    "\(configuration.name)  \(unaskedOrUnreachable(configuration))"
                )
                continue
            }
            let sessions = snapshot.agentSessions
            guard !sessions.isEmpty else {
                lines.append("\(configuration.name)  (no sessions)")
                continue
            }
            lines.append(configuration.name)
            for session in sessions {
                let state = String(describing: session.state)
                let name = session.title ?? session.projectName
                lines.append(
                    "  \(shortIdentifier(session.id))  \(state.padding(toLength: 10, withPad: " ", startingAt: 0))  \(name)"
                )
            }
        }
        return lines.isEmpty ? "no machines configured" : lines.joined(separator: "\n")
    }


    /// Why a machine produced no snapshot: because it was not asked, or
    /// because it did not answer.
    static func unaskedOrUnreachable(_ configuration: MachineConfiguration) -> String {
        switch configuration.connection {
        case .smb, .dsm: "(not asked — runs no agents)"
        case .local, .ssh: "(not reachable)"
        }
    }

    /// Where a session could go, and why not.
    ///
    /// **Answered by `TransferAssembly.request`, which is the function a drop
    /// calls.** Reimplementing the reasoning here would produce a second
    /// opinion that drifts from the first, and the whole value of this verb is
    /// that it is the answer the app would actually give.
    static func destinations(
        session: AgentSession,
        origin: MachineID,
        herd: [DestinationAccount],
        json: Bool
    ) -> String {
        let answers = herd
            .filter { $0.machine != origin }
            .map { account -> (String, String?) in
                let request = TransferAssembly.request(
                    session: session,
                    from: origin,
                    to: account.machine,
                    in: herd,
                    check: TransferAssembly.check
                )
                switch request {
                case .success: return (account.name, nil)
                case .failure(let refusal): return (account.name, reason(refusal))
                }
            }

        if json {
            return jsonArray(answers.map { name, refusal in
                [
                    "machine": name,
                    "eligible": refusal == nil ? "true" : "false",
                    "reason": refusal ?? "",
                ]
            })
        }

        guard !answers.isEmpty else { return "nowhere to send it — the herd is one machine" }
        let width = answers.map(\.0.count).max() ?? 0
        return answers.map { name, refusal in
            let padded = name.padding(toLength: width, withPad: " ", startingAt: 0)
            return "\(padded)  \(refusal ?? "can take it")"
        }.joined(separator: "\n")
    }

    /// A refusal in the fewest words that still say what to do about it.
    static func reason(_ refusal: TransferAssembly.Refusal) -> String {
        switch refusal {
        case .sessionCannotBeMoved(let why):
            TransferEligibility.explanation(for: why)
        case .destinationLacksRepository:
            "no checkout of that repository"
        case .destinationLacksAgent:
            "no agent installed"
        case .originLacksAgent:
            "this machine has no agent to write the handoff"
        case .originUnknown:
            "the session is not in a repository this machine reports"
        }
    }
}
