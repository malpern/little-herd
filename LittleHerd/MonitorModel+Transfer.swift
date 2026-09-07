import Foundation

extension MonitorModel {
    /// Moves a session to another machine, in the order the whole design
    /// depends on: the source writes down where it got to and pushes, and only
    /// then does anything start on the destination.
    ///
    /// **Nothing here decides anything.** `TransferAssembly` says whether the
    /// move is possible and what it consists of, `TransferPilot` runs the two
    /// halves and carries the one value between them, and the coordinator
    /// holds the result. This is the wiring, and it is deliberately the only
    /// part that knows both which machines exist and how to reach them.
    func beginTransfer(
        of session: AgentSession,
        from origin: MachineID,
        to destination: MachineID
    ) {
        // See `DashboardChrome.startsTransfers`: wired, working, and not yet
        // allowed to surprise anybody.
        guard DashboardChrome.startsTransfers else {
            if DashboardChrome.rehearsesTransfers {
                // The interface, and nothing else. No connection is opened and
                // no command is run — this exists so the row can be judged by
                // using it rather than by looking at a picture of it.
                transfers.rehearse(
                    Transfer(
                        origin: origin,
                        destination: destination,
                        branch: TransferAssembly.branch(for: session),
                        title: session.title ?? session.projectName,
                        repository: session.workingDirectory ?? ""
                    )
                )
            }
            return
        }

        // **A machine with a fixable gap is prepared first, on screen.** A
        // drop can land on one that lacks the checkout or the agent — it lifted
        // to meet the drag for exactly this — and here the remedy runs before
        // the transfer, shown as its own phase in the same card. The drop is
        // the consent: the machine was visibly marked as needing setup, the
        // fix is a phase you can watch and Stop, and nothing runs silently the
        // way the command line's `--fix` guards against with `--yes`.
        let disposition = AgentDropEligibility.disposition(
            of: destination,
            carrying: MachineAgentActivity(provider: session.provider, sessions: [session]),
            from: origin,
            in: machines.map(\.destinationAccount)
        )
        if disposition == .fixable {
            fixThenTransfer(session: session, from: origin, to: destination)
            return
        }

        let assembled = TransferAssembly.request(
            session: session,
            from: origin,
            to: destination,
            in: machines.map(\.destinationAccount),
            check: TransferAssembly.check
        )

        guard case .success(let request) = assembled else {
            // A refusal is not a transfer that failed; it is one that never
            // started, and the interface says so without a row appearing and
            // vanishing.
            return
        }

        transfers.prepare(request.transfer)

        Task {
            guard let source = machines.first(where: { $0.machine == origin })
            else {
                return transfers.fail(
                    request.transfer,
                    SuccessorOutcome(
                        result: .couldNotStart,
                        failingStep: nil,
                        output: "Couldn’t reach the machine it is leaving.",
                        // Nothing was asked of it, so nothing was made.
                        remnant: .nothing
                    )
                )
            }

            // **The same three steps the command line takes**, in the same
            // order, through the same code — see `TransferDriver`. What is left
            // here is the wiring: which machines exist, how to reach them, and
            // where the answer goes.
            // Asked here rather than inside the driver: this probe also
            // records what it learned on the machine itself, so the herd shows
            // a machine that needs signing in. The driver only needs the answer.
            var authRefusal: String?
            if let target = machines.first(where: { $0.machine == destination }) {
                await target.verifyAgentAuthentication()
                if case .refused(let reason) = target.agentAuth {
                    authRefusal = reason
                }
            }

            let target = machines.first { $0.machine == destination }
            // The preference is read here, at the moment of the drop, so a
            // change to it takes effect on the next transfer and never on one
            // already in flight.
            let carries = UserDefaults.standard.bool(
                forKey: LittleHerdPreferences.carriesTranscriptKey
            )
            let prepared = await TransferDriver.prepare(
                request,
                authRefusal: authRefusal,
                destinationName: target?.shortName ?? "the destination",
                destinationCommand: target.map {
                    TransferRunners.command(for: $0.configuration)
                },
                carry: (carries && target != nil) ? TransferDriver.Carry(
                    localSourceHome: source.isLocal ? NSHomeDirectory() : nil,
                    sourceCommand: TransferRunners.command(for: source.configuration),
                    copy: TransferRunners.copy(to: target!.configuration),
                    destinationHome: NSHomeDirectory(),
                    scratchRoot: TransferAssembly.scratchRoot
                ) : nil,
                departure: TransferRunners.departure(for: source.configuration)
            )

            switch prepared {
            case .blocked(let outcome):
                transfers.fail(request.transfer, outcome)
            case .ready(let commit, let steps):
                // Kept so the result can be read back: the diff is everything
                // after this, and the branch carries the departure too.
                transfers.record(departure: commit, for: request.transfer)
                transfers.begin(request.transfer, steps: steps)
            }
        }
    }

