import Foundation

/// Everything a transfer does before its destination starts working, in one
/// place both callers use.
///
/// **The point is that there is only one of these.** The dashboard drives a
/// transfer from a drop and the command line drives one from `move`, and if
/// each carried its own copy of the order — verify, depart, plan the arrival —
/// then an end-to-end test through the CLI would prove the CLI works and say
/// nothing whatever about dragging. That is the trap this project keeps
/// finding: the fan and the resting deck were two descriptions of one object
/// and they disagreed.
///
/// It stops at the point the two genuinely diverge. Handing the arrival's
/// steps to a coordinator that draws a progress bar is a different job from
/// running them and printing what happened, so the steps are where this ends.
/// Five of the six bugs that turning transfers on actually cost were inside
/// what is above that line.
nonisolated enum TransferDriver {
    /// What preparing a transfer came to.
    enum Prepared {
        /// It did not get far enough to run anything on the destination. The
        /// outcome carries **what survives on the source**, which is the whole
        /// reason this is not just an error string: a failed push leaves a
        /// branch on one machine, and a refused destination leaves one on the
        /// remote.
        case blocked(SuccessorOutcome)
        /// The departure succeeded and the arrival is planned. `commit` is
        /// kept because the diff is everything after it — the branch carries
        /// the departure too, so diffing from the branch's parent would
        /// present the brief as the successor's work.
        case ready(commit: String, steps: [SuccessorRun.Step])
    }

    /// - Parameters:
    ///   - request: what `TransferAssembly` said the move consists of. Refusals
    ///     happen before this and are the caller's to report — a refusal is not
    ///     a transfer that failed, it is one that never started.
    ///   - authRefusal: why the destination cannot sign in, when it definitely
    ///     cannot. **Asked by the caller and passed in as a value**, because
    ///     asking differs where it should: the dashboard's probe also updates
    ///     the machine's own state so the herd shows it, and the command line
    ///     has no state to update. What must not differ is what happens next,
    ///     and that is here.
    ///   - departure: runs a step on the source.
    ///   - destinationName: what to call the destination in a sentence.
    ///   - destinationCommand: runs one command there, for the two questions
    ///     the pre-flight asks. Optional: without it the request's own check is
    ///     used, which is what every transfer did before item 14.
    static func prepare(
        _ request: TransferAssembly.Request,
        authRefusal: String? = nil,
        destinationName: String = "the destination",
        destinationCommand: (@Sendable (String) async -> (output: String, succeeded: Bool))? = nil,
        note: (@Sendable (String) -> Void)? = nil,
        carry: Carry? = nil,
        departure: @Sendable (TransferDeparture.Step) async -> SuccessorExecutor.StepOutput
    ) async -> Prepared {
        // **Before anything leaves this machine.**
        //
        // Measured on the first live transfers: the mini's token had expired
        // six days earlier, and the transfer pushed a branch, fetched it on the
        // far side, built a worktree, staged a brief and started an agent
        // before failing on something knowable in one step.
        //
        // Only a definite refusal stops it. A probe that times out means
        // nothing was learned, and refusing on silence would ground the herd
        // whenever a machine was slow.
        if let reason = authRefusal {
            return .blocked(
                SuccessorOutcome(
                    result: .couldNotStart,
                    failingStep: nil,
                    output: reason,
                    // Nothing has been built or pushed yet, and this is the one
                    // refusal that can still say so honestly.
                    remnant: .nothing
                )
            )
        }

        // **The agent path, before anything moves.**
        //
        // `SuccessorLaunch.plan` checks this against `SuccessorBinary` — the
        // destination's reported path is a claim, and executing an unchecked
        // claim would let a compromised machine choose what runs on it — but
        // it checks it during the *arrival*, which is after the branch has been
        // pushed. Measured on 6 September: the mini keeps its agent inside the
        // Claude desktop app's bundle, every transfer to it was refused for
        // that, and each refusal cost a departure, a model call and a branch on
        // the remote before saying so.
        //
        // Nothing about the answer needs the departure to have happened. The
        // same function, asked first, turns the most expensive refusal in the
        // system into the cheapest one.
        if SuccessorBinary.accept(request.destinationAgentPath, for: request.provider) == nil {
            return .blocked(
                SuccessorOutcome(
                    result: .couldNotStart,
                    failingStep: nil,
                    output: "\(destinationName) offered an agent at "
                        + "\(request.destinationAgentPath), which is not a "
                        + "location an agent has been measured working from. "
                        + "Nothing was moved.",
                    remnant: .nothing
                )
            )
        }

        // **Before the departure, because a missing tool is knowable without
        // moving anything.** The same reasoning as the sign-in check above: the
        // expensive place to discover a destination cannot do the work is after
        // the branch has been pushed.
        var check = request.check
        if let destinationCommand {
            switch await discoverCheck(
                repository: request.destinationRepository,
                on: destinationName,
                run: destinationCommand
            ) {
            case .check(let discovered):
                check = discovered
                note?("check: \(discovered)")
            case .missingTool(let reason):
                return .blocked(
                    SuccessorOutcome(
                        result: .couldNotStart,
                        failingStep: nil,
                        output: reason,
                        remnant: .nothing
                    )
                )
            case .unknown:
                // Nothing was learned, so nothing is claimed and the request's
                // own check stands.
                break
            }
        }

        // **The carry goes first, and a carried session is not briefed.**
        //
        // The first live run of the carry never reached it: the departure
        // resumed the session to ask for a brief and the answer was "Prompt is
        // too long" — a 24 MB transcript plus the request overflows the
        // window. The brief fails for exactly the sessions with the most to
        // lose, and it was ordered before the carry that would have saved
        // them. So the copy happens here, where nothing of ours is writing to
        // the transcript, and if it lands the brief step is dropped: the
        // successor has the whole history, a summary of it would cost a model
        // call and can fail, and a summary it does not need is not worth
        // either. If the carry declines, the brief is written as before.
        var carriedSession: String? = nil
        var departureSteps = request.departure
        if let carry {
            switch await carryTranscript(request, carry: carry) {
            case .carried:
                carriedSession = request.sessionIdentifier
                departureSteps = departureSteps.filter { $0.purpose != .brief }
                note?("carried the transcript; the successor resumes the session, and no brief is written")
            case .fellBack(let why):
                note?("brief instead of transcript: \(why)")
            }
        }

        let departed = await TransferPilot.depart(
            steps: departureSteps,
            run: departure
        )

        switch departed {
        case .failure(let failure):
            return .blocked(
                SuccessorOutcome(
                    result: .couldNotStart,
                    failingStep: nil,
                    output: String(describing: failure),
                    // Where it stopped decides what survives, and only the
                    // failure knows where it stopped.
                    remnant: failure.remnant
                )
            )
        case .success(let commit):
            let arrival = TransferPilot.arrival(
                commit: commit,
                briefPath: request.briefPath,
                briefText: "",
                branch: request.transfer.branch,
                repository: request.destinationRepository,
                scratchRoot: TransferAssembly.scratchRoot,
                provider: request.provider,
                reportedAgentPath: request.destinationAgentPath,
                // The discovered one when the destination answered, and the
                // request's otherwise.
                check: check,
                commitMessage: "Successor work on \(request.transfer.branch)",
                carriedSession: carriedSession
            )
            switch arrival {
            case .failure(let failure):
                return .blocked(
                    SuccessorOutcome(
                        result: .couldNotStart,
                        failingStep: nil,
                        output: String(describing: failure),
                        // The departure fully succeeded to get here: the work
                        // is pushed and only the destination was refused.
                        remnant: .pushedBranch
                    )
                )
            case .success(let steps):
                return .ready(commit: commit, steps: steps)
            }
        }
    }
}

