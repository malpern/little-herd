import Foundation

/// `little-herd move <session> --to <machine> [--yes]`.
///
/// **The one verb that changes something, and the reason the CLI was deferred
/// until it was decided rather than arrived at.** Every transfer until now
/// began with a human picking a card up and dropping it on an animal. This
/// removes that by construction: an agent that can call `move` can send its own
/// work to another machine, spend tokens there and push branches with nobody
/// dragging anything.
///
/// The answer is the house rule this herd's other tools already use, copied
/// from `attgw` and `yarm` rather than invented: **reads are automatic, a write
/// prints the change and refuses without `--yes`,** and the exit code carries
/// the contract — `0` applied, `1` error, `2` refused and *nothing changed*.
/// The `2` exists precisely so "I refused" cannot be mistaken for "I did it".
///
/// **It runs the dashboard's own code path**, not a second one. Assembly,
/// sign-in check, departure and arrival all go through `TransferDriver` and
/// `TransferRunners`, which is what makes a transfer started here evidence
/// about a transfer started by a drag. A parallel implementation would have
/// tested itself and nothing else.
extension HerdCommand {
    /// Where the work would go, and what would be true afterwards.
    struct Plan {
        let session: AgentSession
        let origin: MachineConfiguration
        let destination: MachineConfiguration
        let branch: String
    }

    /// Resolves a machine the way somebody would type it: its short name, its
    /// full name, or its id, case-insensitively, and a prefix will do.
    ///
    /// Ambiguity is refused rather than guessed at, for the same reason a
    /// session prefix is — picking one of two would eventually move work to
    /// the wrong machine, and that is a mistake nobody would see until later.
    /// A refusal carrying the sentence to print. `String` is not an `Error`,
    /// and the words are the whole payload here.
    struct Unresolved: Error { let message: String }

    static func machine(
        matching wanted: String,
        in configurations: [MachineConfiguration]
    ) -> Result<MachineConfiguration, Unresolved> {
        let needle = wanted.lowercased()
        let exact = configurations.filter {
            $0.id.rawValue.lowercased() == needle
                || $0.shortName.lowercased() == needle
                || $0.name.lowercased() == needle
        }
        let matches = exact.isEmpty
            ? configurations.filter {
                $0.id.rawValue.lowercased().hasPrefix(needle)
                    || $0.shortName.lowercased().hasPrefix(needle)
                    || $0.name.lowercased().hasPrefix(needle)
            }
            : exact

        guard let first = matches.first else {
            let known = configurations.map(\.shortName).joined(separator: ", ")
            return .failure(Unresolved(
                message: "little-herd: no machine matching “\(wanted)”. Known: \(known)"
            ))
        }
        guard matches.count == 1 else {
            let names = matches.map(\.shortName).joined(separator: ", ")
            return .failure(Unresolved(
                message: "little-herd: “\(wanted)” matches \(matches.count) machines: \(names)"
            ))
        }
        return .success(first)
    }

    /// What a refused-because-not-confirmed answer says.
    ///
    /// It prints the change first and in full, because the point of refusing is
    /// that somebody reads it before saying yes. The branch name is on it
    /// deliberately: that is where the work will be, and it is the thing to go
    /// looking for if anything goes wrong later.
    static func plannedChange(_ plan: Plan, json: Bool) -> String {
        if json {
            return jsonArray([[
                "applied": "false",
                "exit_reason": "confirmation_required",
                "session": shortIdentifier(plan.session.id),
                "title": plan.session.displayTitle,
                "from": plan.origin.shortName,
                "to": plan.destination.shortName,
                "branch": plan.branch,
            ]])
        }
        return """
            little-herd would move this work:

              session      \(shortIdentifier(plan.session.id))  \(plan.session.displayTitle)
              from         \(plan.origin.shortName)
              to           \(plan.destination.shortName)
              branch       \(plan.branch)

            The session it leaves is not retired: nothing in a transfer stops
            it, so the worst case is work sitting on a branch nobody merged.

            Nothing has been changed. Re-run with --yes to do it.
            """
    }
}

