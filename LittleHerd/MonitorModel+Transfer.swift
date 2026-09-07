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
            let prepared = await TransferDriver.prepare(
                request,
                authRefusal: authRefusal,
                destinationName: target?.shortName ?? "the destination",
                destinationCommand: target.map {
                    TransferRunners.command(for: $0.configuration)
                },
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
