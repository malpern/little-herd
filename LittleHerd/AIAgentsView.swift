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
    var compactionThresholds = AgentCompactionThresholds()
    /// What each session is costing its machine, by session id.
    var agentCPU: [String: Double] = [:]
    /// When each session last compacted, by session id.
    var agentCompactedAt: [String: Date] = [:]
    /// Which machine these sessions are on. Named once, in the first header,
    /// because a panel scoped to one machine that never says which one is a
    /// panel you cannot trust.
    var machineName: String?
    /// The rest of the herd, for the one question a parked session raises.
    /// Empty in a herd of one, and then the section never appears.

    /// Which groups are folded. Every section folds, not only the finished
    /// one — a panel where one header behaves differently from its neighbours
    /// teaches people that headers are decoration.
    ///
    /// Finished is not a group here any more. It was the majority of what a
    /// probe returns and the least useful thing on screen — folded away by
    /// default, which is most of the way to admitting it should not be a
    /// section at all. The header still counts those sessions as tracked, so
    /// nothing has stopped being watched; the panel has stopped listing them.
    ///
    /// Destinations starts folded too, and for a different reason. Expanded, it
    /// listed every machine that could not take the work — and a list of
    /// reasons nobody asked for reads as the app complaining that it needs
    /// something, which is how the first person to see it read it. Where a
    /// session could go is a question you ask, so the header asks it and the
    /// answers are one click away.
    @State private var collapsed: Set<AgentPanelSection> = []

    private var layout: AgentPanelLayout {
        AgentPanelLayout.make(from: sessions, showingFinished: false)
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
                    compactionThresholds: compactionThresholds,
                    agentCPU: agentCPU,
                    agentCompactedAt: agentCompactedAt,
                    hoveredAgentID: $hoveredAgentID,
                    collapsed: $collapsed,
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
    var compactionThresholds = AgentCompactionThresholds()
    var agentCPU: [String: Double] = [:]
    var agentCompactedAt: [String: Date] = [:]
    @Binding var hoveredAgentID: MachineAgentSession.ID?
    @Binding var collapsed: Set<AgentPanelSection>
    var onSelectMachine: ((MachineID) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if let workload {
                HerdWorkloadRow(
                    finding: workload,
                    onSelectMachine: onSelectMachine
                )
            }

            section(.running, label: machineName, rows: layout.active)
            section(.waiting, rows: layout.waiting)
        }
        .padding(.horizontal, 14)
        .padding(.top, 3)
        // The last row used to sit flush against the bottom edge, so a clipped
        // row read as the end of the list.
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func section(
        _ section: AgentPanelSection,
        label: String? = nil,
        rows sectionRows: [AgentPanelRow]
    ) -> some View {
        if !sectionRows.isEmpty {
            AgentSectionHeader(
                section: section,
                label: label,
                hiddenCount: sectionRows.count,
                isExpanded: Binding(
                    get: { !collapsed.contains(section) },
                    set: { expanded in
                        if expanded {
                            collapsed.remove(section)
                        } else {
                            collapsed.insert(section)
                        }
                    }
                )
            )
            if !collapsed.contains(section) {
                rows(sectionRows)
            }
        }
    }


    @ViewBuilder
    private func rows(_ panelRows: [AgentPanelRow]) -> some View {
        ForEach(panelRows) { row in
            Button {
                onSelectMachine?(row.session.machine)
            } label: {
                AIActiveAgentRow(
                    row: row,
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

            // Inset to where the titles begin, so the dividers, the section
            // headers and the titles share one vertical line.
            Divider()
                .padding(.leading, AgentRowMetrics.titleInset)
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
/// **Type.** Title and status used to be `.caption` and `.caption2`, which on
/// macOS are both about ten points — the same size, distinguished only by
/// colour, which is why the row read as flat however the pieces were arranged.
/// Hierarchy is built from size, weight and colour together: twelve-point
/// medium against ten-point regular secondary is a step you can see before you
/// read either of them. Semantic styles rather than fixed points, so the panel
/// follows the system text size instead of ignoring it.
///
/// **Grid.** Everything measured sits in one trailing column, and the meter is
/// pulled onto the title's baseline rather than floating at the top of its
/// stack — a bar that sits a point or two off the line it belongs to is the
/// kind of thing you feel without being able to name.
///
/// **Restraint.** No application icon: twenty points of full colour, identical
/// on every row of a panel scoped to one machine, saying the same word over and
/// over. A seven-point dot carries the state, which is the only per-row fact
/// that changes.
/// The measurements every row in this panel shares, and the one piece of
/// formatting all of them need.
///
/// What is left of `AIAgentRow` after the panel was redrawn around
/// `AIActiveAgentRow`. The row itself went; these three outlived it because
/// other views were already reaching into it for them, and a two-hundred-line
/// view kept alive as a namespace for three constants is the dead code this
/// project keeps rediscovering.
nonisolated enum AgentRowMetrics {
    /// The share of *the machine* below which a session's meter stays empty.
    ///
    /// Set from measurement, twice over. Fifteen percent was an estimate and
    /// nothing ever reached it. Five was a correction made against a figure
    /// that turned out to be measuring the agent binary rather than the work
    /// it starts. With the figure fixed and stated against the machine, three
    /// sessions on this ten-core Mac idled at 0.13–0.20% and a child process
    /// doing real work reached 0.58%; a whole core is 10%.
    ///
    /// Two percent is a fifth of a core here — enough that the session is
    /// plainly doing something, low enough that it lights up long before the
    /// machine is in trouble. The rule it enforces has not changed since the
    /// first guess: a mark that is always lit is a mark nobody reads.
    static let meterFloorPercent: Double = 2

    /// The leading column: the mark plus the space to the title. Dividers and
    /// section headers inset to this, so one vertical line runs down the panel.
    static let titleInset: CGFloat = 15

    /// Just the number and a unit — "2m", "3h", "4d". This is a glance, not a
    /// sentence.
    static func compactAge(of date: Date, now: Date = .now) -> String {
        let elapsed = max(now.timeIntervalSince(date), 0)
        if elapsed < 60 { return "now" }
        if elapsed < 3_600 { return "\(Int(elapsed / 60))m" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3_600))h" }
        return "\(Int(elapsed / 86_400))d"
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

/// The panel's three groups, so collapse state has something to key on.
nonisolated enum AgentPanelSection: String, CaseIterable, Sendable {
    case running
    case waiting
    /// Where a parked session could go, and why the rest of the herd could
    /// not. Not a group of sessions like the other three, but it folds the
    /// same way — a header that behaves differently from its neighbours
    /// teaches people that headers are decoration.
    case destinations
    case finished

    /// A glyph does the naming. "Waiting" as a word was being said twice — once
    /// in the header and again under every row beneath it — and once the rows
    /// stopped repeating it, the header did not need to spell it either. The
    /// symbols are the ones these states are drawn with everywhere else: a
    /// waveform for work in progress, a clock for something parked, a check for
    /// something done.
    var symbolName: String {
        switch self {
        case .running: "waveform"
        case .waiting: "clock"
        case .destinations: "arrowshape.turn.up.right"
        case .finished: "checkmark"
        }
    }

    /// The word beside the glyph. Nil for the running group, which is named
    /// after its machine by whoever builds the header.
    var name: String? {
        switch self {
        case .running: nil
        case .waiting: "Waiting"
        case .destinations: "Destinations"
        case .finished: "Finished"
        }
    }

    /// Said in full for anyone who cannot see the glyph.
    var accessibleName: LocalizedStringResource {
        switch self {
        case .running: "Running"
        case .waiting: "Waiting"
        case .destinations: "Destinations"
        case .finished: "Finished"
        }
    }
}

private struct AgentSectionHeader: View {
    let section: AgentPanelSection
    /// What the section is called, beside its glyph.
    ///
    /// For a while only the running group was named — on the argument that a
    /// word restating a glyph is the repetition this panel kept being trimmed
    /// of. Reversed on being looked at: folded, the sections collapse to a
    /// bare symbol and a number, and a column of those is a puzzle rather than
    /// a summary. The glyph carries the state at a glance and the word says
    /// which state it is; only one of those survives folding.
    ///
    /// Running still names its machine instead, because that is the thing its
    /// glyph cannot say.
    var label: String?
    /// Shown only when folded, because a count you cannot see the items behind
    /// is the one time the number does any work.
    let hiddenCount: Int
    @Binding var isExpanded: Bool

    @State private var isHovered = false

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: section.symbolName)
                    .font(.caption2.weight(.semibold))
                    .frame(width: 11)

                if let label = label ?? section.name {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        // Positive tracking at this size, per the same rule
                        // that tightens large text: small type reads as
                        // cramped without it.
                        .tracking(0.3)
                }

                if !isExpanded, hiddenCount > 0 {
                    Text("\(hiddenCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .opacity(isHovered ? 1 : 0)
            }
            .foregroundStyle(.secondary)
            .padding(.leading, AgentRowMetrics.titleInset)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            label.map { Text("\(String(localized: section.accessibleName)), \($0)") }
                ?? Text(section.accessibleName)
        )
        .accessibilityHint(isExpanded ? "Collapse" : "Expand")
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
enum AgentProviderIcons {
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
        let urls = bundleIdentifiers.compactMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }

        // Every identifier gets asked for a real icon before any of them is
        // allowed to answer with a generic one. Two passes rather than one,
        // and the reason is the blank squares these rows have been showing.
        //
        // `com.anthropic.claude-code` resolves — to the `claude.app` wrapper
        // inside Claude Code's support directory, which carries no
        // `CFBundleIconFile` at all. So `iconFromBundle` rightly declines, and
        // then `NSWorkspace.icon(forFile:)` hands back the generic application
        // placeholder. That is never empty, so the old single pass returned it
        // and never reached `com.anthropic.claudefordesktop`, which has the
        // icon everyone actually recognises. One identifier with no icon was
        // shadowing the one with a good one, purely by being listed first.
        for url in urls {
            if let icon = iconFromBundle(at: url) { return icon }
        }

        // Only now, and still worth trying: on a machine where the bundle
        // cannot be read, this is the icon the user sees in the Dock.
        for url in urls {
            let workspaceIcon = NSWorkspace.shared.icon(forFile: url.path)
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
