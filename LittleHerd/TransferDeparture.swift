import Foundation

/// What happens on the machine the work is leaving.
///
/// The mirror of `SuccessorRun`, and the same shape for the same reasons: an
/// ordered list of commands, as a value, so that the ones this app must never
/// send can be asserted rather than remembered.
nonisolated struct TransferDeparture: Equatable {
    struct Step: Equatable {
        enum Purpose: Equatable {
            /// Ask the session where it got to.
            case brief
            /// Put the answer, and everything else uncommitted, on a branch.
            case capture
            case push
            case cleanup
        }

        let purpose: Purpose
        let command: String
        let isFatal: Bool
    }

    /// **Nothing here may touch the working copy, the index, or HEAD.**
    ///
    /// This runs against a repository somebody is *using* — quite possibly the
    /// one they are watching in another window — so the obvious ways to get a
    /// branch out of a dirty tree are all disqualified. `checkout -b` moves
    /// their checkout. `add -A` rewrites their index, and a staged/unstaged
    /// split is real work that would be silently flattened. `stash` mutates a
    /// stack shared with every worktree of the repository, which is somebody
    /// else's state.
    ///
    /// So the tree is assembled in a scratch index: `read-tree` seeds it from
    /// HEAD, `add -A` populates *that* index rather than the real one,
    /// `write-tree` turns it into a tree object and `commit-tree` into a
    /// commit, and only then does a branch ref appear pointing at it. Git
    /// objects are content-addressed and immutable, so every one of those
    /// steps is an addition; nothing existing is altered, and a failure
    /// half-way leaves unreferenced objects that git collects on its own.
    static func steps(
        repository: String,
        branch: String,
        sessionIdentifier: String,
        provider: AgentTaskProvider,
        agentExecutable: String,
        promptFile: String,
        indexFile: String,
        prompt: String,
        message: String
    ) -> [Step] {
        let repository = RemoteShell.quoted(repository)
        let branchName = RemoteShell.quoted(branch)
        let promptFile = RemoteShell.quoted(promptFile)
        let indexFile = RemoteShell.quoted(indexFile)
        let encodedPrompt = Data(prompt.utf8).base64EncodedString()

        var steps: [Step] = []

        // Staged the same way as the successor's, and for the same reason: it
        // is the one string here this app did not write.
        steps.append(
            Step(
                purpose: .brief,
                command: "printf %s \(RemoteShell.quoted(encodedPrompt)) "
                    + "| base64 -d > \(promptFile)",
                isFatal: true
            )
        )

        // Resuming is what makes this the session's own account of itself
        // rather than a summary assembled from the outside. It gets no shell
        // for the same reason the successor gets none — it is writing one
        // file, and everything else it could reach is somebody's live machine.
        let resume = switch provider {
        case .claude: ["-p", "--resume", sessionIdentifier]
        case .codex: ["exec", "resume", sessionIdentifier]
        }
        steps.append(
            Step(
                purpose: .brief,
                command: "cd \(repository) && "
                    + "\(RemoteShell.quoted(agentExecutable)) "
                    + "\(RemoteShell.quoted(resume)) "
                    + "--disallowedTools "
                    + "\(RemoteShell.quoted(SuccessorLaunch.deniedTools)) "
                    + "\"$(cat \(promptFile))\"",
                isFatal: true
            )
        )

        steps.append(
            Step(
                purpose: .capture,
                command: "rm -f \(indexFile) && "
                    + "GIT_INDEX_FILE=\(indexFile) git -C \(repository) "
                    + "read-tree HEAD && "
                    + "GIT_INDEX_FILE=\(indexFile) git -C \(repository) "
                    + "add -A && "
                    + "TREE=$(GIT_INDEX_FILE=\(indexFile) git -C \(repository) "
                    + "write-tree) && "
                    + "COMMIT=$(git -C \(repository) commit-tree \"$TREE\" "
                    + "-p HEAD -m \(RemoteShell.quoted(message))) && "
                    + "git -C \(repository) branch -f \(branchName) \"$COMMIT\"",
                isFatal: true
            )
        )

        // The sha is the last thing printed, because it is what the transfer
        // pins the destination to. See `SuccessorLaunch.plan`.
        steps.append(
            Step(
                purpose: .push,
                command: "git -C \(repository) push -f origin "
                    + "\(branchName):refs/heads/\(branch) && "
                    + "git -C \(repository) rev-parse \(branchName)",
                isFatal: true
            )
        )

        steps.append(
            Step(
                purpose: .cleanup,
                command: "rm -f \(indexFile) \(promptFile)",
                isFatal: false
            )
        )

        return steps
    }
}
