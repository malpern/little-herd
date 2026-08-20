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

    /// The provider's name as a person writes it, for a sentence rather than
    /// a key. The raw value is lowercase because it is what the shell prints.
    var providerName: String { String(localized: provider.displayName) }
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
              let rawVersion = decode(fields[1]),
              let path = decode(fields[2]),
              case let version = versionNumber(in: rawVersion),
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

    /// The number alone, out of whatever else the agent prints beside it.
    ///
    /// Every one of these was measured by running the command rather than read
    /// off a table, and no two agree:
    ///
    ///     claude  2.1.234 (Claude Code)                       number first
    ///     codex   codex-cli 0.148.0-alpha.15                  name first
    ///     codex   mise …/config.toml tools: codex@0.147.0     a shim's banner
    ///
    /// The first version of this took the first token, which is right for
    /// Claude and gives "codex-cli" for Codex — a version column reading
    /// `codex-cli`, and a skew comparison that then found every real version
    /// newer than it. So the rule is the first token that *starts with a
    /// digit*, and the shim's banner is stripped in the probe before it gets
    /// here. Anything unrecognisable is passed through whole rather than
    /// dropped: a version nobody can parse is still worth showing.
    static func versionNumber(in raw: String) -> String {
        let tokens = raw.split(whereSeparator: \.isWhitespace)
        let numeric = tokens.first { $0.first?.isNumber == true }
        return String(numeric ?? tokens.first ?? "")
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
/// one you would rather it did not. Saying which is which matters, because the
/// three answers have three different fixes and only one of them is a
/// preference — the same reason `RemoteUnavailability` distinguishes a name
/// that will not resolve from a key that was refused.
nonisolated enum DestinationEligibility: Equatable, Sendable {
    case eligible(AgentInstallation)
    /// Capable, perhaps, but not offered. A choice, not a lack.
    case excluded
    /// No agent this account can run, whatever the PATH says.
    case noAgent
    /// The agent is here and the repository is not, so there would be nothing
    /// to fetch the work into. Git itself needs no separate check: an account
    /// with a checkout has git, and one without it has nowhere to put a
    /// transfer branch whether git is installed or not.
    case noCheckout(repository: String)
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
            "Can host a session — \(install.providerName) \(install.version)"
        case .excluded:
            "Excluded here — turn it on in Settings."
        case .noAgent:
            "No agent Little Herd can run here."
        case .noCheckout(let repository):
            "No checkout of \(repository) here."
        case .unknown:
            "Not measured yet."
        }
    }

    /// The glyph for the reason, so a list of destinations can be read down
    /// its leading edge. A switched-off machine is not a fault and does not
    /// get a fault's symbol.
    var symbolName: String {
        switch self {
        case .eligible: "checkmark.circle"
        case .excluded: "minus.circle"
        case .noAgent: "questionmark.circle"
        case .noCheckout: "arrow.trianglehead.branch"
        case .unknown: "clock"
        }
    }

    /// - Parameters:
    ///   - report: what the account last said about itself, or nil if it has
    ///     not been asked. A machine Little Herd cannot run a probe on — a NAS
    ///     reached through DSM — never reports, and never being asked is not
    ///     the same as answering no.
    ///   - repository: the repository the work is in, by the slug of its
    ///     origin remote. Nil where the question is about the account alone,
    ///     as it is in Settings.
    ///   - isAllowed: `MachineConfiguration.mayHostSessions`.
    static func resolve(
        report: DestinationReport?,
        repository: String?,
        isAllowed: Bool
    ) -> DestinationEligibility {
        // Intent is checked first, and deliberately: a machine you have said
        // no to should read as "excluded", not as a list of things it lacks.
        // The second is true and beside the point, and would invite someone to
        // fix a machine they had already decided about.
        guard isAllowed else { return .excluded }
        guard let report else { return .unknown }
        guard let install = report.bestInstallation else { return .noAgent }
        // Last, because it is the only one of the three that depends on which
        // work is being moved rather than on the account itself.
        if let repository, !repository.isEmpty,
           report.checkouts[repository] == nil {
            return .noCheckout(repository: repository)
        }
        return .eligible(install)
    }
}

/// What an account last said about its own ability to host a session.
///
/// Absent rather than empty when the account has not been asked. An empty
/// report is a real measurement — "asked, and it has nothing" — and reads as
/// `.noAgent`; a missing one reads as `.unknown`, which is the difference
/// between a machine that cannot host work and one nobody has checked.
nonisolated struct DestinationReport: Equatable, Sendable {
    let installations: [AgentInstallation]
    /// Repository slug to the directory it is checked out in. Keyed by the
    /// origin remote's slug because that is what identifies a repository —
    /// this herd has `keyboard-newswire` in a folder called `keyboard-wire`.
    let checkouts: [String: String]

    init(
        installations: [AgentInstallation],
        checkouts: [String: String]
    ) {
        self.installations = installations
        self.checkouts = checkouts
    }

    /// The newest agent here, which is the one a transfer would start.
    var bestInstallation: AgentInstallation? {
        installations.max {
            AgentInstallOutputParser.isNewer($1.version, than: $0.version)
        }
    }
}