extension TransferDriver {
    /// What the destination's copy of this repository needs, and whether the
    /// destination has it.
    ///
    /// **Asked before the assembly, because the answer goes into it.** The
    /// check is part of what a transfer *is* — the successor runs it and the
    /// result decides whether the work is delivered — so it has to be known
    /// before the request is built rather than patched onto one.
    ///
    /// Two commands on the destination and no more: a one-level listing, and
    /// `command -v` for the single tool the detected check names. Both are
    /// cheap, and both are asked at the moment somebody is trying to move
    /// work rather than on the thirty-second sample, which is item 14's rule
    /// — machine facts are cheap and work facts are not.
    enum Discovered {
        case check(RepositoryCheck)
        /// The destination has the repository and not the tool. Named, not
        /// offered: see `RepositoryCheckProbe.missingToolReason`.
        case missingTool(String)
        /// Nothing could be read, so nothing is claimed. The caller falls back
        /// rather than refusing — an unreachable listing is not evidence that
        /// a machine is unsuitable, and refusing on silence would ground the
        /// herd whenever a machine was slow.
        case unknown
    }

    static func discoverCheck(
        repository: String,
        on machineName: String,
        run: @Sendable (String) async -> (output: String, succeeded: Bool)
    ) async -> Discovered {
        let listed = await run(RepositoryCheckProbe.listing(of: repository))
        guard listed.succeeded else { return .unknown }

        let check = RepositoryCheckDetector.check(
            forEntries: RepositoryCheckProbe.entries(fromListing: listed.output)
        )
        guard let preflight = RepositoryCheckProbe.preflight(for: check) else {
            // Nothing to run means nothing to have. `.none` is a real answer
            // and a deliberate one — see `RepositoryCheck.none`.
            return .check(check)
        }

        let has = await run(preflight)
        guard has.succeeded else {
            return .missingTool(
                RepositoryCheckProbe.missingToolReason(check, on: machineName)
            )
        }
        return .check(check)
    }
}


