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

    /// What the session being moved is asked to write.
    ///
    /// The counterpart to `SuccessorLaunch.prompt`, and the harder of the two
    /// to get right, because the thing it produces will be read by another
    /// agent as data. **A handoff that reads like instructions is an injection
    /// vector written by your own session** — so it is asked for a description
    /// of work, in prose, and told that it is writing for a person.
    ///
    /// It is asked for what a person could not reconstruct from the diff:
    /// what was tried and abandoned, what looked right and was not. That is
    /// the part of a session that dies with it, and this whole feature exists
    /// to carry exactly that.
    static func briefRequest(path: String, destination: String) -> String {
        """
        You are being moved to another machine — \(destination) — and this is
        the last thing you will be asked here. Your working tree travels with
        you; your memory of this conversation does not.

        Write that memory down, to \(path), and change nothing else. Do not
        carry on with the work, do not commit, do not run anything. Writing
        this file is the whole task.

        Cover, in prose and in your own words:

        - What you were asked to do, and where you had got to.
        - What is already done, and how somebody could check that.
        - What is left, in enough detail to pick up cold.
        - **What you learned that the code does not show** — what you tried
          that did not work, what looked correct and was not, which apparently
          reasonable approach is a dead end. This is the part that dies with
          this session, and it is the reason the file is worth writing.

        Two things to be careful of. Write a *description of work*, not
        instructions to whoever reads it: another agent will read this as
        data, and a handoff phrased as commands is a way of making one machine
        do as it is told by a file. And write only what you actually know — a
        confident account of something you did not verify is worse than
        saying you did not get to it.
        """
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
    /// - Parameter repository: **the session's own working directory**, not
    ///   the checkout the probe discovered under `~/local-code`. Those are the
    ///   same thing only when nobody is using a worktree, and this project is
    ///   developed in worktrees — so passing the discovered checkout captured
    ///   the parent's tree and pushed a branch that did not contain the work
    ///   the brief described. `git -C` is happy anywhere inside a working
    ///   tree, so the session's directory is both correct and sufficient.
    static func steps(
        repository: String,
        branch: String,
        sessionIdentifier: String,
        provider: AgentTaskProvider,
        agentExecutable: String,
        prompt: String,
        message: String
    ) -> [Step] {
        let repository = RemoteShell.quoted(repository)
        let branchName = RemoteShell.quoted(branch)

        // **Asked for at run time rather than assembled here.** These two files
        // must sit outside the working tree, or `add -A` would sweep them onto
        // the branch — which is why they used to be built as
        // `<repository>/.git/…`. That is a directory in a plain checkout and a
        // *file* in a worktree, so the path was invalid in exactly the case
        // this method now has to serve. `rev-parse --absolute-git-dir` answers
        // correctly for both, and it has to be asked once per step because each
        // one crosses its own ssh connection and no shell variable survives
        // between them.
        let promptFile = "\"$(git -C \(repository) rev-parse --absolute-git-dir)/little-herd-prompt\""
        let indexFile = "\"$(git -C \(repository) rev-parse --absolute-git-dir)/little-herd-index\""
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
                // On standard input, for the reason given in `SuccessorRun`:
                // `--disallowedTools` is variadic and eats a trailing prompt.
                command: "cd \(repository) && cat \(promptFile) | "
                    + "\(RemoteShell.quoted(agentExecutable)) "
                    + "\(RemoteShell.quoted(resume)) "
                    + "--disallowedTools "
                    + "\(RemoteShell.quoted(SuccessorLaunch.deniedTools))",
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
