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
                        title: session.title ?? session.projectName
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
                        output: "Couldn’t reach the machine it is leaving."
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
                        output: String(describing: failure)
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
                            output: String(describing: failure)
                        )
                    )
                case .success(let steps):
                    transfers.begin(request.transfer, steps: steps)
                }
            }
        }
    }

    /// How to talk to one machine, or nothing if it is not one we can reach.
    ///
    /// The local Mac has no runner: a transfer *from* here would have to run
    /// its departure locally rather than over SSH, and that path does not
    /// exist yet — better an honest refusal than a command sent to a hostname
    /// that means this machine.
    private func departureRunner(
        for machine: MachineID
    ) -> (@Sendable (TransferDeparture.Step) async -> SuccessorExecutor.StepOutput)? {
        guard let model = machines.first(where: { $0.machine == machine }),
              !model.isLocal
        else { return nil }

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
