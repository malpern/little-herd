import Foundation

/// An agent this account can actually run, and where.
///
/// Absolute paths, never the PATH. Measured across the herd: not one machine
/// has `claude` or `codex` on the PATH a non-interactive ssh shell sees, and
/// all three have working binaries — inside an application bundle on the Macs,
/// in `~/.local/bin` on the linux box. A probe asking `command -v` would report
/// an empty herd and be wrong about every machine in it.
nonisolated struct AgentInstallation: Equatable, Sendable {
    let provider: AgentTaskProvider
    let version: String
    let path: String
}

nonisolated enum AgentInstallOutputParser {
    static func parse(_ output: String) -> [AgentInstallation] {
        var best: [AgentTaskProvider: AgentInstallation] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let install = parseLine(line) else { continue }
            // A machine can have several copies — the mini carries 2.1.234 in
            // ~/.local/bin and 2.1.221 inside an application bundle. The newer
            // one is the one worth reporting and the one a transfer should use.
            if let existing = best[install.provider],
               !isNewer(install.version, than: existing.version) {
                continue
            }
            best[install.provider] = install
        }
        return best.values.sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    private static func parseLine(_ line: Substring) -> AgentInstallation? {
        let fields = line.split(
            separator: "\t",
            maxSplits: 2,
            omittingEmptySubsequences: false
        )
        guard fields.count == 3,
              fields[0].hasPrefix("agent_install="),
              let provider = AgentTaskProvider(
                  rawValue: String(fields[0].dropFirst("agent_install=".count))
              ),
              let version = decode(fields[1]),
              let path = decode(fields[2]),
              !version.isEmpty,
              !path.isEmpty
        else {
            return nil
        }
        return AgentInstallation(
            provider: provider,
            version: version,
            path: path
        )
    }

    /// Compared piece by piece as numbers, so 2.1.9 does not outrank 2.1.221 —
    /// which is the comparison a string would make and the version pair the
    /// mini actually has.
    static func isNewer(_ candidate: String, than existing: String) -> Bool {
        let left = numbers(candidate)
        let right = numbers(existing)
        for index in 0 ..< max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }

    private static func decode(_ value: Substring) -> String? {
        guard let data = Data(base64Encoded: String(value)) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Whether a machine could host a session, and if not, which reason.
///
/// Capability is measured and intent is chosen, and they are different
/// questions: a machine can be perfectly able to host a session and still be
/// one you would rather it did not. Saying which is which matters, because
/// only one of them has a fix in this app — the same reason
/// `RemoteUnavailability` distinguishes a name that will not resolve from a key
/// that was refused.
nonisolated enum DestinationEligibility: Equatable, Sendable {
    case eligible(AgentInstallation)
    /// Capable, but switched off for this machine.
    case excluded
    /// No agent this account can run, whatever the PATH says.
    case noAgent
    /// No git, so nothing could be fetched even if an agent were there.
    case noGit
    /// Not asked yet, or the machine is not answering.
    case unknown

    var isEligible: Bool {
        if case .eligible = self { return true }
        return false
    }

    /// One line, in the vocabulary of the thing that would fix it.
    var detail: String {
        switch self {
        case .eligible(let install):
            "Can host a session — \(install.provider.rawValue) \(install.version)"
        case .excluded:
            "Excluded here. Turn this machine on as a destination in Settings."
        case .noAgent:
            "No agent Little Herd can run on this machine."
        case .noGit:
            "No git on this machine, so it could not fetch the work."
        case .unknown:
            "Not measured yet."
        }
    }

    static func resolve(
        installations: [AgentInstallation],
        hasGit: Bool,
        isAllowed: Bool,
        hasReported: Bool
    ) -> DestinationEligibility {
        guard hasReported else { return .unknown }
        // Intent is checked first, and deliberately: a machine you have said
        // no to should read as "excluded", not as a list of things it lacks.
        // The second is true and beside the point, and would invite someone to
        // fix a machine they had already decided about.
        guard isAllowed else { return .excluded }
        guard hasGit else { return .noGit }
        guard let install = installations.max(by: {
            AgentInstallOutputParser.isNewer($1.version, than: $0.version)
        }) else {
            return .noAgent
        }
        return .eligible(install)
    }
}
