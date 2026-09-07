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

    /// Every file the carry moves: the transcript, and the sidecar directory
    /// beside it when there is one.
    ///
    /// The sidecar holds `tool-results` and the session's own title. A carry
    /// without it resumed fine in the experiment — it is not load-bearing — but
    /// a carry that wants the whole record should take the whole record.
    static func sourcePaths(
        home: String,
        workingDirectory: String,
        sessionIdentifier: String
    ) -> (transcript: String, sidecar: String) {
        let directory = "\(home)/.claude/projects/"
            + projectDirectoryName(for: workingDirectory)
        return (
            transcript: "\(directory)/\(sessionIdentifier).jsonl",
            sidecar: "\(directory)/\(sessionIdentifier)"
        )
    }

    /// **Refuse a transcript that is still being written.** A running session
    /// appends to its own file, so a copy taken mid-write is torn — and a torn
    /// JSONL resumes as a session missing its last turns, silently. Two looks
    /// at the size, a beat apart: if they differ, something is writing, and
    /// the carry says so instead of guessing. Run on the source, after the
    /// departure's own steps, which is the moment nothing of ours is writing.
    static func stabilityCommand(transcript: String) -> String {
        let quoted = RemoteShell.quoted(transcript)
        return "test -s \(quoted) && a=$(stat -f %z \(quoted) 2>/dev/null || "
            + "stat -c %s \(quoted)) && sleep 1 && "
            + "b=$(stat -f %z \(quoted) 2>/dev/null || stat -c %s \(quoted)) && "
            + "test \"$a\" = \"$b\""
    }

    /// The first line the resumed session reads.
    ///
    /// The boundary is what stops a stale memory editing the wrong tree — see
    /// the type's own note — and this is belt-and-braces over it: the model
    /// demonstrably handles "you have moved" when told, so it is told, in the
    /// first line, before anything else.
    static func movedNotice(from source: String, to destination: String) -> String {
        "You have been moved to another machine. Your working directory is now "
            + "\(destination). Files you remember at \(source) are on a different "
            + "machine and are not reachable from here; do not try to read or "
            + "edit them. Continue the work in \(destination)."
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
