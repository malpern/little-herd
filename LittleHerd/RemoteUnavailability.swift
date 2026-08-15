import Foundation

/// Why a remote machine could not be reached, in terms a person can act on.
///
/// "Unavailable" is true but useless: a machine that is powered off, one whose
/// name stopped resolving because a VPN dropped, and one refusing your key all
/// look identical, and the second is by far the most common — and the one where
/// the machine is fine and the Mac reading it is not. `ssh` already says which
/// it is on standard error; this turns that into something the interface can
/// show without making the user open a terminal to find out.
nonisolated enum RemoteUnavailability: Equatable, Sendable {
    /// The host name resolved to nothing at all.
    case nameNotFound
    /// Resolved, but nothing answered in time.
    case noAnswer
    /// Something answered and actively refused the connection.
    case refused
    /// Reachable, but SSH would not accept the key.
    case keyRejected
    /// The host's key changed — refused for safety, not a network problem.
    case hostKeyChanged
    /// Reached the machine, but the metrics command came back incomplete.
    case incompleteOutput
    /// The configured host name is not usable as an SSH destination.
    case unusableHostName
    /// Anything else; carries ssh's own first line so nothing is swallowed.
    case other(String)

    /// A short line for a status row.
    var summary: LocalizedStringResource {
        switch self {
        case .nameNotFound: "Name not found"
        case .noAnswer: "No answer"
        case .refused: "Connection refused"
        case .keyRejected: "Key rejected"
        case .hostKeyChanged: "Host key changed"
        case .incompleteOutput: "Incomplete data"
        case .unusableHostName: "Bad host name"
        case .other: "Unavailable"
        }
    }

    /// A fuller sentence for a tooltip, naming the likely cause where there is
    /// one worth naming.
    func detail(host: String) -> LocalizedStringResource {
        switch self {
        case .nameNotFound:
            "“\(host)” doesn’t resolve to an address. The machine may be fine — check whether a VPN such as Tailscale is disconnected on this Mac."
        case .noAnswer:
            "“\(host)” resolved, but nothing answered. The machine is likely asleep or off the network."
        case .refused:
            "“\(host)” answered but refused the connection. Remote Login may be turned off, or SSH is not listening on the interface being used."
        case .keyRejected:
            "“\(host)” refused the SSH key. Check that this Mac’s public key is in that machine’s authorized_keys."
        case .hostKeyChanged:
            "“\(host)” presented a different host key, so the connection was refused. Verify the machine was genuinely rebuilt before clearing the old key."
        case .incompleteOutput:
            "“\(host)” connected but returned incomplete metrics. Its shell tools may differ from what Little Herd expects."
        case .unusableHostName:
            "“\(host)” isn’t a usable SSH host name, so no connection was attempted."
        case let .other(message):
            "“\(host)” could not be reached: \(message)"
        }
    }

    /// Classifies an ssh failure from what ssh itself printed.
    ///
    /// Matching on message text is inherently fragile, so anything unrecognised
    /// falls through to `.other` carrying the original line rather than being
    /// discarded or guessed at.
    static func classify(_ error: any Error) -> RemoteUnavailability {
        guard let remote = error as? RemoteMonitorError else {
            return .other(error.localizedDescription)
        }

        switch remote {
        case .invalidHost:
            return .unusableHostName
        case .invalidOutput:
            return .incompleteOutput
        case let .commandFailed(message):
            return classify(standardError: message)
        }
    }

    static func classify(standardError: String) -> RemoteUnavailability {
        let text = standardError.lowercased()

        if text.contains("could not resolve hostname")
            || text.contains("nodename nor servname")
            || text.contains("name or service not known")
        {
            return .nameNotFound
        }
        if text.contains("operation timed out")
            || text.contains("connection timed out")
            || text.contains("timed out")
            || text.contains("no route to host")
            || text.contains("host is down")
            || text.contains("network is unreachable")
        {
            return .noAnswer
        }
        if text.contains("connection refused") {
            return .refused
        }
        if text.contains("permission denied")
            || text.contains("too many authentication failures")
        {
            return .keyRejected
        }
        if text.contains("host key verification failed")
            || text.contains("remote host identification has changed")
        {
            return .hostKeyChanged
        }

        let firstLine = standardError
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        guard let firstLine, !firstLine.isEmpty else {
            return .other("no error output")
        }
        return .other(firstLine)
    }
}