extension TransferDriver {
    /// What a caller supplies to carry a transcript, and only what it must.
    ///
    /// Everything here is a machine fact the driver cannot know: where the
    /// source's home is if the source is this Mac, how to run one command
    /// there, and how to copy a file to the destination. The decision to carry
    /// at all is the preference, read by the caller, so a render or a test
    /// can pass nil and get yesterday's behaviour exactly.
    struct Carry {
        /// The source's home directory **when the source is this Mac**, which
        /// is the only source the carry reads from today. A remote source is
        /// declined rather than attempted: fetching its transcript here first
        /// is a second hop that has not been run live, and this project ships
        /// what it has run.
        let localSourceHome: String?
        let sourceCommand: @Sendable (String) async -> (output: String, succeeded: Bool)
        let copy: @Sendable (_ localPath: String, _ remotePath: String, _ recursive: Bool) async -> Bool
        /// The destination's home, for the project folder the successor will
        /// look in. Both machines on this herd share one, and the same
        /// assumption already lives in `TransferAssembly.scratchRoot`.
        let destinationHome: String
        let scratchRoot: String
    }

    enum Carried {
        case carried
        case fellBack(String)
    }

    /// The carry itself: check the file is still, copy it and its sidecar to
    /// where the successor will look, and say which of those failed if one did.
    static func carryTranscript(
        _ request: TransferAssembly.Request,
        carry: Carry
    ) async -> Carried {
        guard request.provider == .claude else {
            return .fellBack("only a Claude session can be carried")
        }
        guard let home = carry.localSourceHome else {
            return .fellBack("the session is on another machine, and only this Mac's are carried yet")
        }
        guard let workingDirectory = request.sessionWorkingDirectory, !workingDirectory.isEmpty else {
            return .fellBack("the session has no working directory to find its transcript by")
        }

        let source = TranscriptCarry.sourcePaths(
            home: home,
            workingDirectory: workingDirectory,
            sessionIdentifier: request.sessionIdentifier
        )

        // Still, and present. A file whose size changes between two looks has
        // a writer, and a copy taken then is a session missing its last turns.
        let still = await carry.sourceCommand(
            TranscriptCarry.stabilityCommand(transcript: source.transcript)
        )
        guard still.succeeded else {
            return .fellBack("its transcript is missing, empty, or still being written")
        }

        let scratch = SuccessorLaunch.workingDirectory(
            scratchRoot: carry.scratchRoot,
            branch: request.transfer.branch
        )
        let destination = TranscriptCarry.destinationDirectory(
            home: carry.destinationHome,
            successorWorkingDirectory: scratch
        )
        guard await carry.copy(
            source.transcript,
            "\(destination)/\(request.sessionIdentifier).jsonl",
            false
        ) else {
            return .fellBack("the transcript could not be copied to the destination")
        }
        // The sidecar is not load-bearing — the experiment resumed without it
        // — so its absence, or a failure copying it, is not a reason to lose
        // the carry. Attempted, and the outcome ignored.
        if FileManager.default.fileExists(atPath: source.sidecar) {
            _ = await carry.copy(
                source.sidecar,
                "\(destination)/\(request.sessionIdentifier)",
                true
            )
        }
        return .carried
    }
}
