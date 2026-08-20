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

/// What a session is costing the machine it runs on.
///
/// Memory is exact and instantaneous. CPU is not: `ps` reports a process's
/// average over its whole life, which for a session started this morning says
/// almost nothing about now. What is exact is *cumulative* CPU seconds, so the
/// share of a core a session is using is the difference between two readings
/// over the time between them — the same trick the remote CPU sampler already
/// plays with `iostat`, for the same reason.
nonisolated struct AgentResourceUsage: Equatable, Sendable {
    let residentBytes: Int
    let cpuSeconds: Double
    /// Share of one core since the previous sample, as a percentage. Nil until
    /// there have been two readings, because one reading cannot describe a
    /// rate.
    var cpuPercent: Double?

    var residentLabel: String {
        Int64(residentBytes).formatted(.byteCount(style: .memory))
    }
}

/// One agent process as the machine reports it.
nonisolated struct AgentProcessSample: Equatable, Sendable {
    let pid: Int
    let residentBytes: Int
    let cpuSeconds: Double
    let workingDirectory: String
}

nonisolated enum AgentProcessOutputParser {
    static func parse(_ output: String) -> [AgentProcessSample] {
        output.split(whereSeparator: \.isNewline).compactMap(parseLine)
    }

    private static func parseLine(_ line: Substring) -> AgentProcessSample? {
        let fields = line.split(
            separator: "\t",
            maxSplits: 3,
            omittingEmptySubsequences: false
        )
        guard fields.count == 4,
              fields[0].hasPrefix("agent_process="),
              let pid = Int(fields[0].dropFirst("agent_process=".count)),
              let residentKilobytes = Int(fields[1]),
              let seconds = cpuSeconds(fields[2]),
              let data = Data(base64Encoded: String(fields[3])),
              let directory = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return AgentProcessSample(
            pid: pid,
            residentBytes: residentKilobytes * 1_024,
            cpuSeconds: seconds,
            workingDirectory: directory
        )
    }

    /// `ps` writes cumulative CPU as `M:SS.ss`, and as `H:MM:SS.ss` once a
    /// process has been running for an hour — which agent sessions routinely
    /// are, so the second form is the common case rather than the exotic one.
    static func cpuSeconds(_ field: Substring) -> Double? {
        let parts = field.split(separator: ":")
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total = 0.0
        for part in parts {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

/// Ties processes to the sessions they are running.
nonisolated enum AgentResourceJoin {
    /// Matched on the working directory, which is all the two have in common.
    ///
    /// Two sessions started in the same directory cannot be told apart this
    /// way, and rather than attribute one session's cost to both, neither is
    /// given a figure. A wrong attribution here would be read as "this session
    /// is the expensive one" and could send someone to move the wrong work.
    static func attach(
        processes: [AgentProcessSample],
        to sessions: [AgentSession]
    ) -> [AgentSession] {
        var byDirectory: [String: [AgentProcessSample]] = [:]
        for process in processes {
            byDirectory[process.workingDirectory, default: []].append(process)
        }
        var sessionsPerDirectory: [String: Int] = [:]
        for session in sessions {
            guard let directory = session.workingDirectory else { continue }
            sessionsPerDirectory[directory, default: 0] += 1
        }

        return sessions.map { session in
            guard let directory = session.workingDirectory,
                  let matches = byDirectory[directory],
                  matches.count == 1,
                  sessionsPerDirectory[directory] == 1
            else {
                return session
            }
            let process = matches[0]
            return session.consuming(
                AgentResourceUsage(
                    residentBytes: process.residentBytes,
                    cpuSeconds: process.cpuSeconds
                )
            )
        }
    }
}

/// The last thing a session did, as its own transcript recorded it.
///
/// Carries the tool's *description* rather than its arguments. A raw shell
/// command is unreadable in a 300-point window, and it can carry paths and
/// contents that have no business on a screen someone else can see over your
/// shoulder — the description is a sentence the agent already wrote for a
/// person to read.
nonisolated struct AgentActivity: Equatable, Sendable {
    let tool: String
    let detail: String

    /// One line, in the present tense, for a panel refreshed on every sample.
    var phrase: String {
        let detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return fallbackPhrase }
        switch tool {
        // Bash and the agent tools already carry a written description, so
        // dressing them in a verb would say it twice.
        case "Bash", "Task", "Agent", "Skill": return detail
        case "Read", "NotebookRead": return "Reading \(detail)"
        case "Edit", "Write", "NotebookEdit": return "Editing \(detail)"
        case "Grep": return "Searching for \(detail)"
        case "Glob": return "Looking for \(detail)"
        case "WebFetch": return "Reading \(detail)"
        case "WebSearch": return "Searching the web for \(detail)"
        default: return detail
        }
    }

    private var fallbackPhrase: String {
        switch tool {
        case "": "Working"
        // Codex names the call and not what it is for: every shell command it
        // runs arrives as "exec". Better than the raw argument, which is a
        // block of JavaScript.
        case "exec", "shell", "local_shell": "Running a command"
        case "apply_patch": "Editing files"
        case "update_plan": "Planning"
        case "WebSearch": "Searching the web"
        case "AskUserQuestion": "Asking you a question"
        default: "Running \(tool)"
        }
    }
}

nonisolated struct AgentSession: Equatable, Identifiable, Sendable {
    let id: String
    let provider: AgentTaskProvider
    let projectName: String
    let state: AgentSessionState
    let updatedAt: Date
    let progress: AgentSessionProgress?
    /// How much is in the model's context right now, when the provider records
    /// it. Claude's transcripts do; Codex's rollouts do not, so this is nil for
    /// half the herd and the interface must not pretend otherwise.
    ///
    /// **There is deliberately no percentage, and no bar.** A transcript
    /// records what a turn *used* and never what the model *allows*, so a
    /// proportion would need a model-to-limit table — and one was written and
    /// thrown away, because it was already wrong: a session on this very
    /// machine measured 425,107 tokens against a table that would have called
    /// the limit 200,000. A number that is real beats a percentage that is
    /// invented, and the number still tells you which session is the heavy one.
    let contextTokens: Int?
    /// The session's own name — the one its agent's sidebar shows, set by the
    /// user or written by the model. Nil for a provider that records none, and
    /// then the project name has to stand in.
    let title: String?
    /// What it was last seen doing.
    let activity: AgentActivity?
    /// Where the session is working, kept so a process on the machine can be
    /// tied back to it — nothing in a process list names a session, and the
    /// working directory is the only thing the two have in common.
    let workingDirectory: String?
    /// What it is costing the machine, when a process could be matched to it.
    let resource: AgentResourceUsage?
    /// The context this model is allowed, when the provider says so.
    ///
    /// Codex writes `model_context_window` into every rollout; Claude records
    /// nothing of the kind, which is why the compaction threshold has to be
    /// learned by watching. Where both are known the measured threshold wins:
    /// it is where sessions actually compact, which is below the window.
    let contextWindow: Int?
    /// Which model is answering. The context a session may hold depends on it,
    /// and the limit is learned per model rather than assumed.
    let model: String?

    init(
        id: String,
        provider: AgentTaskProvider,
        projectName: String,
        state: AgentSessionState,
        updatedAt: Date,
        progress: AgentSessionProgress?,
        contextTokens: Int? = nil,
        title: String? = nil,
        activity: AgentActivity? = nil,
        model: String? = nil,
        workingDirectory: String? = nil,
        resource: AgentResourceUsage? = nil,
        contextWindow: Int? = nil
    ) {
        self.id = id
        self.provider = provider
        self.projectName = projectName
        self.state = state
        self.updatedAt = updatedAt
        self.progress = progress
        self.contextTokens = contextTokens
        self.title = title
        self.activity = activity
        self.model = model
        self.workingDirectory = workingDirectory
        self.resource = resource
        self.contextWindow = contextWindow
    }

    /// The same session with what it is costing attached.
    func consuming(_ resource: AgentResourceUsage?) -> AgentSession {
        AgentSession(
            id: id,
            provider: provider,
            projectName: projectName,
            state: state,
            updatedAt: updatedAt,
            progress: progress,
            contextTokens: contextTokens,
            title: title,
            activity: activity,
            model: model,
            workingDirectory: workingDirectory,
            resource: resource,
            contextWindow: contextWindow
        )
    }

    /// What the row calls this session. The title if it has one, because that
    /// is what identifies it everywhere else the user sees it; the project only
    /// when there is nothing better, and it repeats down the column.
    var displayTitle: String {
        guard let title, !title.isEmpty else { return projectName }
        return title
    }

    /// The line under the title, when there is something specific to put there.
    ///
    /// Nil rather than a restatement of the state. It used to say "Waiting for
    /// you" under every waiting session and "Finished" under every finished
    /// one — the same words repeating down a column, directly beneath a section
    /// header that had just said them once. A line that says what the group it
    /// sits in already says is a line that trains people to stop reading the
    /// column.
    ///
    /// A waiting session still gets its last activity here, and that is worth
    /// the row: what it was doing when it stopped is the fastest way to
    /// remember what it wants from you.
    var statusLine: String? {
        activity?.phrase ?? progress?.currentStep
    }

    func waitingIfActive() -> AgentSession {
        guard state == .active else { return self }
        return AgentSession(
            id: id,
            provider: provider,
            projectName: projectName,
            state: .waiting,
            updatedAt: updatedAt,
            progress: progress,
            contextTokens: contextTokens,
            title: title,
            activity: activity,
            model: model
        )
    }

    /// Compact enough for a row that is 300 points wide, and rounded because
    /// the last three digits of a context size are noise.
    var contextLabel: String? {
        guard let contextTokens, contextTokens > 0 else { return nil }
        if contextTokens >= 1_000_000 {
            return String(
                format: "%.1fM",
                Double(contextTokens) / 1_000_000
            )
        }
        if contextTokens >= 1_000 {
            return "\(contextTokens / 1_000)k"
        }
        return "\(contextTokens)"
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
    /// Set only when another visible row shows the same title.
    ///
    /// Judged on what the row actually displays, which is the point: this began
    /// as a fix for a panel titled by project, where "Clawd" appeared three
    /// times and no row could be told from its neighbour. Rows are titled by
    /// the session's own name now, so nearly all of them are already distinct —
    /// and a mark on a row that is plainly unique is noise pretending to be
    /// information. Seen doing exactly that in a render, on every row at once.
    let disambiguator: String?

    var id: MachineAgentSession.ID { session.id }
}

/// What the AI panel shows, grouped the way it shows it.
///
/// Running first, then waiting, then a count of what finished.
///
/// An earlier version put waiting at the top, on the reasoning that a blocked
/// session is the one needing a person. That was reversed deliberately: this
/// panel is for watching work that is happening, and a queue of things to
/// attend to is a different screen with a different job. Waiting is still
/// grouped, labelled and never truncated — it is below, not hidden.
///
/// Finished work collapses to a count. It is most of what a probe returns and
/// the least useful thing on screen, and it used to outnumber the one session
/// that was live.
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
        maximumFinishedCount: Int = 6,
        showingFinished: Bool = true
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

        // Ambiguity is judged across what is actually on screen. Not within a
        // group — the same project waiting on one machine and running on
        // another is exactly when you need to know which row is which — but
        // not across hidden rows either: marking a row because it collides
        // with something folded inside the finished group explains nothing,
        // since you cannot see the thing it is being distinguished from.
        let visible = waiting + active + (showingFinished ? finished : [])
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
        "\(row.machine.rawValue)\u{1F}\(row.session.displayTitle)"
    }

    /// The tail of the session's own id, with the provider prefix dropped —
    /// short enough to read, long enough to differ.
    static func shortIdentifier(of session: AgentSession) -> String {
        let raw = session.id.split(separator: ":", maxSplits: 1).last
            .map(String.init) ?? session.id
        return String(raw.suffix(4))
    }
}

nonisolated enum AgentPanelFocus {
    /// Which machine's sessions the panel shows.
    ///
    /// One machine at a time, the way the metric detail screens work: a herd
    /// view answers "where is the work", and this screen answers "what is that
    /// machine doing", which are different questions and were being asked in
    /// one list. The dashboard's selection decides it whenever there is one.
    ///
    /// On the overview there is no selection, so the panel falls back to the
    /// machine with the most sessions actually running — the one you would have
    /// picked. Ties go to the machine with the most sessions of any kind, and
    /// then to the order the herd is configured in, so the choice does not
    /// flicker between two equal machines on every sample.
    static func machine(
        for sessions: [MachineAgentSession],
        selected: MachineID?,
        order: [MachineID] = []
    ) -> MachineID? {
        if let selected { return selected }

        var running: [MachineID: Int] = [:]
        var total: [MachineID: Int] = [:]
        for session in sessions {
            total[session.machine, default: 0] += 1
            if session.session.state == .active {
                running[session.machine, default: 0] += 1
            }
        }
        guard !total.isEmpty else { return nil }

        func rank(_ machine: MachineID) -> Int {
            order.firstIndex(of: machine) ?? order.count
        }
        return total.keys.max { lhs, rhs in
            let lhsKey = (running[lhs] ?? 0, total[lhs] ?? 0, -rank(lhs))
            let rhsKey = (running[rhs] ?? 0, total[rhs] ?? 0, -rank(rhs))
            return lhsKey < rhsKey
        }
    }

    static func sessions(
        _ sessions: [MachineAgentSession],
        on machine: MachineID?
    ) -> [MachineAgentSession] {
        guard let machine else { return [] }
        return sessions.filter { $0.machine == machine }
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
        return (layout.active + layout.waiting + layout.finished)
            .map(\.session)
    }
}

nonisolated struct AgentProbeSnapshot: Equatable, Sendable {
    let tasksByProvider: [AgentTaskProvider: AgentTaskSummary]
    let sessions: [AgentSession]
    /// What this machine last saw of the Codex account's limits.
    let codexUsage: AIUsageLimit?

    init(
        tasksByProvider: [AgentTaskProvider: AgentTaskSummary],
        sessions: [AgentSession],
        codexUsage: AIUsageLimit? = nil
    ) {
        self.tasksByProvider = tasksByProvider
        self.sessions = sessions
        self.codexUsage = codexUsage
    }

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
            maxSplits: 14,
            omittingEmptySubsequences: false
        )
        guard fields.count == 15,
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
            progress: progress,
            // Empty for a provider that does not report it, and empty is not
            // zero: zero would claim an empty context.
            contextTokens: Int(fields[9]),
            title: decodeBase64(fields[10]),
            activity: fields[11].isEmpty
                ? nil
                : AgentActivity(
                    tool: String(fields[11]),
                    detail: decodeBase64(fields[12]) ?? ""
                ),
            model: fields[13].isEmpty ? nil : String(fields[13]),
            workingDirectory: workingDirectory,
            contextWindow: Int(fields[14]).flatMap { $0 > 0 ? $0 : nil }
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

    /// Active outranks waiting, here as in the panel. The panel's job is to
    /// show what is running now; what is blocked on a person is real but it is
    /// not moving, and it sits below.
    private static func priority(for state: AgentSessionState) -> Int {
        switch state {
        case .active: 0
        case .waiting: 1
        case .completed: 2
        }
    }
}
