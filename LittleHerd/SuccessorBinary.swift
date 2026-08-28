import Foundation

/// Which agent binary a successor is allowed to be started with.
///
/// **Never the path the destination reported.** `AgentInstallation.path` is
/// parsed out of a shell script's output on the machine being asked, so a
/// machine that is compromised — or merely answering something other than what
/// we think — chooses the binary the source will then execute on it. The app
/// only prints that path today; starting a successor with it would make it an
/// execution primitive handed over by the destination.
///
/// So the reported path is treated as a claim to be checked rather than an
/// instruction to be followed: it is accepted only if it ends in a location we
/// have measured an agent working from, and rejected otherwise.
nonisolated enum SuccessorBinary {
    /// Measured, not guessed. Every one of these was run over plain ssh on a
    /// machine in this herd and answered; `/opt/homebrew/bin/codex` is
    /// deliberately absent because it does **not** — it dies with
    /// `env: node: No such file or directory` under a non-interactive shell,
    /// which is the same PATH lesson the probe already learned.
    static let allowedSuffixes: [AgentTaskProvider: [String]] = [
        .claude: ["/.local/bin/claude", "/.claude/local/claude"],
        .codex: ["/.local/bin/codex"],
    ]

    /// The path to start, or nil if the destination offered something else.
    ///
    /// Absolute paths only: a relative path would be resolved against whatever
    /// directory the successor happens to start in, which is exactly the sort
    /// of thing an attacker gets to choose.
    static func accept(
        _ reportedPath: String,
        for provider: AgentTaskProvider
    ) -> String? {
        guard reportedPath.hasPrefix("/"),
              !reportedPath.contains(".."),
              let suffixes = allowedSuffixes[provider],
              suffixes.contains(where: { reportedPath.hasSuffix($0) })
        else { return nil }
        return reportedPath
    }
}
