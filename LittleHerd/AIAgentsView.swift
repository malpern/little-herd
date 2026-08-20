import AppKit
import SwiftUI

struct AIAgentsView: View {
    let sessions: [MachineAgentSession]
    @Binding var hoveredAgentID: MachineAgentSession.ID?
    var onSelectMachine: ((MachineID) -> Void)?
    /// Where the load is, set against where the sessions are. Nil most of the
    /// time, and deliberately so — see `HerdWorkloadReader`.
    var workload: HerdWorkloadFinding?
    /// What each model has been measured to hold. Empty until a compaction has
    /// been watched, and then the rows can say how full they are.
    var contextLimits = AgentContextLimits()
    /// What each session is costing its machine, by session id.
    var agentCPU: [String: Double] = [:]
    /// What the focused machine's CPU is doing overall, so the header can put
    /// the sessions' shares against the whole.
    var machineCPUPercent: Double?
    /// Which machine these sessions are on. Named once, in the first header,
    /// because a panel scoped to one machine that never says which one is a
    /// panel you cannot trust.
    var machineName: String?

    /// Finished work starts collapsed. It is the majority of what a probe
    /// returns and the least useful thing on screen — six finished sessions
    /// used to carry the same weight as the one that was live.
    @State private var isShowingFinished = false

    private var layout: AgentPanelLayout {
        AgentPanelLayout.make(from: sessions, showingFinished: isShowingFinished)
    }

    var body: some View {
        if layout.isEmpty {
            AIAgentsEmptyState()
        } else {
            ScrollView {
                AIAgentPanelContent(
                    layout: layout,
                    workload: workload,
                    machineName: machineName,
                    contextLimits: contextLimits,
                    agentCPU: agentCPU,
                    machineCPUPercent: machineCPUPercent,
                    hoveredAgentID: $hoveredAgentID,
                    isShowingFinished: $isShowingFinished,
                    onSelectMachine: onSelectMachine
                )
            }
            // Was `.hidden`, which is why a list taller than the panel gave no
            // sign that it continued.
            .scrollIndicators(.automatic)
            .onDisappear {
                hoveredAgentID = nil
            }
        }
    }

}

