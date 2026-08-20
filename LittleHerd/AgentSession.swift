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

/// One row of the AI panel, with what it takes to tell it from its neighbours.
nonisolated struct AgentPanelRow: Equatable, Identifiable, Sendable {
    let session: MachineAgentSession
    /// Set only when another visible row has the same project on the same
    /// machine, which is the common case rather than the exotic one: a panel
    /// read on 18 August said "Clawd" three times and "Little Herd" twice, and
    /// no row could be told from any other. A few characters of the session's
    /// own id is the only thing that actually differs, and it is the same
    /// handle `--resume` takes.
    let disambiguator: String?

    var id: MachineAgentSession.ID { session.id }
}

/// What the AI panel shows, grouped the way it shows it.
///
/// Ordered by what needs you rather than by when it last moved. `waiting` is
/// the single most actionable fact this app holds — it is the state a session
/// can be moved from, and the state where a person is the blocker — and it used
/// to be a ten-pixel dot in the right gutter, indistinguishable from finished.
/// Finished work is real but it is over, so it collapses to a count instead of
/// spending a row each and outnumbering the one session that is live.
nonisolated struct AgentPanelLayout: Equatable, Sendable {
    let waiting: [AgentPanelRow]
    let active: [AgentPanelRow]
    let finished: [AgentPanelRow]

    var isEmpty: Bool {
        waiting.isEmpty && active.isEmpty && finished.isEmpty
    }

    /// How many sessions are blocked on a person. Drives the one number worth
    /// putting where it can be seen without opening anything.
    var waitingCount: Int { waiting.count }

    static func make(
        from sessions: [MachineAgentSession],
        maximumFinishedCount: Int = 6
    ) -> AgentPanelLayout {
        func rows(
            in state: AgentSessionState,
            limit: Int? = nil
        ) -> [MachineAgentSession] {
            let matching = sessions
                .filter { $0.session.state == state }
                .sorted { $0.session.updatedAt > $1.session.updatedAt }
            guard let limit else { return matching }
            return Array(matching.prefix(max(limit, 0)))
        }

        let waiting = rows(in: .waiting)
        let active = rows(in: .active)
        let finished = rows(in: .completed, limit: maximumFinishedCount)

        // Ambiguity is judged across everything on screen, not within a group:
        // the same project waiting on one machine and running on another is
        // exactly when you need to know which row is which.
        let visible = waiting + active + finished
        var counts: [String: Int] = [:]
        for row in visible {
            counts[Self.identity(of: row), default: 0] += 1
        }
        func decorate(_ rows: [MachineAgentSession]) -> [AgentPanelRow] {
            rows.map { row in
                AgentPanelRow(
                    session: row,
                    disambiguator: (counts[Self.identity(of: row)] ?? 0) > 1
                        ? Self.shortIdentifier(of: row.session)
                        : nil
                )
            }
        }

        return AgentPanelLayout(
            waiting: decorate(waiting),
            active: decorate(active),
            finished: decorate(finished)
        )
    }

    private static func identity(of row: MachineAgentSession) -> String {
        "\(row.machine.rawValue)\u{1F}\(row.session.projectName)"
    }

    /// The tail of the session's own id, with the provider prefix dropped —
    /// short enough to read, long enough to differ.
    static func shortIdentifier(of session: AgentSession) -> String {
        let raw = session.id.split(separator: ":", maxSplits: 1).last
            .map(String.init) ?? session.id
        return String(raw.suffix(4))
    }
}

nonisolated enum MachineAgentSessionBuilder {
    /// The flat list, in panel order. The header looks rows up by id and does
    /// not care about grouping, so it keeps taking this.
    static func visibleSessions(
        from sessions: [MachineAgentSession],
        maximumRecentCount: Int = 6
    ) -> [MachineAgentSession] {
        let layout = AgentPanelLayout.make(
            from: sessions,
            maximumFinishedCount: maximumRecentCount
        )
        return (layout.waiting + layout.active + layout.finished)
            .map(\.session)
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

    /// Waiting outranks active, here as in the panel: a session that is working
    /// needs nothing from anyone, and one that is waiting needs you.
    private static func priority(for state: AgentSessionState) -> Int {
        switch state {
        case .waiting: 0
        case .active: 1
        case .completed: 2
        }
    }
}
