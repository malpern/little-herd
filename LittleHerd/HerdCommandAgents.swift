import Foundation

/// `little-herd agents` — what each machine has installed, and where the herd disagrees
/// with itself.
///
/// **The half of item 7 the dashboard deliberately gave up.** The AI page used to list a
/// machine's installed agents above its sessions, and that was removed for a good
/// reason: which agents are installed is a fact about the *machine*, not about the work,
/// and it was the first thing on a page you open to see what is running.
///
/// But removing it left a question nobody could answer. You could learn that the Air is
/// on one Codex build and the mini on another by opening two pages and remembering; you
/// could not learn how many builds the herd was running. That is a herd-level question,
/// and the command line is the herd-level surface — which is what this verb is for. It
/// belongs here rather than back on the page it was taken off.
extension HerdCommand {
    /// One machine's answer.
    nonisolated struct AgentRow: Equatable {
        let machine: String
        /// Empty when the machine answered and has nothing Little Herd can run; nil
        /// when it did not answer at all. A sleeping Mac is the second, and reporting
        /// the two the same way would be a lie about one of them.
        let installations: [AgentInstallation]?
        /// Whether this machine could carry an agent at all. Storage cannot, so it has
        /// no agents by design rather than by failure, and calling that "not answering"
        /// reads as a fault when it is the intended state.
        ///
        /// **Not `mayHostSessions`** — that is a per-machine preference and reads false
        /// on every machine here, which made every row say "not a destination". What is
        /// wanted is what the machine *is*, not what it has been allowed to do.
        var couldCarryAnAgent: Bool = true
    }

    /// Where the herd disagrees with itself about one provider.
    nonisolated struct Drift: Equatable {
        let provider: String
        /// Newest first, each with the machines carrying it.
        let versions: [(version: String, machines: [String])]

        static func == (a: Drift, b: Drift) -> Bool {
            a.provider == b.provider
                && a.versions.map(\.version) == b.versions.map(\.version)
                && a.versions.map(\.machines) == b.versions.map(\.machines)
        }
    }

    /// Which providers are on more than one version, and who has what.
    ///
    /// Sorted by version descending so the newest reads first, which is the order the
    /// question "is this machine behind" wants. A provider on one version everywhere is
    /// not drift and is left out — the point is disagreement.
    static func drift(in rows: [AgentRow]) -> [Drift] {
        var byProvider: [String: [String: [String]]] = [:]
        for row in rows {
            for install in row.installations ?? [] {
                byProvider[install.providerName, default: [:]][install.version, default: []]
                    .append(row.machine)
            }
        }
        return byProvider.compactMap { provider, versions -> Drift? in
            guard versions.count > 1 else { return nil }
            let ordered = versions
                .map { (version: $0.key, machines: $0.value.sorted()) }
                .sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
            return Drift(provider: provider, versions: ordered)
        }
        .sorted { $0.provider < $1.provider }
    }

    static func agents(_ rows: [AgentRow], json: Bool) -> String {
        if json {
            return jsonArray(rows.flatMap { row -> [[String: String]] in
                guard row.couldCarryAnAgent else {
                    return [["machine": row.machine, "storage": "true"]]
                }
                guard let installations = row.installations else {
                    return [["machine": row.machine, "storage": "false", "answered": "false"]]
                }
                if installations.isEmpty {
                    return [["machine": row.machine, "answered": "true", "agents": "none"]]
                }
                return installations.map {
                    [
                        "machine": row.machine, "answered": "true",
                        "agent": $0.providerName, "version": $0.version, "path": $0.path,
                    ]
                }
            })
        }

        guard !rows.isEmpty else { return "no machines configured" }
        let width = rows.map(\.machine.count).max() ?? 0
        var lines = rows.map { row -> String in
            let name = row.machine.padding(toLength: width, withPad: " ", startingAt: 0)
            guard row.couldCarryAnAgent else { return "\(name)  storage — no agents" }
            guard let installations = row.installations else { return "\(name)  not answering" }
            guard !installations.isEmpty else { return "\(name)  nothing Little Herd can run" }
            let what = installations
                .sorted { $0.providerName < $1.providerName }
                .map { "\($0.providerName) \($0.version)" }
                .joined(separator: "   ")
            return "\(name)  \(what)"
        }

        let drifting = drift(in: rows)
        if !drifting.isEmpty {
            lines.append("")
            for d in drifting {
                let spread = d.versions
                    .map { "\($0.version) (\($0.machines.joined(separator: ", ")))" }
                    .joined(separator: ", ")
                lines.append("\(d.provider) is on \(d.versions.count) versions: \(spread)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Builds the rows from a sample.
    static func agentRows(
        from sampled: [(MachineConfiguration, SystemSnapshot?)]
    ) -> [AgentRow] {
        sampled.map { configuration, snapshot in
            AgentRow(
                machine: configuration.name,
                installations: snapshot?.destination?.installations,
                couldCarryAnAgent: !configuration.isStorage
            )
        }
    }
}