extension HerdCommand {
    /// Runs the move, printing each step as it starts.
    ///
    /// **Blocking, and safe to be**, for the same reason `sampleBlocking` is:
    /// everything awaited here is `nonisolated` — the driver, the runners, the
    /// executor and the sign-in probe. The deadlock this project already found
    /// came from blocking the main thread on work that hopped *back* to the
    /// main actor to finish, and nothing on this path does.
    static func performMove(
        _ plan: Plan,
        herd: [DestinationAccount],
        json: Bool,
        log: @escaping @Sendable (String) -> Void
    ) -> (output: String, code: Int32) {
        let assembled = TransferAssembly.request(
            session: plan.session,
            from: plan.origin.id,
            to: plan.destination.id,
            in: herd,
            check: TransferAssembly.check
        )
        guard case .success(let request) = assembled else {
            guard case .failure(let refusal) = assembled else {
                return ("little-herd: could not assemble the transfer", 1)
            }
            // A refusal is not a failed transfer; it is one that never started,
            // and the words are the app's own rather than a second opinion.
            return ("little-herd: \(reason(refusal))", 1)
        }

        let outcome = Handoff<SuccessorOutcome>()
        let semaphore = DispatchSemaphore(value: 0)
        let destination = plan.destination
        let origin = plan.origin

        Task.detached {
            // The same question the dashboard asks before anything leaves this
            // machine, and for the same measured reason: a destination whose
            // token expired would otherwise push a branch, build a worktree and
            // start an agent before failing on something knowable in one step.
            var authRefusal: String?
            if !request.destinationAgentPath.isEmpty {
                log("checking \(destination.shortName) can sign in")
                log("agent: \(request.destinationAgentPath)")
                let state = await AgentAuthVerifier.verify(
                    install: AgentInstallation(
                        provider: request.provider,
                        // The version is not a question this asks; the path and
                        // the provider are what the probe runs.
                        version: "",
                        path: request.destinationAgentPath
                    ),
                    isLocal: destination.connection == .local,
                    host: destination.sshDestination,
                    identityFile: destination.identityFile
                )
                if case .refused(let why) = state { authRefusal = why }
            }

            // **Wrapped so a failure names the command that failed.** The
            // first live run through this verb reported `departure(.brief, "")`
            // — the right step and nothing else, because `SuccessorLocal`
            // returns exactly an empty string when a process will not start,
            // and an empty string is indistinguishable from a command that ran
            // and said nothing. A tool that runs commands on your machines
            // should be able to tell you which one it was.
            let inner = TransferRunners.departure(for: origin)
            let prepared = await TransferDriver.prepare(
                request,
                authRefusal: authRefusal,
                destinationName: destination.shortName,
                destinationCommand: { command in
                    await TransferRunners.command(for: destination)(command)
                },
                note: log,
                departure: { step in
                    log("\(step.purpose)")
                    let out = await inner(step)
                    if !out.succeeded {
                        log("failed: \(step.command)")
                        let said = out.text.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        )
                        log(said.isEmpty ? "it said nothing at all" : "said: \(said)")
                    }
                    return out
                }
            )

            switch prepared {
            case .blocked(let blocked):
                outcome.value = blocked
            case .ready(_, let steps):
                let run = TransferRunners.arrival(for: destination)
                outcome.value = await SuccessorExecutor.execute(
                    steps: steps,
                    run: run,
                    progress: { purpose in log("\(purpose)") }
                )
            }
            semaphore.signal()
        }
        // **Bounded, because an unbounded wait is a hang with no story.**
        // Seen on 6 September: the sign-in probe suspended and never resumed —
        // main thread parked on this semaphore, every worker thread idle, no
        // `ssh` process ever spawned — and the command sat there for
        // twenty-seven minutes saying nothing. The probe's own 90-second
        // watchdog cannot help, because whatever failed happened before it
        // started.
        //
        // The cap is the sum of what the steps are allowed plus room: an agent
        // may have half an hour and a check fifteen minutes. Reaching it means
        // something is wrong with this tool rather than with the transfer, and
        // it says so in those terms rather than inventing a result.
        let ceiling = DispatchTime.now() + .seconds(70 * 60)
        guard semaphore.wait(timeout: ceiling) == .success else {
            return (
                "little-herd: gave up waiting. Nothing here timed out — the "
                    + "transfer stopped reporting, which is a fault in this "
                    + "command rather than an answer about the work. Check "
                    + "whether a branch was pushed before trusting anything.",
                1
            )
        }

        guard let result = outcome.value else {
            return ("little-herd: the transfer reported nothing", 1)
        }

