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
        scheme: String,
        commitMessage: String
    ) -> [Step] {
        let scratch = RemoteShell.quoted(plan.workingDirectory)
        let repository = RemoteShell.quoted(repository)
        let promptFile = RemoteShell.quoted(promptFile)
        let encodedPrompt = Data(plan.prompt.utf8).base64EncodedString()

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

        // `"$(cat …)"` is a quoted expansion: the shell substitutes the file's
        // contents and does not re-parse them, so the prompt reaches the agent
        // as one argument however it is punctuated.
        steps.append(
            Step(
                purpose: .agent,
                command: "cd \(scratch) && "
                    + "\(RemoteShell.quoted(plan.executable)) "
                    + "\(RemoteShell.quoted(plan.arguments)) "
                    + "\"$(cat \(promptFile))\"",
                isFatal: true
            )
        )

        // The check and the delivery are this app's commands. A brief names
        // which scheme to build; it can never name a command line.
        for check in SuccessorLaunch.verification(scheme: scheme) {
            steps.append(
                Step(
                    purpose: .verification,
                    command: "cd \(scratch) && \(RemoteShell.quoted(check))",
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
                command: "git -C \(repository) worktree remove --force "
                    + "\(scratch); rm -f \(promptFile)",
                isFatal: false
            )
        )

        return steps
    }
}
