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
    static func projectName(fromWorkingDirectory path: String) -> String? {
        let components = URL(fileURLWithPath: path)
            .standardizedFileURL
            .pathComponents
            .filter { $0 != "/" }
        guard !components.isEmpty else { return nil }

        if let claudeIndex = components.firstIndex(where: {
            $0.caseInsensitiveCompare(".claude") == .orderedSame
        }), claudeIndex > 0,
           components.indices.contains(claudeIndex + 1),
           components[claudeIndex + 1].caseInsensitiveCompare("worktrees")
            == .orderedSame
        {
            return displayName(for: components[claudeIndex - 1])
        }

        if let derivedDataIndex = components.firstIndex(where: {
            $0.caseInsensitiveCompare("DerivedData") == .orderedSame
        }), components.indices.contains(derivedDataIndex + 1) {
            return displayName(for: removingDerivedDataHash(
                from: components[derivedDataIndex + 1]
            ))
        }

        if let sourceIndex = components.lastIndex(where: {
            $0.caseInsensitiveCompare("src") == .orderedSame
        }), sourceIndex > 0,
           components[(sourceIndex + 1)...].contains(where: {
               let normalized = $0.lowercased()
               return normalized == "out" || normalized == "build"
           })
        {
            return displayName(for: components[sourceIndex - 1])
        }

        if let swiftBuildIndex = components.firstIndex(where: { $0 == ".build" }),
           swiftBuildIndex > 0
        {
            return displayName(for: components[swiftBuildIndex - 1])
        }

        if let sourceIndex = components.lastIndex(where: {
            $0.caseInsensitiveCompare("src") == .orderedSame
        }), sourceIndex > 0 {
            if components.contains(where: {
                $0.localizedCaseInsensitiveContains("chromium")
            }) {
                return "Chromium"
            }
            return displayName(for: components[sourceIndex - 1])
        }

        let ignoredComponents = Set([
            ".build",
            "bin",
            "build",
            "debug",
            "out",
            "products",
            "release",
            "release+asserts",
        ])
        guard let candidate = components.last(where: {
            !ignoredComponents.contains($0.lowercased())
        }) else {
            return nil
        }
        return displayName(for: candidate)
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
    little_herd_recent_window_ms=43200000

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
            codex_status=completed
          elif [ "$codex_signal" = "waiting" ]; then
            codex_status=waiting
          elif [ "$codex_age_ms" -ge 0 ] && [ "$codex_age_ms" -le "$little_herd_active_window_ms" ]; then
            codex_status=active
          else
            codex_status=waiting
          fi
          codex_id64=$(printf '%s' "$codex_id" | base64 | tr -d '\n')
          codex_cwd64=$(printf "%s" "$codex_cwd" | base64 | tr -d '\n')
          printf "agent_session=codex\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$codex_id64" "$codex_status" "$codex_updated_ms" "$codex_cwd64" \
            "$codex_completed" "$codex_total" "$codex_current" "$codex_step64"
        fi
      done
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
              claude_status=completed
            elif [ "$claude_age_ms" -ge 0 ] && [ "$claude_age_ms" -le "$little_herd_active_window_ms" ]; then
              claude_status=active
            else
              claude_status=waiting
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

            claude_id64=$(printf '%s' "$claude_id" | base64 | tr -d '\n')
            printf "agent_session=claude\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
              "$claude_id64" "$claude_status" "$((claude_mtime * 1000))" "$claude_cwd64" \
              "$claude_completed" "$claude_total" "$claude_current" "$claude_step64"
          fi
        fi
      done
    fi
    """#

    static func readLocalSnapshot() async -> AgentProbeSnapshot {
        guard let output = await LocalProcessRunner.run(
            executablePath: "/bin/zsh",
            arguments: ["-c", shellCommand]
        ) else {
            logger.error("The local task metadata probe did not complete")
            return .empty
        }

        let snapshot = AgentProbeSnapshot(
            tasksByProvider: AgentTaskOutputParser.parse(output),
            sessions: AgentSessionOutputParser.parse(output)
        )
        logger.debug(
            "Task metadata probe found \(snapshot.sessions.count) sessions"
        )
        return snapshot
    }

    static func readLocal() async -> [AgentTaskProvider: AgentTaskSummary] {
        await readLocalSnapshot().tasksByProvider
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
