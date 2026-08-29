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

/// Whether a Mac's Bluetooth is on, as the probe reported it.
///
/// Carried because it is the **one** readable precondition for a shared
/// pointer between two Macs, and because "the pointer will not cross" is
/// otherwise a silence with four possible causes.
nonisolated enum BluetoothStateParser {
    static func parse(_ output: String) -> Bool? {
        for line in output.split(whereSeparator: \.isNewline)
        where line.hasPrefix("bluetooth=") {
            let value = line.dropFirst("bluetooth=".count)
            if value == "On" { return true }
            if value == "Off" { return false }
            // "unknown" is not "off": a machine that could not be asked must
            // not be reported as misconfigured.
            return nil
        }
        return nil
    }
}
