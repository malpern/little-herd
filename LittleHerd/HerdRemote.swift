import Foundation

// MARK: - Moving from a phone

extension MonitorModel {
    /// A move asked for by a phone: the plan when `dryRun`, the move itself
    /// otherwise. Goes through the same assembly and the same
    /// `beginTransfer` a drag on the dashboard does, so the phone can start
    /// nothing the Mac would not.
    func remoteMove(_ request: HerdWire.MoveRequest) async -> HerdWire.MoveResponse {
        let origin = MachineID(rawValue: request.from)
        let destination = MachineID(rawValue: request.to)
        let source = machines.first { $0.machine == origin }
        let target = machines.first { $0.machine == destination }
        let session = source?.agentSessions.first { $0.id == request.session }

        func refuse(_ reason: String, fix: String? = nil) -> HerdWire.MoveResponse {
            HerdWire.MoveResponse(
                applied: false,
                title: session.map { $0.title ?? $0.projectName } ?? request.session,
                fromName: source.map(Self.wireName) ?? request.from,
                toName: target.map(Self.wireName) ?? request.to,
                refusal: reason,
                fixesFirst: false,
                steps: [],
                fix: fix
            )
        }

        guard let source, let session else {
            return refuse("That session is no longer on \(source?.shortName ?? request.from).")
        }
        guard let target, origin != destination else {
            return refuse("There is no such machine to move it to.")
        }
        guard target.state == .live else {
            return refuse("\(target.shortName) isn’t answering right now, so it can’t take work.")
        }

        let herd = machines.map(\.destinationAccount)
        let disposition = AgentDropEligibility.disposition(
            of: destination,
            carrying: MachineAgentActivity(provider: session.provider, sessions: [session]),
            from: origin,
            in: herd,
            requiresApproval: UserDefaults.standard
                .bool(forKey: LittleHerdPreferences.requiresDestinationApprovalKey)
        )
        if case .refused(let why) = TransferEligibility.verdict(
            for: session,
            hasRepository: session.workingDirectory != nil
        ) {
            return refuse(TransferEligibility.explanation(for: why))
        }
        if disposition == .refuse {
            return refuse("\(target.shortName) can’t take this one.")
        }
        if disposition == .ready {
            switch TransferAssembly.request(
                session: session,
                from: origin,
                to: destination,
                in: herd,
                check: TransferAssembly.check
            ) {
            case .failure(let refusal):
                return refuse(HerdCommand.reason(refusal).capitalizedFirst + ".")
            case .success(let assembled) where request.dryRun:
                // **The plan asks the destination what the move itself will
                // ask**, so a missing tool is on the phone before anyone
                // presses Move — with the line that would fix it — rather than
                // in a failed card afterwards.
                if case .missingTool(let reason, let remedy) = await TransferDriver.discoverCheck(
                    repository: assembled.destinationRepository,
                    on: Self.wireName(target),
                    sshHost: target.configuration.connection == .local
                        ? nil : target.configuration.sshDestination,
                    run: TransferRunners.command(for: target.configuration)
                ) {
                    return refuse(
                        reason.replacingOccurrences(of: " Nothing was moved.", with: ""),
                        fix: remedy
                    )
                }
            case .success:
                break
            }
        }

        let fixes = disposition == .fixable
        var steps: [String] = []
        if session.state == .active {
            steps.append("Wait for its current turn on \(source.shortName) to finish")
        }
        if fixes {
            steps.append("Set up \(target.shortName) — clone the checkout or install the agent")
        }
        steps += [
            "Ask it to write down where it got to, and push that as a branch",
            "Start the agent on \(target.shortName) from that branch",
            "Run the checks and push the result",
        ]

        if !request.dryRun {
            beginTransfer(of: session, from: origin, to: destination)
        }
        return HerdWire.MoveResponse(
            applied: !request.dryRun,
            title: session.title ?? session.projectName,
            fromName: Self.wireName(source),
            toName: Self.wireName(target),
            refusal: nil,
            fixesFirst: fixes,
            steps: steps
        )
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension MonitorModel {
    /// "This Mac" is true only on this Mac; a phone gets its name.
    static func wireName(_ machine: MachineMonitorModel) -> String {
        machine.isLocal && machine.shortName == "This Mac" ? machine.name : machine.shortName
    }
}
