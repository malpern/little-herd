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
            scheme: TransferAssembly.scheme
        )

        guard case .success(let request) = assembled else {
            // A refusal is not a transfer that failed; it is one that never
            // started, and the interface says so without a row appearing and
            // vanishing.
            return
        }

        transfers.prepare(request.transfer)

        Task {
            guard let sourceRunner = departureRunner(for: origin) else {
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

            let departed = await TransferPilot.depart(
                steps: request.departure,
                run: sourceRunner
            )

            switch departed {
            case .failure(let failure):
                transfers.fail(
                    request.transfer,
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
                // Kept so the result can be read back: the diff is everything
                // after this, and the branch carries the departure too.
                transfers.record(departure: commit, for: request.transfer)
                let arrival = TransferPilot.arrival(
                    commit: commit,
                    briefPath: request.briefPath,
                    briefText: "",
                    branch: request.transfer.branch,
                    repository: request.destinationRepository,
                    scratchRoot: TransferAssembly.scratchRoot,
                    provider: request.provider,
                    reportedAgentPath: request.destinationAgentPath,
                    scheme: request.scheme,
                    commitMessage: "Successor work on \(request.transfer.branch)"
                )
                switch arrival {
                case .failure(let failure):
                    transfers.fail(
                        request.transfer,
                        SuccessorOutcome(
                            result: .couldNotStart,
                            failingStep: nil,
                            output: String(describing: failure),
                            // The departure fully succeeded to get here: the
                            // work is pushed, and only the destination was
                            // refused.
                            remnant: .pushedBranch
                        )
                    )
                case .success(let steps):
                    transfers.begin(request.transfer, steps: steps)
                }
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

    /// How to talk to one machine, or nothing if it is not one we can reach.
    ///
    /// **This Mac runs its departure directly.** It used to be refused, on the
    /// grounds that a local departure "does not exist yet" — which was true and
    /// made the ordinary case impossible: working on the machine in front of
    /// you and handing the session to another one. The steps are shell text
    /// either way, so the only difference is whether `ssh` is in front of them.
    private func departureRunner(
        for machine: MachineID
    ) -> (@Sendable (TransferDeparture.Step) async -> SuccessorExecutor.StepOutput)? {
        guard let model = machines.first(where: { $0.machine == machine })
        else { return nil }
        guard !model.isLocal else { return SuccessorLocal.departureRunner() }

        let host = model.sshDestination
        let identity = model.identityFile
        return { step in
            let result = await SSHCommandRunner.runReportingStatus(
                host: host,
                command: step.command,
                identityFile: identity,
                timeout: SuccessorSSH.timeout(
                    for: step.purpose == .brief ? .agent : .worktree
                )
            )
            return SuccessorExecutor.StepOutput(
                text: result.output,
                succeeded: result.succeeded
            )
        }
    }
}

extension TransferAssembly {
    /// The scheme a check runs against, and where scratch worktrees go.
    /// Constants for now; both belong in per-repository settings the day
    /// Little Herd is pointed at something that is not this project.
    static let scheme = "LittleHerd"
    static let scratchRoot = NSString(string: "~/.little-herd/transfers")
        .expandingTildeInPath
}