/// The panel's rows, separated from the `ScrollView` that holds them.
///
/// Not a tidiness refactor: `ImageRenderer` lays out neither a `ScrollView` nor
/// a lazy stack, so with the rows inside both, the render harness produced a
/// blank image and reported success. Rendering this directly is what let anyone
/// see the panel at all. The stack is eager for the same reason — this list is
/// bounded to about ten rows, so laziness bought nothing and cost the ability
/// to look at it.
struct AIAgentPanelContent: View {
    let layout: AgentPanelLayout
    var workload: HerdWorkloadFinding?
    var machineName: String?
    var contextLimits = AgentContextLimits()
    var agentCPU: [String: Double] = [:]
    var machineCPUPercent: Double?
    @Binding var hoveredAgentID: MachineAgentSession.ID?
    @Binding var isShowingFinished: Bool
    var onSelectMachine: ((MachineID) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if let workload {
                HerdWorkloadRow(
                    finding: workload,
                    onSelectMachine: onSelectMachine
                )
            }

            runningHeader
            rows(layout.active)
            section("Waiting", rows: layout.waiting)

            if !layout.finished.isEmpty {
                FinishedSessionsDisclosure(
                    count: layout.finished.count,
                    isExpanded: $isShowingFinished
                )
                if isShowingFinished {
                    rows(layout.finished)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 3)
        // The last row used to sit flush against the bottom edge, so a clipped
        // row read as the end of the list.
        .padding(.bottom, 8)
    }

    /// The machine is named in the first header rather than in a row of its
    /// own, which would cost a line to say one word.
    private var runningTitle: LocalizedStringKey {
        guard let machineName else { return "Running" }
        return "Running on \(machineName)"
    }

    /// The whole, with the parts underneath it.
    ///
    /// The panel shows one machine, so its thermometer belongs at the top of
    /// the list of what is running on it — the same component, the same scale
    /// and the same colours as the CPU screen. Read together, the header says
    /// how hard the machine is working and the rows say which sessions are the
    /// reason, which is two screens' worth of the old answer in one line.
    @ViewBuilder
    private var runningHeader: some View {
        if !layout.active.isEmpty {
            HStack(spacing: 6) {
                Text(runningTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                // The machine's own bar, in the same column and the same
                // geometry as the sessions' — so the whole sits directly above
                // its parts and the two can be read against each other rather
                // than merely near each other.
                VStack(alignment: .trailing, spacing: 2) {
                    InlineSegmentedThermometer(value: machineCPUPercent)

                    Text(
                        machineCPUPercent.map {
                            "\(Int($0.rounded()))%"
                        } ?? " "
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .frame(
                    width: AIAgentRow.measureColumnWidth,
                    alignment: .trailing
                )
            }
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }

    @ViewBuilder
    private func section(
        _ title: LocalizedStringKey,
        rows sectionRows: [AgentPanelRow]
    ) -> some View {
        if !sectionRows.isEmpty {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .padding(.bottom, 2)
            rows(sectionRows)
        }
    }

    @ViewBuilder
    private func rows(_ panelRows: [AgentPanelRow]) -> some View {
        ForEach(panelRows) { row in
            Button {
                onSelectMachine?(row.session.machine)
            } label: {
                AIAgentRow(
                    row: row,
                    contextLimits: contextLimits,
                    cpuPercent: agentCPU[row.session.session.id]
                )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                if isHovered {
                    hoveredAgentID = row.id
                } else if hoveredAgentID == row.id {
                    hoveredAgentID = nil
                }
            }

            // Inset to where the titles begin — the dot column plus its
            // spacing — rather than to where a twenty-point icon used to end.
            Divider()
                .padding(.leading, 15)
        }
    }
}

/// The two halves of the app, said in one sentence.
///
/// Tapping it goes to the busy machine, because "which machine" is the next
/// question anyone reading this asks.
private struct HerdWorkloadRow: View {
    let finding: HerdWorkloadFinding
    var onSelectMachine: ((MachineID) -> Void)?

    var body: some View {
        Button {
            onSelectMachine?(finding.busyMachine)
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "scalemass")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .frame(width: 15, height: 15)

                Text(finding.sentence)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(finding.sentence))
    }
}

private struct FinishedSessionsDisclosure: View {
    let count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                Text("\(count) finished")
                    .font(.caption2.weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(count) finished sessions"))
        .accessibilityHint(Text(isExpanded ? "Collapse" : "Expand"))
    }
}

private struct AIAgentsEmptyState: View {
    var body: some View {
        ContentUnavailableView {
            Label("No recent agents", systemImage: "sparkles")
        } description: {
            Text("Codex and Claude activity will appear here.")
        }
        .foregroundStyle(.secondary)
    }
}

/// One session, laid out on the panel's grid.
///
/// Everything measured sits in a fixed trailing column, so the bars line up
/// down the panel and can be compared by eye. They used to follow the status
/// text, which is a different length on every row, so each one started
/// somewhere else and the column read as ragged — a bar you have to hunt for
/// is a bar doing none of the work a bar is for.
///
/// There is no application icon. It was twenty points of full colour, identical
/// on every row of a panel scoped to one machine, and it was the loudest thing
/// on a screen whose subject is the titles. Which agent a session belongs to
/// lives in the tooltip, where it is available and quiet, and a coloured dot
/// carries the state instead — the only per-row fact that changes.
struct AIAgentRow: View {
    let row: AgentPanelRow
    var contextLimits = AgentContextLimits()
    /// Share of a core since the last sample, when two readings exist.
    var cpuPercent: Double?

    /// One width for every measured thing in the panel, header included.
    static let measureColumnWidth: CGFloat = 58

    private var machineSession: MachineAgentSession { row.session }

    var body: some View {
        HStack(spacing: 8) {
            AgentStateDot(state: machineSession.session.state)
                .accessibilityLabel(Text(machineSession.session.state.title))

            VStack(alignment: .leading, spacing: 1) {
                // The session's own name, in the agent's own words — the same
                // string its sidebar shows, so a session is called one thing
                // wherever you meet it.
                Text(machineSession.session.displayTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Text(machineSession.session.statusLine)
                        .foregroundStyle(.secondary)

                    if let disambiguator = row.disambiguator {
                        Text(disambiguator)
                            .monospaced()
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                // Work on the top line, against the machine's own bar in the
                // header directly above it. Only above fifteen percent: every
                // session uses some CPU, and a number that is always there is
                // a number people stop reading.
                if let cpuPercent, cpuPercent >= 15 {
                    InlineSegmentedThermometer(value: cpuPercent)
                        .help("\(Int(cpuPercent.rounded()))% of a core")
                } else {
                    // Holds the line's height so the second line does not
                    // shuffle up and down between rows.
                    Color.clear.frame(width: 1, height: 9)
                }

                HStack(spacing: 4) {
                    // Only once this model has been watched compacting. Before
                    // that there is no honest denominator, and a percentage
                    // would be the invention this design exists to avoid.
                    if let fraction = contextLimits.fraction(
                        tokens: machineSession.session.contextTokens,
                        model: machineSession.session.model
                    ) {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .foregroundStyle(contextTint(for: fraction))
                    }

                    Text(Self.compactAge(of: machineSession.session.updatedAt))
                        .foregroundStyle(.tertiary)
                }
                .font(.caption2.monospacedDigit())
            }
            .frame(width: Self.measureColumnWidth, alignment: .trailing)
        }
        .frame(minHeight: 33)
        .contentShape(Rectangle())
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(machineSession.session.state.title))
    }

    /// Quiet until it matters. A context two-thirds full is not news; one that
    /// is about to compact is the moment to start a successor session, which is
    /// the whole reason this figure is on screen.
    private func contextTint(for fraction: Double) -> Color {
        switch fraction {
        case ..<0.75: Color.secondary
        case ..<0.9: Color.orange
        default: Color.red
        }
    }

    /// Just the number and a unit — "2m", "3h", "4d". The rail's own rail is
    /// the title; this is a glance, not a sentence.
    static func compactAge(of date: Date, now: Date = .now) -> String {
        let elapsed = max(now.timeIntervalSince(date), 0)
        if elapsed < 60 { return "now" }
        if elapsed < 3_600 { return "\(Int(elapsed / 60))m" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3_600))h" }
        return "\(Int(elapsed / 86_400))d"
    }

    private var helpText: Text {
        var parts = [
            String(localized: machineSession.session.provider.displayName),
            machineSession.session.projectName,
            machineSession.machineName,
            String(localized: machineSession.session.state.title),
        ]
        // Still measured, no longer given a column. It answers "which of these
        // is the heavy one", which is worth a hover and not worth the width
        // the title wants.
        if let context = machineSession.session.contextLabel {
            parts.append("\(context) in context")
        }
        return Text(parts.joined(separator: ", "))
    }

    private var accessibilityLabel: Text {
        let providerName = String(
            localized: machineSession.session.provider.displayName
        )
        let machineName = machineSession.machineName
        var label = "\(providerName), \(machineSession.session.projectName), \(machineName)"
        if let progress = machineSession.session.progress {
            label += ", step \(progress.currentStepIndex) of \(progress.totalStepCount)"
        }
        return Text(label)
    }
}

struct HoveredAgentHeader: View {
    let machineSession: MachineAgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HoveredAgentIdentityRow(machineSession: machineSession)

            HoveredAgentProgressRow(session: machineSession.session)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

private struct HoveredAgentIdentityRow: View {
    let machineSession: MachineAgentSession

    var body: some View {
        HStack(spacing: 5) {
            AgentProviderIcon(
                provider: machineSession.session.provider,
                size: 15
            )

            Text(machineSession.session.projectName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 5)

            Image(systemName: machineSession.machineSymbolName)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(machineSession.machineName)
                .font(.caption2)
                .foregroundStyle(.secondary)

            AgentSessionStatusIndicator(
                state: machineSession.session.state,
                includesLabel: true
            )
        }
    }
}

private struct HoveredAgentProgressRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 7) {
            if let progress = session.progress {
                AgentProgressRing(progress: progress, state: session.state)

                VStack(alignment: .leading, spacing: 0) {
                    Text(progress.currentStep)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(
                        "Step \(progress.currentStepIndex) of \(progress.totalStepCount)"
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: session.state == .waiting ? "clock" : "waveform.path")
                    .foregroundStyle(statusColor)
                    .frame(width: 27)

                VStack(alignment: .leading, spacing: 0) {
                    Text(progressUnavailableLabel)
                        .font(.caption.weight(.medium))

                    Text(session.updatedAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var progressUnavailableLabel: LocalizedStringResource {
        switch session.state {
        case .active: "Working — no structured plan"
        case .completed: "Finished — no structured plan"
        case .waiting: "Waiting — no structured plan"
        }
    }

    private var statusColor: Color {
        switch session.state {
        case .active: .green
        case .completed: .blue
        case .waiting: .orange
        }
    }
}

private struct AgentProgressRing: View {
    let progress: AgentSessionProgress
    let state: AgentSessionState

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.16), lineWidth: 2.5)

            Circle()
                .trim(from: 0, to: progress.fractionCompleted)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text("\(progress.currentStepIndex)/\(progress.totalStepCount)")
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .minimumScaleFactor(0.65)
        }
        .frame(width: 30, height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Agent progress")
        .accessibilityValue(
            "Step \(progress.currentStepIndex) of \(progress.totalStepCount)"
        )
    }

    private var ringColor: Color {
        switch state {
        case .active: .green
        case .completed: .blue
        case .waiting: .orange
        }
    }
}

/// State as a single dot at the leading edge.
///
/// Small, and the only coloured thing on a row that is otherwise text. Running
/// is filled and green; waiting is an open ring, which reads as unfinished
/// without shouting; finished is a faint dot that gets out of the way. Shape
/// carries the difference as well as colour, so the three are still distinct
/// where colour is not.
private struct AgentStateDot: View {
    let state: AgentSessionState

    var body: some View {
        Group {
            switch state {
            case .active:
                Circle().fill(Color.green)
            case .waiting:
                Circle().strokeBorder(Color.orange, lineWidth: 1.5)
            case .completed:
                Circle().fill(Color.secondary.opacity(0.35))
            }
        }
        .frame(width: 7, height: 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(state.title))
    }
}

/// State, at the leading edge, with a shape of its own.
///
/// Deliberately a glyph and not a word. The section header above the row
/// already says "Needs you" or "Running", so a text badge on every row would
/// repeat it — and this panel is 300 points wide, where the width a badge costs
/// comes straight out of the project name, which is the part that identifies
/// the row. What the old indicator got wrong was not its size but its position
/// and its vocabulary: a dot in the right gutter, the same shape for waiting
/// and for finished, differing only in colour. These differ in shape.
private struct AgentStateBadge: View {
    let state: AgentSessionState

    var body: some View {
        Image(systemName: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 15, height: 15)
            .background(tint.opacity(0.15), in: Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(state.title))
    }

    private var symbol: String {
        switch state {
        case .waiting: "hand.raised.fill"
        case .active: "waveform"
        case .completed: "checkmark"
        }
    }

    private var tint: Color {
        switch state {
        case .waiting: .orange
        case .active: .green
        case .completed: .secondary
        }
    }
}

private struct AgentSessionStatusIndicator: View {
    let state: AgentSessionState
    var includesLabel = false

    var body: some View {
        HStack(spacing: 3) {
            switch state {
            case .active:
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
            case .completed:
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            case .waiting:
                Image(systemName: "clock")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }

            if includesLabel {
                Text(state.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(state.title))
    }
}

private struct AgentProviderIcon: View {
    let provider: AgentTaskProvider
    let size: Double

    var body: some View {
        Image(nsImage: AgentProviderIcons.icon(for: provider))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            .accessibilityLabel(Text(provider.displayName))
    }
}

@MainActor
private enum AgentProviderIcons {
    // Looked up on each use rather than cached in a `static let`.
    //
    // A stored static is computed once, on first access. That happened during
    // early launch, before NSWorkspace could answer properly, and the generic
    // placeholder it returned was then kept for the life of the process — which
    // is why these rows have been blank squares. Asking again is cheap;
    // NSWorkspace keeps its own cache.
    static var chatGPT: NSImage {
        appIcon(
            bundleIdentifiers: ["com.openai.chat", "com.openai.codex"],
            fallbackSymbolName: "sparkles"
        )
    }

    static var claudeCode: NSImage {
        appIcon(
            bundleIdentifiers: [
                "com.anthropic.claude-code",
                "com.anthropic.claudefordesktop",
                "com.anthropic.claude",
            ],
            fallbackSymbolName: "brain.head.profile"
        )
    }

    static func icon(for provider: AgentTaskProvider) -> NSImage {
        switch provider {
        case .codex: chatGPT
        case .claude: claudeCode
        }
    }

    /// Reads the icon out of the application bundle rather than asking
    /// NSWorkspace for it.
    ///
    /// `NSWorkspace.icon(forFile:)` resolves these apps correctly from a
    /// standalone process — verified, 32 representations each — and appears to
    /// return a generic placeholder from inside this one, so this reads the
    /// `.icns` the bundle already contains instead.
    ///
    /// NOTE: this did not restore the agent-row icons, so the real cause is
    /// still open.
    private static func appIcon(
        bundleIdentifiers: [String],
        fallbackSymbolName: String
    ) -> NSImage {
        for bundleIdentifier in bundleIdentifiers {
            guard let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
            ) else {
                continue
            }
            if let icon = iconFromBundle(at: applicationURL) { return icon }

            // Worth trying anyway: on a machine where it does work, this is the
            // icon the user actually sees in the Dock.
            let workspaceIcon = NSWorkspace.shared.icon(forFile: applicationURL.path)
            if !workspaceIcon.representations.isEmpty { return workspaceIcon }
        }

        return NSImage(
            systemSymbolName: fallbackSymbolName,
            accessibilityDescription: nil
        ) ?? NSImage()
    }

    private static func iconFromBundle(at applicationURL: URL) -> NSImage? {
        let resources = applicationURL.appendingPathComponent("Contents/Resources")

        // `CFBundleIconFile` may or may not carry the extension, and apps that
        // ship their icon in an asset catalog name it something else entirely —
        // so fall back to whatever .icns the bundle has.
        var candidates: [String] = []
        if let declared = Bundle(url: applicationURL)?
            .object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            candidates.append(
                declared.hasSuffix(".icns") ? declared : declared + ".icns"
            )
        }
        candidates += (try? FileManager.default.contentsOfDirectory(
            atPath: resources.path
        ))?.filter { $0.hasSuffix(".icns") } ?? []

        for name in candidates {
            let url = resources.appendingPathComponent(name)
            if let image = NSImage(contentsOf: url),
               !image.representations.isEmpty {
                return image
            }
        }
        return nil
    }
}