/// One account, as the herd-level questions see it.
///
/// An account and not a machine: the home directory decides which repositories
/// exist, the agent install is per-user, and so are the credentials. The mini
/// has two accounts and they are not interchangeable.
nonisolated struct DestinationAccount: Equatable, Identifiable, Sendable {
    let machine: MachineID
    let name: String
    let symbolName: String
    let report: DestinationReport?
    let mayHostSessions: Bool

    var id: MachineID { machine }
}

nonisolated struct DestinationCandidate: Equatable, Identifiable, Sendable {
    let account: DestinationAccount
    let eligibility: DestinationEligibility

    var id: MachineID { account.machine }
    var name: String { account.name }
    var symbolName: String { account.symbolName }
}

/// Where a piece of work could go, and what each of the other accounts is
/// missing.
nonisolated enum DestinationRoster {
    /// - Parameters:
    ///   - repository: the slug of the repository the work is in. Nil where
    ///     the work is not in one, and then the checkout question cannot be
    ///     asked of anybody.
    ///   - origin: the account the work is already on, which is not a
    ///     destination for itself.
    static func candidates(
        among accounts: [DestinationAccount],
        forRepository repository: String?,
        excluding origin: MachineID?
    ) -> [DestinationCandidate] {
        let candidates = accounts
            .filter { $0.machine != origin }
            .map { account in
                DestinationCandidate(
                    account: account,
                    eligibility: DestinationEligibility.resolve(
                        report: account.report,
                        repository: repository,
                        isAllowed: account.mayHostSessions
                    )
                )
            }

        // Somewhere the work could actually go comes first; the reasons the
        // others could not are the answer to a second question, and burying a
        // usable destination underneath them would make the list read as bad
        // news when it is not. Ties keep the herd's own order, so the list does
        // not rearrange itself between samples.
        return candidates.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.eligibility.isEligible
                    != rhs.element.eligibility.isEligible {
                    return lhs.element.eligibility.isEligible
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Whether the whole list would say one sentence three times.
    ///
    /// Which is what it does before anyone has chosen a destination, and a
    /// panel that repeats itself down a column teaches people to stop reading
    /// the column. Say it once instead: the reason is the same for every row
    /// and so is the fix.
    static func isEntirelyUnchosen(_ candidates: [DestinationCandidate]) -> Bool {
        !candidates.isEmpty && candidates.allSatisfy { $0.eligibility == .excluded }
    }
}

/// One installed agent, set against the newest copy of it in the herd.
///
/// Version skew here is not an incident, it is the standing condition — Codex
/// is three different builds across three machines and has been for as long as
/// anyone has looked. So this marks the copies that are behind rather than
/// announcing skew as news: a banner that is always lit is read once and never
/// again, and the moment the difference matters is the moment you are looking
/// at the machine it is on.
nonisolated struct AgentVersionReport: Equatable, Identifiable, Sendable {
    /// Where the newest copy in the herd is, when it is not this one.
    nonisolated struct Newer: Equatable, Sendable {
        let version: String
        let accountName: String
    }

    let installation: AgentInstallation
    let newer: Newer?

    var id: String { installation.provider.rawValue }

    /// The path, with the home directory folded back to `~`.
    ///
    /// Claude on a Mac lives five levels inside "Application Support" and the
    /// full path is longer than this pane is wide; what the line is for is
    /// saying *which* copy answered, and the tail carries that.
    func shortPath(home: String = NSHomeDirectory()) -> String {
        let path = installation.path
        guard !home.isEmpty, path.hasPrefix(home) else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

nonisolated enum AgentVersionReader {
    /// What one account has installed, and which of it the herd has newer.
    ///
    /// Only what is installed here: an agent this account lacks entirely is a
    /// different statement, and `DestinationEligibility` already makes it.
    static func reports(
        for account: MachineID,
        among accounts: [DestinationAccount]
    ) -> [AgentVersionReport] {
        guard let mine = accounts.first(where: { $0.machine == account })?.report
        else {
            return []
        }

        return mine.installations
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
            .map { installation in
                AgentVersionReport(
                    installation: installation,
                    // Compared against the whole herd including this
                    // account. Filtering itself out reads as the careful
                    // thing and cannot change the answer — the comparison is
                    // strict, so a version is never newer than itself — and a
                    // guard that cannot bind still has to be understood by
                    // everyone who reads it. Established by deleting it and
                    // watching the suite stay green.
                    newer: newest(
                        of: installation.provider,
                        beating: installation.version,
                        among: accounts
                    )
                )
            }
    }

    private static func newest(
        of provider: AgentTaskProvider,
        beating version: String,
        among others: [DestinationAccount]
    ) -> AgentVersionReport.Newer? {
        var best: AgentVersionReport.Newer?
        for other in others {
            guard let candidate = other.report?.installations
                .first(where: { $0.provider == provider })
            else {
                continue
            }
            guard AgentInstallOutputParser.isNewer(candidate.version, than: version)
            else {
                continue
            }
            // Ties keep the herd's order rather than the last one seen, so the
            // line names the same machine on every sample.
            if let current = best,
               !AgentInstallOutputParser.isNewer(
                   candidate.version,
                   than: current.version
               ) {
                continue
            }
            best = AgentVersionReport.Newer(
                version: candidate.version,
                accountName: other.name
            )
        }
        return best
    }
}
