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
    var destinationAccounts: [DestinationAccount] = []

    /// Which groups are folded. Every section folds, not only the finished
    /// one — a panel where one header behaves differently from its neighbours
    /// teaches people that headers are decoration.
    ///
    /// Finished starts folded: it is the majority of what a probe returns and
    /// the least useful thing on screen, and six finished sessions used to
    /// carry the same weight as the one that was live.
    @State private var collapsed: Set<AgentPanelSection> = [.finished]

    private var layout: AgentPanelLayout {
        AgentPanelLayout.make(
            from: sessions,
            showingFinished: !collapsed.contains(.finished)
        )
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
                    destinationAccounts: destinationAccounts,
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
    var destinationAccounts: [DestinationAccount] = []
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
            destinationSection
            section(.finished, rows: layout.finished)
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

    /// Where the parked work could go.
    ///
    /// Shown only when something is waiting, which is not a way of keeping the
    /// panel tidy but the rule the transfer design already settled on: only a
    /// quiescent session can move safely, so a herd of running sessions has
    /// nothing to ask this about. It also makes the subject unambiguous — the
    /// list answers for the session named in the header, not for the panel.
    @ViewBuilder
    private var destinationSection: some View {
        if let subject = layout.waiting.first, !destinationAccounts.isEmpty {
            let repository = subject.session.session.repo?.slug
            let candidates = DestinationRoster.candidates(
                among: destinationAccounts,
                forRepository: repository,
                excluding: subject.session.machine
            )
            if !candidates.isEmpty {
                AgentSectionHeader(
                    section: .destinations,
                    label: "Could take \(repository ?? subject.session.session.projectName)",
                    hiddenCount: candidates.count,
                    isExpanded: Binding(
                        get: { !collapsed.contains(.destinations) },
                        set: { expanded in
                            if expanded {
                                collapsed.remove(.destinations)
                            } else {
                                collapsed.insert(.destinations)
                            }
                        }
                    )
                )
                if !collapsed.contains(.destinations) {
                    if DestinationRoster.isEntirelyUnchosen(candidates) {
                        DestinationNoticeRow(
                            symbolName: DestinationEligibility.excluded.symbolName,
                            title: "No destination chosen",
                            detail: "Tick a machine in Settings to let a session be moved onto it."
                        )

                        Divider()
                            .padding(.leading, AIAgentRow.titleInset)
                    } else {
                        ForEach(candidates) { candidate in
                            DestinationRow(candidate: candidate)

                            Divider()
                                .padding(.leading, AIAgentRow.titleInset)
                        }
                    }
                }
            }
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
                    compactionThresholds: compactionThresholds,
                    cpuPercent: agentCPU[row.session.session.id],
                    compactedAt: agentCompactedAt[row.session.session.id]
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
                .padding(.leading, AIAgentRow.titleInset)
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
struct AIAgentRow: View {
    let row: AgentPanelRow
    var compactionThresholds = AgentCompactionThresholds()
    /// Share of a core since the last sample, when two readings exist.
    var cpuPercent: Double?
    /// When this session last compacted, if it has while the app was watching.
    var compactedAt: Date?

    /// How long a compaction stays worth announcing.
    ///
    /// It is news, not a state: a session that compacted an hour ago has moved
    /// on, and a row still saying so would be one more permanent label to stop
    /// reading. Long enough to be seen on a panel nobody watches continuously.
    static let compactionNoticeWindow: TimeInterval = 600

    /// One width for every measured thing in the panel, header included.
    static let measureColumnWidth: CGFloat = 48
    /// The two measures each keep their own slot inside that column, filled or
    /// not. Right-aligning the pair instead let the ring slide under the meter's
    /// place whenever a row had no meter, so the rings did not line up with
    /// each other — the sort of drift that reads as carelessness even when
    /// nobody can say what moved.
    static let ringSlotWidth: CGFloat = 13
    static let meterSlotWidth: CGFloat = 31
    /// The leading column: the dot plus the space to the title. Dividers and
    /// section headers inset to this, so one vertical line runs down the panel.
    static let titleInset: CGFloat = 15

    private var machineSession: MachineAgentSession { row.session }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            AgentStateDot(
                state: machineSession.session.state,
                contextFraction: compactionThresholds.fraction(
                    tokens: machineSession.session.contextTokens,
                    model: machineSession.session.model,
                    declaredWindow: machineSession.session.contextWindow
                )
            )

            VStack(alignment: .leading, spacing: 3) {
                // Line one is identity: what this session is, and how long
                // since it moved. Line two is work: what it is doing, and what
                // that is costing and consuming. Sorting the row's contents by
                // what they are about is what stopped the right-hand side
                // reading as debris — four rows had produced four different
                // arrangements of the same slots.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(machineSession.session.displayTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    Text(Self.compactAge(of: machineSession.session.updatedAt))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    HStack(spacing: 4) {
                        // A compaction outranks whatever the session is doing
                        // now. It has just lost the history it was working
                        // from, which is the one moment a person would choose
                        // to start a successor instead of letting the next
                        // compaction chew through it as well.
                        if let compactionNotice {
                            Text(compactionNotice)
                                .foregroundStyle(.orange)
                        } else if let statusLine = machineSession.session.statusLine {
                            Text(statusLine)
                                .foregroundStyle(.secondary)
                        }

                            // Work that exists only on this machine, marked only
                        // when it does. A session whose branch is pushed needs
                        // nothing said about it, and a mark on every row would
                        // be one more thing to stop reading.
                        if machineSession.session.repo?.carriesUnsharedWork == true {
                            Image(systemName: "arrow.triangle.branch")
                                .foregroundStyle(.tertiary)
                                .help(unsharedWorkDescription)
                        }

                    if let disambiguator = row.disambiguator {
                            Text(disambiguator)
                                .monospaced()
                                .foregroundStyle(.tertiary)
                        }
                    }
                    // Small text wants a little air between its letters; large
                    // text wants less. This is the small end.
                    .font(.caption)
                    .tracking(0.1)
                    .lineLimit(1)
                    .truncationMode(.tail)

                    Spacer(minLength: 4)

                    Group {
                        // Only above fifteen percent: every session uses some
                        // CPU, and a number that is always there is a number
                        // people stop reading.
                        if let cpuPercent, cpuPercent >= 15 {
                            InlineSegmentedThermometer(value: cpuPercent)
                                .help("\(Int(cpuPercent.rounded()))% of a core")
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        }
                    }
                    .frame(
                        width: Self.meterSlotWidth,
                        alignment: .trailing
                    )
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(machineSession.session.state.title))
    }

    /// Said in full on hover, because the glyph can only say "something".
    private var unsharedWorkDescription: String {
        guard let repo = machineSession.session.repo else { return "" }
        var parts = ["on \(repo.branch)"]
        if repo.uncommittedFileCount > 0 {
            parts.append(
                repo.uncommittedFileCount == 1
                    ? "1 uncommitted file"
                    : "\(repo.uncommittedFileCount) uncommitted files"
            )
        }
        if !repo.hasUpstream {
            parts.append("never pushed anywhere")
        } else if repo.unpushedCommitCount > 0 {
            parts.append(
                repo.unpushedCommitCount == 1
                    ? "1 unpushed commit"
                    : "\(repo.unpushedCommitCount) unpushed commits"
            )
        }
        return parts.joined(separator: ", ")
    }

    private var compactionNotice: String? {
        guard let compactedAt else { return nil }
        let elapsed = Date.now.timeIntervalSince(compactedAt)
        guard elapsed >= 0, elapsed <= Self.compactionNoticeWindow else {
            return nil
        }
        return "Compacted \(Self.compactAge(of: compactedAt)) ago"
    }

    /// Quiet until it matters. A context two-thirds full is not news; one that
    /// is about to compact is the moment to start a successor session, which is
    /// the whole reason this figure is on screen.
    private func contextTint(for fraction: Double) -> Color {
        switch fraction {
        // The system accent, which is blue on most Macs and whatever the user
        // chose on the rest. Deliberately not a colour from the thermometer's
        // green-to-red scale: this is a different quantity, and borrowing that
        // vocabulary is what made the two read as one measurement. It also has
        // to be a real colour rather than a grey — drawn in `.secondary` it was
        // the same tone as its own track and effectively invisible.
        case ..<0.75: Color.accentColor
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
        if let fraction = compactionThresholds.fraction(
            tokens: machineSession.session.contextTokens,
            model: machineSession.session.model
        ) {
            parts.append(
                "context \(Int((fraction * 100).rounded()))% full"
            )
        } else if let context = machineSession.session.contextLabel {
            // No measured limit for this model yet, so the count is all that
            // can honestly be said.
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

/// One account, and whether the parked work could go there.
///
/// The reason is spelled out rather than reduced to a mark, because the three
/// answers have three different fixes and only one of them is a preference —
/// "excluded here" is a click away in Settings, "no agent" and "no checkout"
/// are not, and a row that only said "no" would send someone to the wrong one.
private struct DestinationRow: View {
    let candidate: DestinationCandidate

    var body: some View {
        DestinationNoticeRow(
            symbolName: candidate.eligibility.symbolName,
            title: candidate.name,
            detail: candidate.eligibility.detail,
            // Green only for the one that can. Nothing else here is a fault —
            // a machine you switched off is not broken — so the rest stay in
            // the panel's own quiet grey rather than borrowing a warning
            // colour.
            tint: candidate.eligibility.isEligible ? .green : .secondary
        )
    }
}

/// The shape of a destination line: a glyph, a name, and the sentence under
/// it.
///
/// The glyph column is `titleInset` wide including its spacing, so these names
/// sit on the same vertical line as the session titles above them. Four points
/// of drift here is the sort of thing that reads as carelessness even when
/// nobody can say what moved.
private struct DestinationNoticeRow: View {
    let symbolName: String
    let title: String
    let detail: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: symbolName)
                .font(.caption2)
                .foregroundStyle(tint)
                .frame(width: AIAgentRow.titleInset - 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(title). \(detail)"))
    }
}

/// A section header you can fold, with the control kept out of sight until it
/// is wanted.
///
/// The chevron appears on hover and fades when the pointer leaves. A row of
/// permanent disclosure triangles is a row of things to look at on a panel
/// whose subject is elsewhere, and the affordance is only ever needed by a
/// pointer that is already there. It sits at the trailing edge: at the leading
/// edge it pushed the titles out of the one vertical line the panel is built
/// on, and a control is a better citizen at the end of a row than at the start
/// of one it does not belong to.
private struct AgentSectionHeader: View {
    let section: AgentPanelSection
    /// Only the running group names anything: which machine these are on. The
    /// other two are their glyph, because a word restating the glyph is the
    /// repetition this panel keeps being trimmed of.
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

                if let label {
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
            .padding(.leading, AIAgentRow.titleInset)
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

/// State as a single dot at the leading edge — and the context warning.
///
/// Small, and the only coloured thing on a row that is otherwise text. Running
/// is filled and green; waiting is an open ring, which reads as unfinished
/// without shouting; finished is a faint dot that gets out of the way. Shape
/// carries the difference as well as colour, so the three stay distinct where
/// colour does not.
///
/// A session close to compacting overrides all three and blinks yellow. It is
/// the one thing on this panel worth interrupting a glance for — a session
/// about to compact is a session about to lose the history it has been building
/// — and it is safe to override the state because the section header above the
/// row already says what the state is. Blinking follows the usage LED's
/// behaviour, including holding still for anyone who has asked for less motion:
/// the colour still changes, so nothing is carried by movement alone.
private struct AgentStateDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let state: AgentSessionState
    /// How full the session's context is, when its model has been measured.
    var contextFraction: Double?

    @State private var isDimmed = false

    /// Close enough to compaction to be worth acting on. Measured against the
    /// point sessions actually compact at, which is what the app learns — not
    /// against the model's advertised window.
    static let almostFullFraction = 0.9

    private var isAlmostFull: Bool {
        (contextFraction ?? 0) >= Self.almostFullFraction
    }

    private var isBlinking: Bool { isAlmostFull && !reduceMotion }

    var body: some View {
        Circle()
            .fill(tint)
            .frame(width: 7, height: 7)
            // Opacity only, never scale. Pulsing the size made the warning
            // dot a different size from every other dot for half of every
            // cycle, and a column of markers that are not the same size is the
            // first thing the eye picks up — it read as a mistake rather than
            // as a warning. The dim end sits at half rather than a third: a
            // dot that fades to nothing on a light background reads as a
            // rendering fault, and the point is to be noticed.
            .opacity(isBlinking && isDimmed ? 0.5 : 1)
            .animation(
                isBlinking
                    ? .easeInOut(duration: 0.56).repeatForever()
                    : .easeOut(duration: 0.16),
                value: isDimmed
            )
            // Optically on the title's baseline: a marker that floats above or
            // below the line it belongs to is the sort of thing you feel rather
            // than notice.
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
            .onAppear { isDimmed = isBlinking }
            .onChange(of: isBlinking) { _, blinking in isDimmed = blinking }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(state.title))
            .accessibilityValue(
                isAlmostFull
                    ? Text("context almost full")
                    : Text("")
            )
    }

    /// One filled circle at one size, and colour carries the rest.
    ///
    /// Waiting used to be an open ring. It was meant to read as unfinished, and
    /// what it actually read as was a dot with a hole in it — a different kind
    /// of object sitting in a column of dots, which invites the question "what
    /// does that one mean?" every time. The section header above already says
    /// the state in words, so the colour has only to distinguish, not explain.
    private var tint: Color {
        if isAlmostFull { return .yellow }
        switch state {
        case .active: return .green
        case .waiting: return .orange
        case .completed: return Color.secondary.opacity(0.35)
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
