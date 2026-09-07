import Foundation

/// Handing the successor the departing session's own transcript, rather than a
/// summary of it.
///
/// **The brief is the transfer's weakest step by evidence.** It is the only one
/// that spends a model call on the source; it is where the first failure of
/// 6 September was; it is where the silent permission failure of 3 September
/// was, reporting success having written nothing. And its ceiling is whatever
/// an agent writes in one prompt — the successor is a *new* session holding a
/// paragraph, with no history, no tool results and no context.
///
/// A carried transcript has all three and costs a copy. Measured, not argued:
/// a session created on the Air was copied to the mini and resumed there, and
/// answered a question about its own contents that only the history could
/// answer.
///
/// **Where a transcript lives is derived from the directory it ran in**, and
/// that is the whole mechanism: `~/.claude/projects/<encoded cwd>/<id>.jsonl`,
/// where the encoding replaces every `/` and `.` with `-`.
///
/// **What that means is better than it first looked.** The obvious fear is the
/// paths inside — 5,954 records in one transcript carry an absolute `cwd`, and
/// none of them will be true on another machine. It does not matter for
/// resuming: a transcript placed under the project directory for *the
/// destination's* working directory resumes there, with its history intact,
/// while its records still describe where it used to be. Tested directly, by
/// resuming one under a deliberately mismatched path. So the carry does **not**
/// need the two machines to share a layout, which is what the first write-up of
/// this assumed and got wrong.
///
/// The paths inside are still wrong, and that is a fidelity problem rather than
/// a mechanical one: the agent remembers files at addresses that no longer
/// hold. Its prompt is what tells it where it is now, which is the same thing
/// the brief has always had to do.
nonisolated enum TranscriptCarry {
    /// Claude's own encoding of a working directory into a folder name.
    ///
    /// `/Users/x/local-code/little-herd/.claude/worktrees/w` becomes
    /// `-Users-x-local-code-little-herd--claude-worktrees-w`. The doubled dash
    /// is not a separator: it is the `/` and the `.` of `/.claude`, each
    /// becoming a dash on its own.
    static func projectDirectoryName(for workingDirectory: String) -> String {
        String(workingDirectory.map { $0 == "/" || $0 == "." ? "-" : $0 })
    }

    /// Where a session's transcript sits on the machine it ran on.
    static func transcriptPath(
        home: String,
        workingDirectory: String,
        sessionIdentifier: String
    ) -> String {
        "\(home)/.claude/projects/"
            + "\(projectDirectoryName(for: workingDirectory))/\(sessionIdentifier).jsonl"
    }

    /// The directory the carried transcript must land in on the destination,
    /// which is decided by where the successor will *run*, not by where the
    /// session used to be.
    static func destinationDirectory(
        home: String,
        successorWorkingDirectory: String
    ) -> String {
        "\(home)/.claude/projects/"
            + projectDirectoryName(for: successorWorkingDirectory)
    }
}

extension TranscriptCarry {
    /// Whether this session can be carried at all.
    ///
    /// **Only Claude, for now.** The mechanism is a file in a place derived
    /// from a directory, and that is Claude's layout. Codex keeps its rollouts
    /// somewhere else entirely and would need its own answer; claiming to carry
    /// one and quietly writing a brief instead would be worse than not
    /// offering it.
    static func canCarry(_ session: AgentSession) -> Bool {
        session.provider == .claude && session.workingDirectory?.isEmpty == false
    }

    /// Reading the transcript on the source, as one shell command.
    ///
    /// `base64` because the thing being moved is a file and the transport is a
    /// command that returns text: a transcript is JSON with newlines in it, and
    /// handing that back raw would leave the caller unpicking where the output
    /// of one command ended.
    static func readCommand(
        home: String,
        workingDirectory: String,
        sessionIdentifier: String
    ) -> String {
        let path = transcriptPath(
            home: home,
            workingDirectory: workingDirectory,
            sessionIdentifier: sessionIdentifier
        )
        // `-s` first: a transcript that does not exist, or exists empty, must
        // fail here rather than deliver nothing and let the arrival resume a
        // session that is not there. The same lesson the brief learned when it
        // reported success having written nothing.
        return "test -s \(RemoteShell.quoted(path)) && base64 < \(RemoteShell.quoted(path))"
    }

    /// Writing it on the destination, in the place the successor will look.
    static func writeCommand(
        home: String,
        successorWorkingDirectory: String,
        sessionIdentifier: String,
        base64Contents: String
    ) -> String {
        let directory = destinationDirectory(
            home: home,
            successorWorkingDirectory: successorWorkingDirectory
        )
        let file = "\(directory)/\(sessionIdentifier).jsonl"
        return "mkdir -p \(RemoteShell.quoted(directory)) && "
            + "printf %s \(RemoteShell.quoted(base64Contents)) "
            + "| base64 --decode > \(RemoteShell.quoted(file)) && "
            + "test -s \(RemoteShell.quoted(file))"
    }

    /// How the successor is started when it has the session rather than a
    /// brief.
    ///
    /// **`--fork-session`, and that is not a detail.** Resuming the carried id
    /// as itself would give one conversation a second, divergent history on
    /// another machine, and nothing merges them. Forking says the true thing:
    /// the destination continues *from* the session rather than becoming it,
    /// and the original is left exactly as it was — which is the promise the
    /// whole transfer already makes about the work.
    static func resumeArguments(sessionIdentifier: String) -> [String] {
        ["--resume", sessionIdentifier, "--fork-session", "-p"]
    }
}
