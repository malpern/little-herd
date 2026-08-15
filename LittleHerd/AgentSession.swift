import Foundation

nonisolated enum AgentSessionState: String, Equatable, Sendable {
    case active
    case completed
    case waiting

    var title: LocalizedStringResource {
        switch self {
        case .active: "Active"
        case .completed: "Finished"
        case .waiting: "Waiting"
        }
    }
}

nonisolated struct AgentSessionProgress: Equatable, Sendable {
    let completedStepCount: Int
    let totalStepCount: Int
    let currentStepIndex: Int
    let currentStep: String

    var fractionCompleted: Double {
        guard totalStepCount > 0 else { return 0 }
        return min(
            max(Double(completedStepCount) / Double(totalStepCount), 0),
            1
        )
    }
}

nonisolated struct AgentSession: Equatable, Identifiable, Sendable {
    let id: String
    let provider: AgentTaskProvider
    let projectName: String
    let state: AgentSessionState
    let updatedAt: Date
    let progress: AgentSessionProgress?

    func waitingIfActive() -> AgentSession {
        guard state == .active else { return self }
        return AgentSession(
            id: id,
            provider: provider,
            projectName: projectName,
            state: .waiting,
            updatedAt: updatedAt,
            progress: progress
        )
    }
}

nonisolated struct MachineAgentSession: Equatable, Identifiable, Sendable {
    let machine: MachineID
    let session: AgentSession
    /// Resolved from the saved configuration when the row is built, so a
    /// renamed machine reads the same here as everywhere else.
    let machineName: String
    let machineSymbolName: String

    init(
        machine: MachineID,
        session: AgentSession,
        machineName: String? = nil,
        machineSymbolName: String? = nil
    ) {
        self.machine = machine
        self.session = session
        self.machineName = machineName ?? machine.shortName
        self.machineSymbolName = machineSymbolName ?? machine.symbolName
    }

    var id: String { "\(machine.rawValue):\(session.id)" }
}

nonisolated enum MachineAgentSessionBuilder {
    static func visibleSessions(
        from sessions: [MachineAgentSession],
        maximumRecentCount: Int = 6
    ) -> [MachineAgentSession] {
        let active = sessions
            .filter { $0.session.state == .active }
            .sorted { $0.session.updatedAt > $1.session.updatedAt }
        let recent = sessions
            .filter { $0.session.state != .active }
            .sorted { lhs, rhs in
                let lhsPriority = lhs.session.state == .waiting ? 0 : 1
                let rhsPriority = rhs.session.state == .waiting ? 0 : 1
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }
                return lhs.session.updatedAt > rhs.session.updatedAt
            }
            .prefix(max(maximumRecentCount, 0))
        return active + recent
    }
}

nonisolated struct AgentProbeSnapshot: Equatable, Sendable {
    let tasksByProvider: [AgentTaskProvider: AgentTaskSummary]
    let sessions: [AgentSession]

    static let empty = AgentProbeSnapshot(tasksByProvider: [:], sessions: [])
}

nonisolated enum AgentSessionOutputParser {
    static func parse(_ output: String) -> [AgentSession] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap(parseLine)
            .sorted(by: sortSessions)
    }

    private static func parseLine(_ line: Substring) -> AgentSession? {
        let fields = line.split(
            separator: "\t",
            maxSplits: 8,
            omittingEmptySubsequences: false
        )
        guard fields.count == 9,
              fields[0].hasPrefix("agent_session="),
              let provider = AgentTaskProvider(
                  rawValue: String(fields[0].dropFirst("agent_session=".count))
              ),
              let id = decodeBase64(fields[1]),
              let state = AgentSessionState(rawValue: String(fields[2])),
              let updatedMilliseconds = Double(fields[3]),
              let workingDirectory = decodeBase64(fields[4]),
              let projectName = MachineActivityContext.projectName(
                  fromWorkingDirectory: workingDirectory
              ),
              let completedStepCount = Int(fields[5]),
              let totalStepCount = Int(fields[6]),
              let currentStepIndex = Int(fields[7])
        else {
            return nil
        }

        let decodedStep = decodeBase64(fields[8])
        let progress: AgentSessionProgress?
        if totalStepCount > 0,
           completedStepCount >= 0,
           completedStepCount <= totalStepCount,
           currentStepIndex > 0,
           currentStepIndex <= totalStepCount,
           let decodedStep,
           !decodedStep.isEmpty
        {
            progress = AgentSessionProgress(
                completedStepCount: completedStepCount,
                totalStepCount: totalStepCount,
                currentStepIndex: currentStepIndex,
                currentStep: decodedStep
            )
        } else {
            progress = nil
        }

        return AgentSession(
            id: "\(provider.rawValue):\(id)",
            provider: provider,
            projectName: projectName,
            state: state,
            updatedAt: Date(
                timeIntervalSince1970: updatedMilliseconds / 1_000
            ),
            progress: progress
        )
    }

    private static func decodeBase64(_ value: Substring) -> String? {
        guard !value.isEmpty,
              let data = Data(base64Encoded: String(value)),
              let decoded = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return decoded
    }

    private static func sortSessions(
        _ lhs: AgentSession,
        _ rhs: AgentSession
    ) -> Bool {
        let lhsPriority = priority(for: lhs.state)
        let rhsPriority = priority(for: rhs.state)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func priority(for state: AgentSessionState) -> Int {
        switch state {
        case .active: 0
        case .waiting: 1
        case .completed: 2
        }
    }
}
