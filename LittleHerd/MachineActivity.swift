import Foundation
import OSLog

nonisolated enum AgentTaskProvider: String, Codable, Equatable, Hashable, Sendable {
    case codex
    case claude

    var displayName: LocalizedStringResource {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    var processName: String {
        switch self {
        case .codex: "codex"
        case .claude: "claude"
        }
    }

    /// Apps whose icon stands for this provider, most specific first.
    var bundleIdentifiers: [String] {
        switch self {
        case .codex: ["com.openai.chat", "com.openai.codex"]
        case .claude: ["com.anthropic.claude-code", "com.anthropic.claudefordesktop"]
        }
    }
}

nonisolated enum AgentTaskStatus: String, Equatable, Sendable {
    case active
    case recent
}

nonisolated struct AgentTaskSummary: Equatable, Sendable {
    let provider: AgentTaskProvider
    let projectName: String
    let status: AgentTaskStatus
    let updatedAt: Date?
}

nonisolated enum MachineActivityKind: Equatable, Hashable, Sendable {
    case codex
    case claudeCode
    case compiling
    case building
    case virtualMachine
    case browser
    case terminal
    case indexing
    case desktop
    case other
}

nonisolated struct MachineActivity: Equatable, Sendable {
    let processName: String
    let cpuPercent: Double
    let processID: Int?
    let contextName: String?
    let childProcessName: String?
    let agentTask: AgentTaskSummary?

    init(
        processName: String,
        cpuPercent: Double,
        processID: Int? = nil,
        contextName: String? = nil,
        childProcessName: String? = nil,
        agentTask: AgentTaskSummary? = nil
    ) {
        self.processName = processName
        self.cpuPercent = cpuPercent
        self.processID = processID
        self.contextName = contextName
        self.childProcessName = childProcessName
        self.agentTask = agentTask
    }

    var cpuCores: Double {
        max(cpuPercent, 0) / 100
    }

    var kind: MachineActivityKind {
        let normalizedName = processName.lowercased()

        if normalizedName.contains("codex") {
            return .codex
        }
        if normalizedName == "claude" {
            return .claudeCode
        }
        if normalizedName.contains("clang")
            || normalizedName.contains("swift-frontend")
            || normalizedName == "rustc"
        {
            return .compiling
        }
        if normalizedName == "ninja"
            || normalizedName == "xcodebuild"
            || normalizedName == "swiftc"
            || normalizedName == "cargo"
            || normalizedName == "make"
        {
            return .building
        }
        if normalizedName.contains("qemu")
            || normalizedName.contains("virtualmachine")
        {
            return .virtualMachine
        }
        if normalizedName.contains("chromium")
            || normalizedName.contains("chrome")
            || normalizedName.contains("safari")
        {
            return .browser
        }
        if normalizedName == "zellij"
            || normalizedName == "terminal"
            || normalizedName == "iterm2"
        {
            return .terminal
        }
        if normalizedName == "mds" || normalizedName == "mds_stores" {
            return .indexing
        }
        if normalizedName == "windowserver" {
            return .desktop
        }
        return .other
    }

    var shortLabel: LocalizedStringResource {
        return switch kind {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        case .compiling:
            if let contextName {
                "Compiling \(contextName)"
            } else {
                "Compiling software"
            }
        case .building:
            if let contextName {
                "Building \(contextName)"
            } else {
                "Building software"
            }
        case .virtualMachine: "Virtual machine"
        case .browser: "Browser"
        case .terminal:
            if let childProcessLabel {
                "\(terminalProcessLabel) · \(childProcessLabel)"
            } else {
                "\(terminalProcessLabel)"
            }
        case .indexing: "Indexing"
        case .desktop: "Desktop"
        case .other: "\(processName)"
        }
    }

    var symbolName: String {
        switch kind {
        case .codex, .claudeCode: "sparkles"
        case .compiling, .building: "hammer"
        case .virtualMachine: "rectangle.3.group"
        case .browser: "globe"
        case .terminal: "terminal"
        case .indexing: "magnifyingglass"
        case .desktop: "macwindow"
        case .other: "gearshape"
        }
    }

    var tooltip: LocalizedStringResource {
        if let agentTask {
            switch agentTask.status {
            case .active:
                return "\(agentTask.provider.displayName) is working in \(agentTask.projectName) — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
            case .recent:
                return "\(agentTask.provider.displayName) was recently active in \(agentTask.projectName) — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
            }
        }

        return switch kind {
        case .codex:
            "Codex is working — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
        case .claudeCode:
            "Claude Code is working — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
        case .compiling:
            if let contextName {
                "Compiling \(contextName) — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
            } else {
                "Compiling software — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
            }
        case .building:
            if let contextName {
                "Building \(contextName) — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
            } else {
                "Building software — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
            }
        case .virtualMachine:
            "Running a virtual machine — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
        case .browser:
            "Running a browser — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
        case .terminal:
            "\(shortLabel) — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
        case .indexing:
            "Indexing files — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
        case .desktop:
            "Displaying the desktop — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
        case .other:
            "\(processName) — \(cpuCores, format: .number.precision(.fractionLength(1 ... 2))) CPU cores"
        }
    }

    func addingContext(_ contextName: String?) -> MachineActivity {
        MachineActivity(
            processName: processName,
            cpuPercent: cpuPercent,
            processID: processID,
            contextName: contextName,
            childProcessName: childProcessName,
            agentTask: agentTask
        )
    }

    func addingChildProcessName(_ childProcessName: String?) -> MachineActivity {
        MachineActivity(
            processName: processName,
            cpuPercent: cpuPercent,
            processID: processID,
            contextName: contextName,
            childProcessName: childProcessName,
            agentTask: agentTask
        )
    }

    func addingAgentTask(_ agentTask: AgentTaskSummary?) -> MachineActivity {
        MachineActivity(
            processName: processName,
            cpuPercent: cpuPercent,
            processID: processID,
            contextName: contextName,
            childProcessName: childProcessName,
            agentTask: agentTask
        )
    }

    private var terminalProcessLabel: LocalizedStringResource {
        switch processName.lowercased() {
        case "zellij": "Zellij"
        case "iterm2": "iTerm"
        default: "Terminal"
        }
    }

    private var childProcessLabel: LocalizedStringResource? {
        guard let childProcessName else { return nil }
        let normalizedName = URL(fileURLWithPath: childProcessName)
            .lastPathComponent
            .lowercased()

        if normalizedName == "ssh" {
            return "SSH session"
        }
        if normalizedName.contains("codex") {
            return "Codex"
        }
        if normalizedName == "claude" {
            return "Claude Code"
        }
        return "\(URL(fileURLWithPath: childProcessName).lastPathComponent)"
    }
}

nonisolated enum MachineActivityParser {
    static let maximumHighlights = 3
    /// The machine page has room for a real list, so the sampler keeps more
    /// than the three the old hover strip could show.
    static let detailHighlights = 8
    static let defaultMinimumCPUPercent = 0.5

    private enum SummaryKey: Hashable {
        case category(MachineActivityKind)
        case process(String)
    }

    private struct Aggregate {
        var totalCPUPercent: Double
        var representative: MachineActivity
        var representativeCPUPercent: Double
    }

    private static let ignoredProcessNames = [
        "awk",
        "head",
        "ps",
        "sort",
    ]

    /// Orders by CPU, then by name.
    ///
    /// The name is not decoration: these activities come out of a Dictionary,
    /// whose iteration order is unspecified, and Swift's sort is not stable. Two
    /// processes reporting the same percentage would otherwise swap places from
    /// one sample to the next and the row would visibly flicker with nothing
    /// actually changing on the machine.
    static func isOrderedByCPU(
        _ lhs: MachineActivity,
        _ rhs: MachineActivity
    ) -> Bool {
        if lhs.cpuPercent != rhs.cpuPercent {
            return lhs.cpuPercent > rhs.cpuPercent
        }
        return lhs.processName.localizedCaseInsensitiveCompare(rhs.processName)
            == .orderedAscending
    }

    static func highlights(
        from processOutput: String,
        limit: Int = maximumHighlights,
        minimumCPUPercent: Double = defaultMinimumCPUPercent
    ) -> [MachineActivity] {
        guard limit > 0 else { return [] }

        let activities = processOutput
            .split(whereSeparator: \.isNewline)
            .compactMap { parseLine(String($0)) }
            .filter { !ignoredProcessNames.contains($0.processName.lowercased()) }
            .filter { $0.cpuPercent > 0 }

        var consolidated: [SummaryKey: Aggregate] = [:]
        for activity in activities {
            let key = summaryKey(for: activity)
            if var aggregate = consolidated[key] {
                aggregate.totalCPUPercent += activity.cpuPercent
                if activity.cpuPercent > aggregate.representativeCPUPercent {
                    aggregate.representative = activity
                    aggregate.representativeCPUPercent = activity.cpuPercent
                }
                consolidated[key] = aggregate
            } else {
                consolidated[key] = Aggregate(
                    totalCPUPercent: activity.cpuPercent,
                    representative: activity,
                    representativeCPUPercent: activity.cpuPercent
                )
            }
        }

        return consolidated.values
            .map { aggregate in
                MachineActivity(
                    processName: aggregate.representative.processName,
                    cpuPercent: aggregate.totalCPUPercent,
                    processID: aggregate.representative.processID
                )
            }
            .filter { $0.cpuPercent >= minimumCPUPercent }
            .sorted(by: isOrderedByCPU)
            .prefix(limit)
            .map(\.self)
    }

    private static func summaryKey(for activity: MachineActivity) -> SummaryKey {
        switch activity.kind {
        case .other:
            .process(activity.processName.lowercased())
        default:
            .category(activity.kind)
        }
    }

    static func parseLine(_ line: String) -> MachineActivity? {
        let fields = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(maxSplits: 2, whereSeparator: \.isWhitespace)

        guard fields.count >= 2,
              let cpuPercent = Double(fields[0])
        else {
            return nil
        }

        let processID: Int?
        let rawProcessName: String
        if fields.count == 3, let parsedProcessID = Int(fields[1]) {
            processID = parsedProcessID
            rawProcessName = String(fields[2])
        } else {
            processID = nil
            rawProcessName = fields.dropFirst().map(String.init).joined(separator: " ")
        }

        let processName = URL(fileURLWithPath: rawProcessName).lastPathComponent
        guard !processName.isEmpty else { return nil }

        return MachineActivity(
            processName: processName,
            cpuPercent: cpuPercent,
            processID: processID
        )
    }
}

nonisolated enum MachineActivityPrioritizer {
    static func select(
        from activities: [MachineActivity],
        agentTasks: [AgentTaskProvider: AgentTaskSummary],
        limit: Int = MachineActivityParser.maximumHighlights
    ) -> [MachineActivity] {
        guard limit > 0 else { return [] }

        var decoratedActivities = activities.map { activity in
            guard let provider = activity.kind.agentTaskProvider else {
                return activity
            }
            return activity.addingAgentTask(agentTasks[provider])
        }

        let orderedTasks = agentTasks
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map(\.value)
        for task in orderedTasks where task.status == .active {
            let alreadyRepresented = decoratedActivities.contains {
                $0.kind.agentTaskProvider == task.provider
            }
            guard !alreadyRepresented else { continue }

            decoratedActivities.append(
                MachineActivity(
                    processName: task.provider.processName,
                    cpuPercent: 0,
                    agentTask: task
                )
            )
        }

        let activeAgentActivities = decoratedActivities
            .filter { $0.agentTask?.status == .active }
            .sorted { lhs, rhs in
                let lhsDate = lhs.agentTask?.updatedAt ?? .distantPast
                let rhsDate = rhs.agentTask?.updatedAt ?? .distantPast
                if lhsDate == rhsDate {
                    return MachineActivityParser.isOrderedByCPU(lhs, rhs)
                }
                return lhsDate > rhsDate
            }

        var selected = Array(activeAgentActivities.prefix(limit))
        let selectedProviders = Set(
            selected.compactMap { $0.kind.agentTaskProvider }
        )
        let remainingCapacity = limit - selected.count
        guard remainingCapacity > 0 else { return selected }

        let heavyActivities = decoratedActivities
            .filter { activity in
                guard activity.cpuPercent
                    >= MachineActivityParser.defaultMinimumCPUPercent
                else {
                    return false
                }
                guard let provider = activity.kind.agentTaskProvider else {
                    return true
                }
                return !selectedProviders.contains(provider)
            }
            .sorted(by: MachineActivityParser.isOrderedByCPU)

        selected.append(contentsOf: heavyActivities.prefix(remainingCapacity))
        return selected
    }
}

nonisolated enum MachineActivityContext {
    /// Names the project a build process is working in, from its working
    /// directory.
    ///
    /// A build directory on its own is a useless label — `out`, `.build` and
    /// `DerivedData` say nothing about what is being built — so each rule walks
    /// back to a name a person would recognise.
    ///
    /// The rules run most-specific first and **the order is load-bearing**:
    /// `~/src/myapp/.build` has to resolve through the Swift-package rule to
    /// "Myapp", not through the source-tree rule to whatever contains `src`.
    /// Each rule has a test, so one that stops earning its keep can be deleted
    /// without having to guess what it was for.
    static func projectName(fromWorkingDirectory path: String) -> String? {
        let components = URL(fileURLWithPath: path)
            .standardizedFileURL
            .pathComponents
            .filter { $0 != "/" }
        guard !components.isEmpty else { return nil }

        if isHomeDirectory(components) { return nil }

        return agentWorktree(components)
            ?? derivedData(components)
            ?? sourceTreeWithBuildOutput(components)
            ?? swiftPackageBuild(components)
            ?? sourceTree(components)
            ?? lastMeaningfulComponent(components)
    }

    /// `…/little-herd/.claude/worktrees/feature` → the repository above it.
    private static func agentWorktree(_ components: [String]) -> String? {
        guard let claudeIndex = components.firstIndex(where: {
            $0.caseInsensitiveCompare(".claude") == .orderedSame
        }), claudeIndex > 0,
        components.indices.contains(claudeIndex + 1),
        components[claudeIndex + 1].caseInsensitiveCompare("worktrees")
            == .orderedSame
        else {
            return nil
        }
        return displayName(for: components[claudeIndex - 1])
    }

    /// `…/DerivedData/LittleHerd-abcdefgh/…` → the target, minus Xcode's hash.
    private static func derivedData(_ components: [String]) -> String? {
        guard let index = components.firstIndex(where: {
            $0.caseInsensitiveCompare("DerivedData") == .orderedSame
        }), components.indices.contains(index + 1) else {
            return nil
        }
        return displayName(
            for: removingDerivedDataHash(from: components[index + 1])
        )
    }

    /// A checkout that builds into a sibling directory, as Chromium and Ninja
    /// trees do: `…/chromium/src/out/Release` → what contains `src`.
    private static func sourceTreeWithBuildOutput(
        _ components: [String]
    ) -> String? {
        guard let index = sourceIndex(in: components), index > 0,
              components[(index + 1)...].contains(where: {
                  let normalized = $0.lowercased()
                  return normalized == "out" || normalized == "build"
              })
        else {
            return nil
        }
        return displayName(for: components[index - 1])
    }

    /// A Swift package: `…/myapp/.build/debug` → "Myapp". This has to be tried
    /// before the general `src` rule, or `~/src/myapp/.build` would be named
    /// after whatever contains `src`.
    private static func swiftPackageBuild(_ components: [String]) -> String? {
        guard let index = components.firstIndex(of: ".build"), index > 0 else {
            return nil
        }
        return displayName(for: components[index - 1])
    }

    /// Any other `src` checkout.
    private static func sourceTree(_ components: [String]) -> String? {
        guard let index = sourceIndex(in: components), index > 0 else {
            return nil
        }
        // Chromium's tree is deep enough that the directory above `src` is
        // often a scratch checkout name rather than the project.
        if components.contains(where: {
            $0.localizedCaseInsensitiveContains("chromium")
        }) {
            return "Chromium"
        }
        return displayName(for: components[index - 1])
    }

    /// Nothing matched: use the deepest component that names something, rather
    /// than a build directory.
    /// A session started in a home directory has no project, and naming it
    /// after the account is worse than saying nothing.
    ///
    /// `lastMeaningfulComponent` would answer "Clawd" for `/Users/clawd`,
    /// which is the account the panel is already scoped to — six sessions on
    /// the mini produced six rows all called Clawd, none of them telling you
    /// anything. Nil here, and the caller says so in its own words.
    private static func isHomeDirectory(_ components: [String]) -> Bool {
        guard components.count == 2 else { return false }
        return ["users", "home"].contains(components[0].lowercased())
    }

    private static func lastMeaningfulComponent(
        _ components: [String]
    ) -> String? {
        let ignored: Set<String> = [
            ".build",
            "bin",
            "build",
            "debug",
            "out",
            "products",
            "release",
            "release+asserts",
        ]
        guard let candidate = components.last(where: {
            !ignored.contains($0.lowercased())
        }) else {
            return nil
        }
        return displayName(for: candidate)
    }

    private static func sourceIndex(in components: [String]) -> Int? {
        components.lastIndex {
            $0.caseInsensitiveCompare("src") == .orderedSame
        }
    }

    private static func removingDerivedDataHash(from name: String) -> String {
        guard let separator = name.lastIndex(of: "-") else { return name }
        let suffix = name[name.index(after: separator)...]
        guard suffix.count >= 8,
              suffix.allSatisfy({ $0.isLetter || $0.isNumber })
        else {
            return name
        }
        return String(name[..<separator])
    }

    private static func displayName(for rawName: String) -> String? {
        var name = rawName
        if name.lowercased().hasSuffix("-work") {
            name.removeLast("-work".count)
        }

        let words = name
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .map(String.init)
        guard !words.isEmpty else { return nil }

        return words
            .map { word in
                guard let first = word.first else { return word }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}

nonisolated enum AgentTaskOutputParser {
    static func parse(_ output: String) -> [AgentTaskProvider: AgentTaskSummary] {
        var summaries: [AgentTaskProvider: AgentTaskSummary] = [:]

        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(
                separator: "\t",
                maxSplits: 3,
                omittingEmptySubsequences: false
            )
            guard fields.count == 4,
                  fields[0].hasPrefix("agent_task="),
                  let provider = AgentTaskProvider(
                      rawValue: String(fields[0].dropFirst("agent_task=".count))
                  ),
                  let status = AgentTaskStatus(rawValue: String(fields[1])),
                  let pathData = Data(base64Encoded: String(fields[3])),
                  let workingDirectory = String(data: pathData, encoding: .utf8),
                  let projectName = MachineActivityContext.projectName(
                      fromWorkingDirectory: workingDirectory
                  )
            else {
                continue
            }

            summaries[provider] = AgentTaskSummary(
                provider: provider,
                projectName: projectName,
                status: status,
                updatedAt: parseDate(String(fields[2]))
            )
        }

        for session in AgentSessionOutputParser.parse(output) {
            let summary = AgentTaskSummary(
                provider: session.provider,
                projectName: session.projectName,
                status: session.state == .active ? .active : .recent,
                updatedAt: session.updatedAt
            )
            guard let existing = summaries[session.provider] else {
                summaries[session.provider] = summary
                continue
            }
            if existing.status != .active && summary.status == .active
                || existing.status == summary.status
                    && (existing.updatedAt ?? .distantPast)
                    < (summary.updatedAt ?? .distantPast)
            {
                summaries[session.provider] = summary
            }
        }

        return summaries
    }

    private static func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }

        if let milliseconds = Double(value), milliseconds > 0 {
            return Date(timeIntervalSince1970: milliseconds / 1_000)
        }

        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        return ISO8601DateFormatter().date(from: value)
    }
}