    /// Reads what a finished transfer changed.
    ///
    /// Run on the machine the work came *from*, which has the repository and
    /// is where somebody is sitting. Local commands, not SSH: the destination
    /// may be asleep by the time anybody opens this, and the branch is on the
    /// remote either way.
    func diff(for transfer: Transfer) async -> Result<TransferDiff, TransferDiffFailure> {
        guard let departure = transfers.departures[transfer] else {
            return .failure(TransferDiffFailure(
                message: "This transfer did not get as far as pushing "
                    + "anything, so there is nothing on the branch to read."
            ))
        }
        let commands = TransferDiffReader.commands(
            repository: transfer.repository,
            branch: transfer.branch,
            since: departure
        )
        var outputs: [String] = []
        for command in commands {
            let text = await LocalProcessRunner.run(
                executablePath: "/usr/bin/git",
                arguments: Array(command.dropFirst())
            )
            guard let text else {
                return .failure(TransferDiffFailure(
                    message: "Couldn’t read the branch. The work is still on "
                        + "\(transfer.branch); nothing has been merged."
                ))
            }
            outputs.append(text)
        }
        guard outputs.count == 3 else {
            return .failure(
                TransferDiffFailure(message: "Couldn’t read the branch.")
            )
        }
        return .success(
            TransferDiffReader.parse(numstat: outputs[1], patch: outputs[2])
        )
    }
}

extension TransferAssembly {
    /// The check every transfer currently runs, and where scratch worktrees go.
    ///
    /// **Still a constant, and now only because nothing reports what is in a
    /// repository yet.** `RepositoryCheckDetector` answers this from a listing
    /// of the repository root; what is missing is somebody to take that
    /// listing on the machine concerned. Until then every transfer is assumed
    /// to be this project, which is true of every transfer that has happened.
    /// `nonisolated` because the driver that reads them is, and it is shared
    /// with the command line — neither value touches the main actor.
    nonisolated static let check = RepositoryCheck.xcode(scheme: "LittleHerd")
    nonisolated static let scratchRoot = NSString(string: "~/.little-herd/transfers")
        .expandingTildeInPath
}

extension MonitorModel {
    /// Prepare a machine that lifted to meet the drag but was not ready, then
    /// transfer onto it.
    ///
    /// **Its own card from the first frame.** A fixing phase is registered
    /// before anything runs, so the animal the card sits on shows the work
    /// starting rather than a beat of nothing — and the strip says which
    /// machine is being set up. The remedy is computed here because the clone
    /// needs the source's remote, read from the machine that has the checkout.
    func fixThenTransfer(
        session: AgentSession,
        from origin: MachineID,
        to destination: MachineID
    ) {
        let branch = TransferAssembly.branch(for: session)
        let destinationModel = machines.first { $0.machine == destination }
        let name = destinationModel?.shortName ?? "the machine"
        let placeholder = Transfer(
            origin: origin, destination: destination, branch: branch,
            title: session.title ?? session.projectName,
            repository: session.workingDirectory ?? ""
        )
        transfers.fixing(placeholder, machine: name)

        Task {
            guard let originModel = machines.first(where: { $0.machine == origin }),
                  let destinationModel
            else {
                return transfers.fail(placeholder, SuccessorOutcome(
                    result: .couldNotStart, failingStep: nil,
                    output: "Couldn’t reach one of the machines.", remnant: .nothing
                ))
            }

            let herd = machines.map(\.destinationAccount)
            let activity = MachineAgentActivity(provider: session.provider, sessions: [session])
            let eligibility = AgentDropEligibility.eligibility(
                of: destination, carrying: activity, from: origin, in: herd
            )
            let slug = AgentDropEligibility.repository(of: activity, from: origin, in: herd)
            // The remote, read from the source. A clone the source cannot name
            // becomes an explanation, and a machine that only looked fixable
            // fails here rather than in the middle of a transfer.
            let originURL = await self.gitRemoteURL(
                of: session.workingDirectory, on: originModel
            )
            let remedy = TransferRemedy.remedy(
                for: eligibility, machine: name, provider: session.provider,
                originURL: originURL, slug: slug
            )

            switch remedy {
            case .none:
                break  // Already ready after all; fall through to the transfer.
            case .explain(let text):
                return transfers.fail(placeholder, SuccessorOutcome(
                    result: .couldNotStart, failingStep: nil,
                    output: text, remnant: .nothing
                ))
            case .offer(_, let command):
                let ran = await TransferRunners.remedyRunner(
                    for: destinationModel.configuration
                )(command)
                guard ran.succeeded else {
                    return transfers.fail(placeholder, SuccessorOutcome(
                        result: .couldNotStart, failingStep: nil,
                        output: "The setup did not complete on \(name). "
                            + ran.output.suffix(400),
                        remnant: .nothing
                    ))
                }
                // The clone or install changed the machine; re-probe it so the
                // transfer sees the new checkout at its real path rather than
                // the report that predates the fix.
                if let sampler = destinationModel.configuration.remotePlatform.map({
                    RemoteMetricsSampler(
                        host: destinationModel.configuration.sshDestination,
                        platform: $0,
                        identityFile: destinationModel.configuration.identityFile
                    )
                }), let snapshot = try? await sampler.sample() {
                    destinationModel.apply(snapshot)
                }
            }

            // The machine is ready now. Hand back to the ordinary path, which
            // re-assembles against the refreshed herd and runs the transfer —
            // the fixing card it already put up carries straight into it.
            self.transfers.dismiss(placeholder)
            self.beginTransfer(of: session, from: origin, to: destination)
        }
    }

    /// The `origin` remote of the checkout a directory sits in, read on the
    /// machine that has it. Nil when the source is remote and unreachable or
    /// has no remote — a clone then cannot be offered.
    func gitRemoteURL(of directory: String?, on model: MachineMonitorModel) async -> String? {
        guard let directory, !directory.isEmpty else { return nil }
        let command = "git -C \(RemoteShell.quoted(directory)) remote get-url origin"
        let out = await TransferRunners.command(for: model.configuration)(command)
        guard out.succeeded else { return nil }
        let url = out.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }
}
