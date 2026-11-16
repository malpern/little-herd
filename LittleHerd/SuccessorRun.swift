import Foundation

/// What actually happens on the destination, in order, as a value.
///
/// `SuccessorLaunch` decides *whether* to start a successor and with what.
/// This decides *what will be run*, and it is separate for the same reason:
/// a list of commands can be read in a test, and the commands this app must
/// never send are easier to assert about than to remember.
///
/// The steps are shell commands rather than argument lists because they cross
/// an `ssh` boundary, where a shell is doing the parsing whatever we intend.
/// Everything interpolated into one goes through `RemoteShell.quoted`.
nonisolated struct SuccessorRun: Equatable {
    struct Step: Equatable {
        /// What this step is for. The interface reports progress in these
        /// terms — "running the check" rather than a command line — and the
        /// distinction between an agent failure and a check failure is the
        /// one a person actually wants when a transfer comes back red.
        enum Purpose: Equatable {
            case worktree
            case prompt
            case agent
            case verification
            case delivery
            case cleanup
        }

        let purpose: Purpose
        let command: String
        /// Whether a non-zero exit abandons the rest of the run.
        ///
        /// Everything up to delivery is fatal: a failed check must not be
        /// followed by a push. Cleanup is not, because a run that has already
        /// failed still has a worktree to take away.
        let isFatal: Bool
    }

    let steps: [Step]

    /// - Parameters:
    ///   - promptFile: where the prompt is staged on the destination. Kept
    ///     *beside* the worktree rather than inside it, so it never appears in
    ///     the diff the successor produces.
    ///
    /// **The prompt is delivered base64-encoded, and that is a safety property
    /// rather than a convenience.** It carries the brief, which is the one
    /// piece of this whole path that we do not write — and interpolating an
    /// unwritten string into a command line on another machine is exactly the
    /// abuse the spike demonstrated, one layer lower down. Base64's alphabet
    /// cannot close a quote, so the encoded form is inert no matter what the
    /// brief says; the decode happens into a file, and the agent reads the
    /// file. A brief never touches a command line in any form.
    static func steps(
        plan: SuccessorLaunch.Plan,
        repository: String,
        branch: String,
        promptFile: String,
        check: RepositoryCheck,
        commitMessage: String
    ) -> [Step] {
        let scratch = RemoteShell.quoted(plan.workingDirectory)
        let repository = RemoteShell.quoted(repository)
        let promptFile = RemoteShell.quoted(promptFile)
        let encodedPrompt = Data(plan.prompt.utf8).base64EncodedString()

        if plan.live != nil {
            return liveSteps(
                plan: plan,
                repository: repository,
                branch: branch,
                promptFile: promptFile,
                encodedPrompt: encodedPrompt
            )
        }

        var steps: [Step] = []

        // Fetch, prove it is what we were told to expect, and work from a
        // detached head. Creating a local branch on the destination would
        // leave a name behind that collides with the next transfer on the
        // same ref, and there is nothing here that needs one.
        //
        // The `test` is the pin: what arrives over the network has to match
        // the sha the source machine pushed, or the run stops before an agent
        // has read a single line of it. The worktree is then made from the
        // sha rather than from FETCH_HEAD, so even a race between the two
        // commands cannot substitute anything.
        let commit = RemoteShell.quoted(plan.expectedCommit)
        steps.append(
            Step(
                purpose: .worktree,
                command: "git -C \(repository) fetch origin "
                    + "\(RemoteShell.quoted(branch)) "
                    + "&& test \"$(git -C \(repository) rev-parse FETCH_HEAD)\" "
                    + "= \(commit) "
                    // **Idempotent, because the scratch path is derived from
                    // the branch and so is the same every time this session is
                    // moved.** A run that ends without cleaning up — a crash, a
                    // machine that slept, a cancelled transfer — leaves the
                    // directory behind, and `worktree add` then refuses with
                    // "already exists" for ever after. Measured: the second
                    // live transfer of one session failed here because the
                    // first had left its worktree, and the only thing wrong was
                    // litter. Removing first costs nothing when there is
                    // nothing to remove.
                    + "&& { git -C \(repository) worktree remove --force "
                    + "\(scratch) >/dev/null 2>&1 || true; } "
                    + "&& rm -rf \(scratch) "
                    + "&& git -C \(repository) worktree add --detach "
                    + "\(scratch) \(commit)",
                isFatal: true
            )
        )

        steps.append(
            Step(
                purpose: .prompt,
                command: "printf %s \(RemoteShell.quoted(encodedPrompt)) "
                    + "| base64 -d > \(promptFile)",
                isFatal: true
            )
        )

        // **The prompt goes in on standard input, not as an argument.**
        //
        // The first version passed it as the trailing argument, which looked
        // right and failed on the first real transfer with "Input must be
        // provided either through stdin or as a prompt argument". The cause is
        // that `--disallowedTools` takes a *list*: it swallowed `Bash`,
        // `WebFetch`, `WebSearch` and then the prompt as well, leaving no
        // positional argument at all. Reordering would only move the problem
        // to whatever ended up last.
        //
        // Piping is better than a fix for that anyway — it takes the brief off
        // the command line entirely, which is a stronger version of the
        // property the base64 staging was already reaching for. The pipe also
        // reaches EOF, which is what the agent needs; an inherited stdin is
        // what it waits on for ever.
        steps.append(
            Step(
                purpose: .agent,
                command: "cd \(scratch) && cat \(promptFile) | "
                    + "\(RemoteShell.quoted(plan.executable)) "
                    + "\(RemoteShell.quoted(plan.arguments))",
                isFatal: true
            )
        )

        // The check and the delivery are this app's commands. A repository
        // names which check to run and fills in its blanks; neither it nor a
        // brief can ever name a command line. See `RepositoryCheck`.
        for check in SuccessorLaunch.verification(check: check) {
            steps.append(
                Step(
                    purpose: .verification,
                    command: "cd \(scratch) && \(RepositoryCheckProbe.toolPath) && \(RemoteShell.quoted(check))",
                    isFatal: true
                )
            )
        }

        for command in SuccessorLaunch.delivery(
            branch: branch,
            message: commitMessage
        ) {
            steps.append(
                Step(
                    purpose: .delivery,
                    command: "cd \(scratch) && \(RemoteShell.quoted(command))",
                    isFatal: true
                )
            )
        }

        // Always, and never fatal: a failed run is the case that most needs
        // its worktree taken away.
        steps.append(
            Step(
                purpose: .cleanup,
                // `rm -rf` after the removal rather than instead of it:
                // git's own removal is the tidy path and also unregisters the
                // worktree, but it fails on a directory it does not recognise
                // and then the litter stays. Both, and neither is fatal.
                command: "git -C \(repository) worktree remove --force "
                    + "\(scratch) >/dev/null 2>&1; rm -rf \(scratch); "
                    + "rm -f \(promptFile)",
                isFatal: false
            )
        )

        return steps
    }

    /// Marks a live worktree whose session started, beside it. Cleanup keeps
    /// a marked worktree and removes an unmarked one: the session lives in it.
    static func liveMarker(_ workingDirectory: String) -> String {
        "\(workingDirectory).live"
    }

    /// The live version: the same pinned fetch, then a worktree that stays.
    ///
    /// Differences from the one-shot run, each deliberate:
    /// - **The worktree is on the transfer branch**, so the session can commit
    ///   and push its own work when the person asks; nothing does it for it.
    /// - **An existing worktree is refused, not cleared.** The one-shot run
    ///   removes litter at its path; here the path can hold a session somebody
    ///   is still talking to, and removing it would end that conversation.
    /// - **`.claude/worktrees/` goes in the repository's own `info/exclude`**,
    ///   never its `.gitignore`, so the main checkout does not list the
    ///   worktrees as untracked and nothing in the repository changes.
    /// - **No check and no push**: the session owns the branch.
    /// - Cleanup removes the worktree only if the session never started.
    ///
    /// The prompt is the session's first message, passed as one argument read
    /// from the staged file. That is a parameter expansion, which the shell does
    /// not parse again, so the brief still cannot become a command; `--` stops
    /// it being read as an option.
    private static func liveSteps(
        plan: SuccessorLaunch.Plan,
        repository: String,
        branch: String,
        promptFile: String,
        encodedPrompt: String
    ) -> [Step] {
        let worktree = RemoteShell.quoted(plan.workingDirectory)
        let marker = RemoteShell.quoted(liveMarker(plan.workingDirectory))
        let commit = RemoteShell.quoted(plan.expectedCommit)
        let exclude = RemoteShell.quoted("/.claude/worktrees/")
        return [
            Step(
                purpose: .worktree,
                command: "git -C \(repository) fetch origin \(RemoteShell.quoted(branch)) "
                    + "&& test \"$(git -C \(repository) rev-parse FETCH_HEAD)\" = \(commit) "
                    + "&& { test ! -e \(worktree) || { echo \"A moved copy of this session "
                    + "is already on this machine.\"; exit 1; }; } "
                    + "&& rm -f \(marker) "
                    + "&& f=\"$(git -C \(repository) rev-parse --path-format=absolute "
                    + "--git-path info/exclude)\" && mkdir -p \"$(dirname \"$f\")\" "
                    + "&& { grep -qxF \(exclude) \"$f\" 2>/dev/null || printf '%s\\n' "
                    + "\(exclude) >> \"$f\"; } "
                    + "&& git -C \(repository) worktree add -B \(RemoteShell.quoted(branch)) "
                    + "\(worktree) \(commit)",
                isFatal: true
            ),
            Step(
                purpose: .prompt,
                command: "printf %s \(RemoteShell.quoted(encodedPrompt)) | base64 -d > \(promptFile)",
                isFatal: true
            ),
            Step(
                purpose: .agent,
                command: "cd \(worktree) && \(RemoteShell.quoted(plan.executable)) "
                    + "\(RemoteShell.quoted(plan.arguments)) -- \"$(cat \(promptFile))\" "
                    + "&& touch \(marker)",
                isFatal: true
            ),
            Step(
                purpose: .cleanup,
                command: "rm -f \(promptFile); test -e \(marker) || "
                    + "{ git -C \(repository) worktree remove --force \(worktree) >/dev/null 2>&1; "
                    + "rm -rf \(worktree); }"
                    + carriedCopyRemoval(plan: plan, marker: marker),
                isFatal: false
            ),
        ]
    }

    /// **The carried copy goes once the fork holds everything in it.**
    ///
    /// A carried transcript lands under the destination's project folder with
    /// the departing session's own id, so that `--resume --fork-session` can
    /// find it. The fork writes a file of its own, and after that the copy is
    /// a second, finished-looking session in that folder: the herd listed it
    /// as "completed" beside the live one, which is half of why a move looked
    /// like a duplication (15 November). The fork keeps every message's
    /// `uuid`, so the copy is removed once another file there holds the copy's
    /// last one, waiting up to thirty seconds. If that never shows, the copy
    /// stays: a duplicate in the list is better than a conversation lost.
    static func carriedCopyRemoval(plan: SuccessorLaunch.Plan, marker: String) -> String {
        guard let carried = plan.carriedSession else { return "" }
        let folder = "\"$HOME\"/.claude/projects/"
            + RemoteShell.quoted(TranscriptCarry.projectDirectoryName(for: plan.workingDirectory))
        let copy = "\(folder)/\(RemoteShell.quoted(carried + ".jsonl"))"
        let sidecar = "\(folder)/\(RemoteShell.quoted(carried))"
        return "; test -e \(marker) && test -f \(copy) && { "
            + "u=$(grep -o '\"uuid\":\"[^\"]*\"' \(copy) | tail -n 1); "
            + "test -n \"$u\" && for i in $(seq 1 30); do "
            + "for f in \(folder)/*.jsonl; do "
            + "if [ \"$f\" != \(copy) ] && grep -qF \"$u\" \"$f\"; then "
            + "rm -f \(copy); rm -rf \(sidecar); break 2; fi; done; sleep 1; done; }; true"
    }
}