nonisolated enum AgentTaskProbe {
    static let refreshInterval: Duration = .seconds(30)
    private static let logger = Logger(
        subsystem: "com.malpern.LittleHerd",
        category: "AgentTaskProbe"
    )

    static let shellCommand = #"""
    little_herd_now_ms=$(($(date +%s) * 1000))
    little_herd_active_window_ms=120000
    # How long a finished turn still counts as waiting for a person.
    #
    # "The agent finished its turn" is not "the session is over", and treating
    # them as the same made a session vanish the moment it answered you — the
    # exact moment somebody looks at the panel. Between your messages a session
    # is waiting for your next one, which is what this app has always meant by
    # waiting.
    #
    # Two hours, set by looking rather than by reasoning. Six was tried first
    # and put ten rows in the waiting group, several of them three hours old
    # and two of them the same job twice — a panel that had just been made lean
    # on purpose, refilled. Two hours covers the case this exists for, which is
    # the session you are talking to right now, and leaves anything you walked
    # away from where it was: tracked, counted in the header, and not listed.
    little_herd_recent_turn_ms=7200000
    little_herd_recent_window_ms=43200000

    # The Codex account limits, from the files Codex writes them into.
    #
    # An account-wide fact recorded per machine, and machines do not run Codex
    # equally — the mini runs emailtriage twice a day, this Mac when someone
    # opens it — so the freshest copy is worth having wherever it lives. The
    # newest six rollouts only: limits are appended to every one of them, and
    # reading the whole directory to learn one number would cost what a full
    # scan costs, every sample. Measured at 99 ms.
    if command -v jq >/dev/null 2>&1 && [ -d "$HOME/.codex/sessions" ]; then
      little_herd_rollouts=$(ls -t "$HOME"/.codex/sessions/*/*/*/*.jsonl 2>/dev/null | head -6)
      if [ -n "$little_herd_rollouts" ]; then
        printf '%s\n' "$little_herd_rollouts" | while IFS= read -r rollout; do
          little_herd_limit_line=$(grep '"primary":{' "$rollout" 2>/dev/null | tail -n 1)
          [ -n "$little_herd_limit_line" ] || continue
          printf '%s\n' "$little_herd_limit_line" | jq -r '
            .payload.rate_limits as $limits |
            [(.timestamp // ""),
             ($limits.primary.used_percent // -1),
             ($limits.primary.window_minutes // 0),
             ($limits.primary.resets_at // 0),
             ($limits.secondary.used_percent // -1),
             ($limits.secondary.window_minutes // 0),
             ($limits.secondary.resets_at // 0)] | @tsv' 2>/dev/null
        done | sort -r | head -n 1 | while IFS= read -r little_herd_limits; do
          [ -n "$little_herd_limits" ] || continue
          printf "agent_usage=codex\t%s\n" "$little_herd_limits"
        done
      fi
    fi

    # Which agents this account could actually run.
    #
    # Absolute paths, never the PATH. Measured on all three machines: not one
    # of them has `claude` or `codex` on the PATH a non-interactive ssh shell
    # sees, and all three have working binaries somewhere — inside an
    # application bundle on the Macs, in ~/.local/bin on the linux box. A probe
    # that asked `command -v` would report an empty herd.
    little_herd_agent_version() {
        # $1 provider, $2 path
        [ -x "$2" ] || return 0
        raw=$("$2" --version 2>/dev/null | head -1 | tr -d '\r')
        [ -n "$raw" ] || return 0
        # A mise shim answers --version with mise's own banner rather than the
        # agent's: "mise ~/.config/mise/config.toml tools: claude@2.1.234".
        # Measured on the linux box, where both agents are shims.
        case "$raw" in
          *"tools:"*)
            raw=$(printf '%s' "$raw" | sed 's/.*tools: *//' | cut -d' ' -f1)
            raw=$(printf '%s' "$raw" | sed 's/^[^@]*@//')
            ;;
        esac
        printf "agent_install=%s\t%s\t%s\n" "$1" \
          "$(printf '%s' "$raw" | base64 | tr -d '\n')" \
          "$(printf '%s' "$2" | base64 | tr -d '\n')"
    }
    # Which repositories this account has a checkout of.
    #
    # Read out of .git/config rather than by asking git, which means no process
    # per repository: 38 checkouts took 783 ms through `git remote get-url` and
    # 303 ms this way, for identical output. Scoped to the [remote "origin"]
    # section and not merely the first url in the file — one repository here
    # has a remote called "sites-origin", and taking the first url gave it a
    # different identity than git does.
    #
    # Matched later by the remote's slug rather than by directory name: this
    # herd has "keyboard-newswire" checked out in a directory called
    # "keyboard-wire", and the folder is not what the repository is.
    #
    # `find` rather than a glob, and this is the second time that lesson has had
    # to be learnt here. This script runs under zsh on a Mac, where a pattern
    # matching nothing is a *fatal* error that takes the whole script with it —
    # so a single empty ~/code cost every session in the AI panel, every agent
    # version, and, over ssh, the machine's entire metrics sample, because
    # `SSHCommandRunner` throws on a non-zero exit and the reading is discarded.
    # A machine would have read as down because a directory was empty. It
    # shipped in 0.1.33 and no machine in this herd happened to trip it.
    #
    # Depth three is the checkout's own `.git/config`, measured rather than
    # counted: two and four both find nothing while failing silently, which
    # looks exactly like an account with no repositories.
    for little_herd_root in "$HOME/local-code" "$HOME/code" "$HOME/src" "$HOME/Developer"; do
      [ -d "$little_herd_root" ] || continue
      find "$little_herd_root" -mindepth 3 -maxdepth 3 -type f \
        -path '*/.git/config' 2>/dev/null \
        | while IFS= read -r little_herd_config; do
        little_herd_checkout=${little_herd_config%/.git/config}
        little_herd_url=$(awk '
          /^[[:space:]]*\[remote "origin"\]/ { inorigin = 1; next }
          /^[[:space:]]*\[/ { inorigin = 0 }
          inorigin && /^[[:space:]]*url[[:space:]]*=/ {
            sub(/^[[:space:]]*url[[:space:]]*=[[:space:]]*/, ""); print; exit
          }' "$little_herd_config")
        [ -n "$little_herd_url" ] || continue
        printf "checkout=%s\t%s\n" \
          "$(printf '%s' "$little_herd_url" | sed 's#\.git$##' | sed 's#.*[/:]##')" \
          "$(printf '%s' "$little_herd_checkout" | base64 | tr -d '\n')"
      done
    done

    little_herd_agent_version claude "$HOME/.local/bin/claude"
    little_herd_agent_version codex "$HOME/.local/bin/codex"
    little_herd_agent_version codex "/Applications/ChatGPT.app/Contents/Resources/codex"

    # `find` rather than a glob, because this script runs under zsh, and zsh
    # aborts the *whole script* on a pattern that matches nothing — where sh
    # would pass it through harmlessly. A Mac without that application bundle
    # would have lost every session in the AI panel, not just its agent
    # version. The repo's own shell tests caught it, which is what they are
    # for. `find` also survives the space in "Application Support" that any
    # unquoted expansion of the result would not.
    find "$HOME/Library/Application Support/Claude/claude-code" \
      -maxdepth 5 -name claude -type f -perm -u+x 2>/dev/null \
      | while IFS= read -r little_herd_candidate; do
      little_herd_agent_version claude "$little_herd_candidate"
    done

    codex_db="$HOME/.codex/state_5.sqlite"
    if command -v sqlite3 >/dev/null 2>&1 && [ -r "$codex_db" ]; then
      codex_cutoff_ms=$((little_herd_now_ms - little_herd_recent_window_ms))
      sqlite3 -separator "$(printf '\t')" "$codex_db" "SELECT id, cwd, rollout_path, recency_at_ms FROM threads WHERE archived = 0 AND recency_at_ms >= $codex_cutoff_ms ORDER BY recency_at_ms DESC LIMIT 12;" 2>/dev/null | while IFS="$(printf '\t')" read -r codex_id codex_cwd codex_path codex_recency_ms; do
        if [ -n "$codex_id" ] && [ -n "$codex_cwd" ] && [ -n "$codex_recency_ms" ]; then
          codex_updated_ms=$codex_recency_ms
          codex_signal=""
          codex_completed=0
          codex_total=0
          codex_current=0
          codex_step64=""

          if [ -n "$codex_path" ] && [ -r "$codex_path" ]; then
            if [ "$(uname -s)" = "Darwin" ]; then
              codex_mtime=$(stat -f '%m' "$codex_path" 2>/dev/null)
            else
              codex_mtime=$(stat -c '%Y' "$codex_path" 2>/dev/null)
            fi
            codex_mtime_ms=$((codex_mtime * 1000))
            if [ "$codex_mtime_ms" -gt "$codex_updated_ms" ]; then codex_updated_ms=$codex_mtime_ms; fi

            if command -v jq >/dev/null 2>&1; then
              codex_signal=$(tail -n 180 "$codex_path" 2>/dev/null | jq -r '
                if .type == "event_msg" and .payload.type == "task_complete" then "completed"
                elif .type == "event_msg" and .payload.type == "turn_aborted" then "waiting"
                elif .type == "event_msg" and .payload.type == "agent_reasoning" then "working"
                elif .type == "response_item" and
                  (.payload.type == "reasoning" or .payload.type == "custom_tool_call" or .payload.type == "function_call") then "working"
                else empty end
              ' 2>/dev/null | tail -n 1)

              codex_plan=$(tail -n 500 "$codex_path" 2>/dev/null | jq -r '
                select(.type == "response_item" and
                  ((.payload.name // .name) == "update_plan")) |
                .payload.arguments
              ' 2>/dev/null | tail -n 1)
              if [ -n "$codex_plan" ]; then
                codex_progress=$(printf '%s' "$codex_plan" | jq -r '
                  (.plan // []) as $plan |
                  ($plan | to_entries) as $entries |
                  (($entries | map(select(.value.status == "in_progress")) | first)
                    // ($entries | map(select(.value.status == "pending")) | first)
                    // ($entries | last)
                    // {"key": -1, "value": {"step": ""}}) as $current |
                  [
                    ($entries | map(select(.value.status == "completed")) | length),
                    ($entries | length),
                    ($current.key + 1),
                    (($current.value.step // "") | @base64)
                  ] | @tsv
                ' 2>/dev/null)
              else
                codex_plan_input=$(tail -n 500 "$codex_path" 2>/dev/null | jq -sr '
                  [.[] | select(
                    .type == "response_item" and
                    .payload.type == "custom_tool_call" and
                    .payload.name == "exec" and
                    ((.payload.input // "") |
                      test("^const [A-Za-z_][A-Za-z0-9_]* = await tools\\.update_plan\\("))
                  )] | last | .payload.input // empty
                ' 2>/dev/null)
                if [ -n "$codex_plan_input" ]; then
                  codex_progress=$(printf '%s' "$codex_plan_input" | jq -Rrs '
                    [scan("\\{\\s*\"?step\"?\\s*:\\s*\"([^\"]+)\"\\s*,\\s*\"?status\"?\\s*:\\s*\"([^\"]+)\"") |
                      {step: .[0], status: .[1]}] as $plan |
                    ($plan | to_entries) as $entries |
                    (($entries | map(select(.value.status == "in_progress")) | first)
                      // ($entries | map(select(.value.status == "pending")) | first)
                      // ($entries | last)
                      // {"key": -1, "value": {"step": ""}}) as $current |
                    [
                      ($entries | map(select(.value.status == "completed")) | length),
                      ($entries | length),
                      ($current.key + 1),
                      (($current.value.step // "") | @base64)
                    ] | @tsv
                  ' 2>/dev/null)
                fi
              fi
              if [ -n "$codex_progress" ]; then
                IFS="$(printf '\t')" read -r codex_completed codex_total codex_current codex_step64 <<EOF
    $codex_progress
    EOF
              fi
            fi
          fi

          codex_age_ms=$((little_herd_now_ms - codex_updated_ms))
          if [ "$codex_signal" = "completed" ]; then
            if [ "$codex_age_ms" -ge 0 ] && [ "$codex_age_ms" -le "$little_herd_recent_turn_ms" ]; then
              codex_status=waiting
            else
              codex_status=completed
            fi
          elif [ "$codex_signal" = "waiting" ]; then
            codex_status=waiting
          elif [ "$codex_age_ms" -ge 0 ] && [ "$codex_age_ms" -le "$little_herd_active_window_ms" ]; then
            codex_status=active
          else
            codex_status=stalled
          fi
          codex_id64=$(printf '%s' "$codex_id" | base64 | tr -d '\n')
          codex_cwd64=$(printf "%s" "$codex_cwd" | base64 | tr -d '\n')
          # Codex records more about itself than Claude does: the size of the
          # context, the window it is allowed, the model, and the last tool it
          # called — all in the rollout this probe is already reading.
          codex_context=""
          codex_window=""
          codex_model=""
          codex_tool=""
          if [ -n "$codex_path" ] && [ -r "$codex_path" ] && command -v jq >/dev/null 2>&1; then
            codex_usage=$(tail -n 400 "$codex_path" 2>/dev/null | jq -r '
              select(.payload.type == "token_count") | .payload.info |
              select(. != null) |
              [(.last_token_usage.total_tokens // 0),
               (.model_context_window // 0)] | @tsv
            ' 2>/dev/null | tail -n 1)
            codex_context=$(printf '%s' "$codex_usage" | cut -f1)
            codex_window=$(printf '%s' "$codex_usage" | cut -f2)
            codex_model=$(tail -n 400 "$codex_path" 2>/dev/null | jq -r '
              select(.type == "turn_context") | .payload.model // empty
            ' 2>/dev/null | tail -n 1)
            codex_tool=$(tail -n 200 "$codex_path" 2>/dev/null | jq -r '
              select(.type == "response_item") |
              select(.payload.type == "custom_tool_call" or .payload.type == "function_call") |
              .payload.name // empty
            ' 2>/dev/null | tail -n 1)
          fi

          printf "agent_session=codex\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$codex_id64" "$codex_status" "$codex_updated_ms" "$codex_cwd64" \
            "$codex_completed" "$codex_total" "$codex_current" "$codex_step64" \
            "$codex_context" "" "$codex_tool" "" "$codex_model" "$codex_window"
        fi
      done
    fi

    # What each session is costing the machine it is on.
    #
    # A Claude session is a process, and its working directory is the one thing
    # that ties it back to a transcript — nothing in the process list names a
    # session. One lsof call covers every session on the machine (measured at
    # 42 ms), which is why this asks for all of them at once rather than once
    # per session. Matched on the claude-code binary path rather than on the
    # command name, or the desktop application answers to "claude" too and
    # would be reported as a session that does not exist.
    #
    # CPU is summed across the agent's whole process tree, not taken from the
    # agent alone. Measured on this Mac with a burner child under an agent:
    # the agent process read 1.0% of a core and its tree read 101.2%. An agent
    # waits on a model; a build, a test run and a grep over a large tree are
    # what cost the machine, and every one of them is a child. The figure
    # exists to answer which session is making this machine hot, and before
    # this it could not.
    #
    # One `ps` for the whole herd of processes, then every process walks up to
    # its nearest agent ancestor. Nearest, so a session that starts a session
    # is billed for its own work rather than its parent's.
    #
    # Resident size stays the agent's own, deliberately: summing it across a
    # tree double-counts every shared page, and a memory figure that is wrong
    # upward is worse than one that is narrow.
    if command -v lsof >/dev/null 2>&1; then
      little_herd_agent_pids=$(ps -Ao pid=,ppid=,rss=,time=,args= 2>/dev/null \
        | awk '
          {
            little_herd_seconds = 0
            little_herd_n = split($4, little_herd_parts, ":")
            for (i = 1; i <= little_herd_n; i++) {
              little_herd_seconds = little_herd_seconds * 60 + little_herd_parts[i]
            }
            parent[$1] = $2
            resident[$1] = $3
            own[$1] = little_herd_seconds
            order[++seen] = $1
            if ($0 ~ /claude-code\// && $3 > 20000) agent[$1] = 1
          }
          END {
            for (i = 1; i <= seen; i++) {
              pid = order[i]
              up = pid
              hops = 0
              while (hops < 32) {
                if (up in agent) { total[up] += own[pid]; break }
                if (!(up in parent)) break
                up = parent[up]
                hops++
              }
            }
            for (pid in agent) {
              printf "%s\t%s\t%.2f\n", pid, resident[pid], total[pid]
            }
          }')
      if [ -n "$little_herd_agent_pids" ]; then
        little_herd_pid_list=$(printf '%s\n' "$little_herd_agent_pids" \
          | cut -f1 | paste -sd, -)
        little_herd_cwds=$(/usr/sbin/lsof -a -d cwd -p "$little_herd_pid_list" -Fpn 2>/dev/null \
          | awk '/^p/ {pid=substr($0,2)} /^n/ {print pid"\t"substr($0,2)}')
        printf '%s\n' "$little_herd_agent_pids" | while IFS="$(printf '\t')" read -r pid rss cputime; do
          cwd=$(printf '%s\n' "$little_herd_cwds" | awk -F '\t' -v p="$pid" '$1 == p {print $2; exit}')
          [ -n "$cwd" ] || continue
          cwd64=$(printf '%s' "$cwd" | base64 | tr -d '\n')
          printf "agent_process=%s\t%s\t%s\t%s\n" "$pid" "$rss" "$cputime" "$cwd64"
        done

        # Whether each session's work is anywhere but this disk.
        #
        # A session's working directory is a checkout, and three facts about it
        # decide whether the work could move: the branch it is on, how much is
        # uncommitted, and how much is committed but unpushed. The last two are
        # what a summary forgets and a transfer has to carry — a target machine
        # can fetch a branch and cannot fetch what was never pushed.
        #
        # Asked of the directories the running sessions are actually in, which
        # lsof has just produced, and only once each. Measured at about 126 ms
        # for three, which is cheap at the agent probe's cadence and would not
        # be at every sample.
        if command -v git >/dev/null 2>&1; then
          printf '%s\n' "$little_herd_cwds" | cut -f2- | sort -u \
            | while IFS= read -r dir; do
            [ -n "$dir" ] && [ -d "$dir" ] || continue
            branch=$(git -C "$dir" branch --show-current 2>/dev/null)
            [ -n "$branch" ] || continue
            slug=$(git -C "$dir" remote get-url origin 2>/dev/null \
              | sed 's#\.git$##' | sed 's#.*[/:]##')
            dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
            ahead=$(git -C "$dir" rev-list --count '@{u}..HEAD' 2>/dev/null)
            # No upstream is not zero unpushed commits: it means the branch
            # exists nowhere else at all, which is the strongest form of "this
            # cannot be fetched from anywhere".
            [ -n "$ahead" ] || ahead=-1
            printf "repo_state=%s\t%s\t%s\t%s\t%s\n" \
              "$(printf '%s' "$dir" | base64 | tr -d '\n')" \
              "$(printf '%s' "$branch" | base64 | tr -d '\n')" \
              "$dirty" "$ahead" \
              "$(printf '%s' "$slug" | base64 | tr -d '\n')"
          done
        fi
      fi
    fi

    if command -v jq >/dev/null 2>&1 && [ -d "$HOME/.claude/projects" ]; then
      if [ "$(uname -s)" = "Darwin" ]; then
        claude_candidates=$(find "$HOME/.claude/projects" -type f -name '*.jsonl' -mtime -1 -exec stat -f '%m %N' {} \; 2>/dev/null | sort -nr | head -n 12)
      else
        claude_candidates=$(find "$HOME/.claude/projects" -type f -name '*.jsonl' -mtime -1 -exec stat -c '%Y %n' {} \; 2>/dev/null | sort -nr | head -n 12)
      fi

      printf '%s\n' "$claude_candidates" | while read -r claude_mtime claude_file; do
        if [ -n "$claude_file" ] && [ -r "$claude_file" ]; then
          claude_metadata=$(head -n 40 "$claude_file" 2>/dev/null | jq -rs '
            map(select((.cwd? | type) == "string" and (.sessionId? | type) == "string")) |
            first | [(.sessionId // ""), ((.cwd // "") | @base64)] | @tsv
          ' 2>/dev/null)
          IFS="$(printf '\t')" read -r claude_id claude_cwd64 <<EOF
    $claude_metadata
    EOF
          if [ -n "$claude_id" ] && [ -n "$claude_cwd64" ] && [ -n "$claude_mtime" ]; then
            claude_signal=$(tail -n 180 "$claude_file" 2>/dev/null | jq -r '
              if .type == "assistant" and .message.stop_reason == "end_turn" then "completed"
              elif .type == "assistant" or .type == "user" then "working"
              else empty end
            ' 2>/dev/null | tail -n 1)
            claude_age_ms=$((little_herd_now_ms - claude_mtime * 1000))
            if [ "$claude_signal" = "completed" ]; then
              # A turn that ended recently leaves the session waiting on you,
              # not finished. Only once it has been quiet for hours is it
              # history.
              if [ "$claude_age_ms" -ge 0 ] && [ "$claude_age_ms" -le "$little_herd_recent_turn_ms" ]; then
                claude_status=waiting
              else
                claude_status=completed
              fi
            elif [ "$claude_age_ms" -ge 0 ] && [ "$claude_age_ms" -le "$little_herd_active_window_ms" ]; then
              claude_status=active
            else
              # Last entry is a tool call and nothing has moved since. That is
              # a run that stopped part-way — killed, crashed, or the machine
              # slept — not one holding for your next message. Saying
              # "waiting" put fourteen dead runs of one scheduled job in the
              # group meant for things that need a person.
              claude_status=stalled
            fi

            # Every TaskCreate must be seen, not just recent ones. taskId is an
            # ordinal into creation order, so truncating the file to a tail drops
            # earlier creates and silently shifts every id onto the wrong task.
            # grep keeps this cheap: it is a few milliseconds even on a 38 MB
            # transcript, and only matching lines reach jq.
            claude_progress=$(grep -E '"(TaskCreate|TaskUpdate)"' "$claude_file" 2>/dev/null | jq -r '
              .message.content[]? |
              select(.type? == "tool_use") |
              if .name == "TaskCreate" then
                ["C", ((.input.subject // "") | @base64), ((.input.activeForm // .input.subject // "") | @base64), (.input.status // "pending")] | @tsv
              elif .name == "TaskUpdate" then
                ["U", (.input.taskId // ""), (.input.status // "")] | @tsv
              else empty end
            ' 2>/dev/null | awk -F '\t' '
              $1 == "C" {
                count++
                subject[count] = $2
                active[count] = $3
                status[count] = ($4 == "" ? "pending" : $4)
              }
              $1 == "U" {
                id = $2 + 0
                if (id > 0 && id <= count && $3 != "") status[id] = $3
              }
              END {
                if (count == 0) exit
                completed = 0
                current = 0
                for (i = 1; i <= count; i++) {
                  if (status[i] == "completed") completed++
                  if (current == 0 && status[i] == "in_progress") current = i
                }
                if (current == 0) {
                  for (i = 1; i <= count; i++) {
                    if (status[i] == "pending") { current = i; break }
                  }
                }
                if (current == 0) current = count
                step = status[current] == "in_progress" ? active[current] : subject[current]
                printf "%d\t%d\t%d\t%s", completed, count, current, step
              }
            ')
            claude_completed=0
            claude_total=0
            claude_current=0
            claude_step64=""
            if [ -n "$claude_progress" ]; then
              IFS="$(printf '\t')" read -r claude_completed claude_total claude_current claude_step64 <<EOF
    $claude_progress
    EOF
            fi

            # How much is in the model's context right now: the prompt of the
            # most recent assistant turn, which is what was cached plus what
            # was not. Read from the tail, because only the latest turn is the
            # current context — earlier turns describe a smaller conversation.
            claude_context=$(tail -n 400 "$claude_file" 2>/dev/null | jq -r '
              select(.type == "assistant") | .message.usage |
              select(. != null) |
              ((.input_tokens // 0) + (.cache_read_input_tokens // 0)
                + (.cache_creation_input_tokens // 0))
            ' 2>/dev/null | tail -n 1)

            # The session's own name, which is what the agent's own sidebar
            # shows: a title the user set, else the one the model wrote. Whole
            # file rather than the tail, because a title set early must not
            # expire out of view.
            claude_title=$(grep -o '"customTitle":"[^"]*"' "$claude_file" 2>/dev/null \
              | tail -n 1 | sed 's/^"customTitle":"//; s/"$//')
            if [ -z "$claude_title" ]; then
              claude_title=$(grep -o '"aiTitle":"[^"]*"' "$claude_file" 2>/dev/null \
                | tail -n 1 | sed 's/^"aiTitle":"//; s/"$//')
            fi
            claude_title64=$(printf '%s' "$claude_title" | base64 | tr -d '\n')

            # What it is doing, from the most recent tool call. Deliberately the
            # human description a tool call carries rather than its arguments:
            # a raw shell command in a menu-bar window is unreadable at this
            # width and can carry things that should not be on screen at all.
            claude_activity=$(tail -n 200 "$claude_file" 2>/dev/null | jq -r '
              select(.type == "assistant") | .message.content[]? |
              select(.type? == "tool_use") |
              [.name,
               ((.input.description
                 // (.input.file_path | if . then split("/") | last else null end)
                 // .input.pattern // .input.url // "") | tostring)] | @tsv
            ' 2>/dev/null | tail -n 1)
            claude_tool=$(printf '%s' "$claude_activity" | cut -f1)
            claude_detail64=$(printf '%s' "$claude_activity" | cut -f2- | base64 | tr -d '\n')

            # Which model, because the context a session may hold depends on it
            # and the limit is learned per model rather than assumed.
            claude_model=$(tail -n 200 "$claude_file" 2>/dev/null | jq -r '
              select(.type == "assistant") | .message.model // empty
            ' 2>/dev/null | tail -n 1)

            claude_id64=$(printf '%s' "$claude_id" | base64 | tr -d '\n')
            printf "agent_session=claude\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
              "$claude_id64" "$claude_status" "$((claude_mtime * 1000))" "$claude_cwd64" \
              "$claude_completed" "$claude_total" "$claude_current" "$claude_step64" \
              "$claude_context" "$claude_title64" "$claude_tool" "$claude_detail64" \
              "$claude_model" ""
          fi
        fi
      done
    fi
    """#

    static func readLocalSnapshot() async -> AgentProbeSnapshot {
        await readSnapshot()
    }

    /// `homeDirectory` exists so the shell itself can be tested against a
    /// fixture transcript tree. Production passes nil and reads the real home.
    static func readSnapshot(
        homeDirectory: String? = nil
    ) async -> AgentProbeSnapshot {
        let environment = homeDirectory.map { home -> [String: String] in
            var environment = ProcessInfo.processInfo.environment
            environment["HOME"] = home
            return environment
        }

        guard let output = await LocalProcessRunner.run(
            executablePath: "/bin/zsh",
            arguments: ["-c", shellCommand],
            environment: environment
        ) else {
            logger.error("The local task metadata probe did not complete")
            return .empty
        }

        let snapshot = AgentProbeSnapshot(
            tasksByProvider: AgentTaskOutputParser.parse(output),
            sessions: AgentResourceJoin.attach(
                repoStates: AgentRepoStateOutputParser.parse(output),
                to: AgentResourceJoin.attach(
                    processes: AgentProcessOutputParser.parse(output),
                    to: AgentSessionOutputParser.parse(output)
                )
            ),
            codexUsage: AgentUsageOutputParser.parse(output),
            destination: DestinationReport(
                installations: AgentInstallOutputParser.parse(output),
                checkouts: CheckoutOutputParser.parse(output)
            )
        )
        logger.debug(
            "Task metadata probe found \(snapshot.sessions.count) sessions"
        )
        return snapshot
    }
}

nonisolated extension MachineActivityKind {
    var agentTaskProvider: AgentTaskProvider? {
        switch self {
        case .codex: .codex
        case .claudeCode: .claude
        default: nil
        }
    }
}