        let phase = TransferPhase.finished(result)
        if json {
            return (
                jsonArray([[
                    "applied": result.result == SuccessorOutcome.Result.landed ? "true" : "false",
                    "result": String(describing: result.result),
                    "branch": request.transfer.branch,
                    "left_a_branch": phase.leftABranch ? "true" : "false",
                    "detail": phase.detail,
                    "output": result.output,
                ]]),
                result.result == SuccessorOutcome.Result.landed ? 0 : 1
            )
        }

        var lines = ["", phase.detail]
        // **And what it actually said.** `detail` is the sentence for the
        // *state* — "It never started, so nothing was changed anywhere" — and
        // the dashboard pairs it with the output in a window. Printing only
        // the sentence made the first live run through this verb report a
        // refusal with no reason attached, which is a tool that knows why and
        // will not say.
        let said = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !said.isEmpty {
            lines.append("")
            lines.append(contentsOf: said.split(separator: "\n").map { "  \($0)" })
        }
        if phase.leftABranch {
            lines.append("")
            lines.append("  branch  \(request.transfer.branch)")
        }
        return (
            lines.joined(separator: "\n"),
            result.result == SuccessorOutcome.Result.landed ? 0 : 1
        )
    }
}

extension HerdCommand {
    /// Parses `move`, finds what it names, and either describes the change or
    /// makes it.
    static func move(
        _ rest: [String],
        configurations: [MachineConfiguration],
        json: Bool
    ) -> (output: String, code: Int32) {
        let arguments = Array(rest.dropFirst())
        guard let wanted = arguments.first(where: { !$0.hasPrefix("-") }) else {
            return (
                "usage: little-herd move <session> --to <machine> [--yes] [--json]",
                1
            )
        }
        guard let toIndex = arguments.firstIndex(of: "--to"),
              arguments.indices.contains(toIndex + 1)
        else {
            return ("little-herd: move needs --to <machine>", 1)
        }
        let confirmed = arguments.contains("--yes")

        let sampled = sampleBlocking(configurations)
        let found = sampled.flatMap { configuration, snapshot in
            (snapshot?.agentSessions ?? [])
                .filter {
                    bareIdentifier($0.id).hasPrefix(wanted) || $0.id.hasPrefix(wanted)
                }
                .map { (configuration, $0) }
        }
        guard let (origin, session) = found.first else {
            return ("little-herd: no session starting “\(wanted)”", 1)
        }
        guard found.count == 1 else {
            let where_ = found.map { "\(shortIdentifier($0.1.id)) on \($0.0.name)" }
            return (
                "little-herd: “\(wanted)” matches \(found.count) sessions: "
                    + where_.joined(separator: ", "),
                1
            )
        }

        let destination: MachineConfiguration
        switch machine(matching: arguments[toIndex + 1], in: configurations) {
        case .failure(let unresolved): return (unresolved.message, 1)
        case .success(let found): destination = found
        }
        guard destination.id != origin.id else {
            return ("little-herd: “\(destination.shortName)” is where it already is", 1)
        }

        let plan = Plan(
            session: session,
            origin: origin,
            destination: destination,
            branch: TransferAssembly.branch(for: session)
        )

        // **Refused, and exit 2 rather than 1.** The distinction is the whole
        // reason the code exists: 1 means something went wrong, 2 means it was
        // asked and declined and nothing on any machine was touched. A caller
        // that cannot tell those apart will eventually retry a write that
        // already happened.
        guard confirmed else { return (plannedChange(plan, json: json), 2) }

        let herd = sampled.map { configuration, snapshot in
            DestinationAccount(
                machine: configuration.id,
                name: configuration.name,
                symbolName: "desktopcomputer",
                report: snapshot?.destination,
                mayHostSessions: configuration.mayHostSessions,
                auth: .unverified,
                isVerifying: false
            )
        }

        // Progress goes to stderr as it happens, so a slow step is visibly a
        // slow step rather than a hang, and stdout stays the answer alone —
        // which is what makes `--json` safe to pipe.
        let log: @Sendable (String) -> Void = { line in
            FileHandle.standardError.write(Data(("  " + line + "\n").utf8))
        }
        if !json {
            log("moving \(shortIdentifier(session.id)) from "
                + "\(origin.shortName) to \(destination.shortName)")
        }
        return performMove(plan, herd: herd, json: json, log: log)
    }
}
