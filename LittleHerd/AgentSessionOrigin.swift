import Foundation

/// Where a session lives, from the registry each live one writes.
///
/// Not derivable from a transcript, which is why it is worth carrying: a
/// session dispatched by another agent and one you are typing to look
/// identical in their `.jsonl`, and they need opposite things from a person.
nonisolated struct AgentSessionOrigin: Equatable, Sendable {
    /// `interactive`, or a background/dispatched session.
    let kind: String
    /// `claude-desktop`, a terminal, and so on.
    let entrypoint: String

    var isInteractive: Bool { kind == "interactive" }
    var isDesktop: Bool { entrypoint.contains("desktop") }

    /// What to say about it, or nothing when there is nothing worth saying.
    ///
    /// An interactive session in a terminal is the ordinary case and gets no
    /// label: a mark that appears on everything tells you nothing.
    var label: String? {
        if !isInteractive { return "Dispatched" }
        if isDesktop { return "Desktop" }
        return nil
    }
}

nonisolated enum AgentLiveRegistryParser {
    /// Reads the `agent_live=` lines the probe emits, keyed by session id.
    static func parse(_ output: String) -> [String: AgentSessionOrigin] {
        var origins: [String: AgentSessionOrigin] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("agent_live=") else { continue }
            let fields = line
                .dropFirst("agent_live=".count)
                .split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 3, !fields[0].isEmpty else { continue }
            origins[String(fields[0])] = AgentSessionOrigin(
                kind: String(fields[1]),
                entrypoint: String(fields[2])
            )
        }
        return origins
    }
}
