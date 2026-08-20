import AppKit
import SwiftUI

struct AIAgentsView: View {
    let sessions: [MachineAgentSession]
    @Binding var hoveredAgentID: MachineAgentSession.ID?
    var onSelectMachine: ((MachineID) -> Void)?
    /// Where the load is, set against where the sessions are. Nil most of the
    /// time, and deliberately so — see `HerdWorkloadReader`.
    var workload: HerdWorkloadFinding?

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

            section("Needs you", rows: layout.waiting)
            section("Running", rows: layout.active)

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
                .padding(.top, 6)
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
                AIAgentRow(row: row)
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

            Divider()
                .padding(.leading, 38)
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

struct AIAgentRow: View {
    let row: AgentPanelRow

    private var machineSession: MachineAgentSession { row.session }

    var body: some View {
        HStack(spacing: 8) {
            ApplicationIcon(
                bundlePath: ApplicationIconCache.bundlePath(
                    forAnyOf: machineSession.session.provider.bundleIdentifiers
                ),
                fallbackSymbol: "sparkles",
                tint: machineSession.session.provider == .codex ? .green : .orange,
                size: 20
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    // State leads the row and is spelled out. It was a
                    // six-pixel dot in the right gutter, where waiting and
                    // finished were the same shape in two colours — so the
                    // most actionable thing the app knows was also the least
                    // visible thing on the row.
                    AgentStateBadge(state: machineSession.session.state)

                    Text(machineSession.session.projectName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let disambiguator = row.disambiguator {
                        Text(disambiguator)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }

                // Several sessions can share a project and a machine, so the
                // row has to say which one it is: what it is doing, or when it
                // last did anything.
                Text(sessionDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                // How much conversation the model is carrying. Not a bar and
                // not a percentage — see `AgentSession.contextTokens` for why
                // there is no honest denominator to divide by.
                if let context = machineSession.session.contextLabel {
                    Text(context)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .help("\(context) tokens in this session’s context")
                }

                if let progress = machineSession.session.progress {
                    Text("\(progress.currentStepIndex)/\(progress.totalStepCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .fixedSize()
        }
        .frame(minHeight: 33)
        .contentShape(Rectangle())
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(machineSession.session.state.title))
    }

    /// The step it is on when it publishes one, otherwise how long since it
    /// last moved — either way, something that differs between sessions.
    private var sessionDetail: String {
        let machine = machineSession.machineName
        if let step = machineSession.session.progress?.currentStep, !step.isEmpty {
            return "\(machine) · \(step)"
        }
        return "\(machine) · \(Self.relativeAge(of: machineSession.session.updatedAt))"
    }

    /// Days once it has been days.
    ///
    /// Hours and minutes alone turn a session from last week into "213h ago",
    /// which is a number nobody converts in their head — seen in the render
    /// harness, where a fixture from an earlier era printed "224,466h 53m ago"
    /// and made the defect obvious at a glance.
    static func relativeAge(of date: Date, now: Date = .now) -> String {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "just now" }
        let allowed: Set<Duration.UnitsFormatStyle.Unit> = elapsed >= 86_400
            ? [.days, .hours]
            : [.hours, .minutes]
        return Duration.seconds(elapsed)
            .formatted(.units(allowed: allowed, width: .narrow)) + " ago"
    }

    private var helpText: Text {
        Text(
            "\(machineSession.session.provider.displayName), \(machineSession.session.projectName), \(machineSession.machineName), \(machineSession.session.state.title)"
        )
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
