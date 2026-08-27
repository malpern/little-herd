import AppKit
import SwiftUI

/// The focused-machine page: one machine, one metric, drawn large.
///
/// This is where clicking a thermometer in the overview lands. Each metric gets
/// its own pane because each answers a different question — which processes,
/// which applications, which volumes, which sessions — and the panes share only
/// the shell `MetricDetailPane` gives them and the one unavailability sentence
/// below, so an unreachable machine reads the same way whichever metric you are
/// looking through. Kept out of `DashboardView` because none of it is the
/// dashboard; it is the page the dashboard hands you off to.

struct MachineMetricsView: View {
    let machine: MachineMonitorModel

    var body: some View {
        // Five rows plus dividers overflow the window on shorter machines, and
        // the last one was being cut in half by the window edge.
        ScrollView {
            metricRows
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var metricRows: some View {
        VStack(spacing: 0) {
            ForEach(machine.metrics) { metric in
                MetricRow(
                    metric: metric,
                    isSupported: metric.kind != .gpu || machine.supportsGPU,
                    memoryPressure: metric.kind == .memory
                        ? machine.memoryPressure
                        : nil,
                    memoryExplanation: metric.kind == .memory
                        ? machine.memoryPressureExplanation
                        : nil
                )

                if metric.kind != .disk {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }
}

/// The bar above a machine's details: somewhere to get back, and the allowance
/// readout that the overview header also carries so it does not blink out when
/// you drop into a machine.
struct MachineDetailBar: View {
    let machine: MachineMonitorModel
    let aiUsageLimits: AIUsageLimitsModel
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.backward")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(machine.name)
                        // Same type as the metric title in the overview header,
                        // so the two pages read as one place.
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to the overview")
            .accessibilityLabel("Back to the overview")

            Spacer(minLength: 8)

            AIUsageLimitsSummary(model: aiUsageLimits)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// One machine, one metric — the destination for clicking a thermometer.
///
/// The bar travels out of the overview and grows, so the thing you touched is
/// the thing you are looking at, and the right-hand side carries exactly the
/// detail the hover panel used to show.
struct MachineMetricDetail: View {
    let machine: MachineMonitorModel
    let metric: OverviewMetric
    var herd: [DestinationAccount] = []
    var namespace: Namespace.ID?
    let onBack: () -> Void
    var onSignIn: (() -> Void)?
    var onAllow: (MachineID, Bool) -> Void = { _, _ in }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                VStack(spacing: 6) {
                    OverviewMetricValue(
                        metric: metric,
                        value: presentation.value,
                        memoryPressure: presentation.memoryPressure,
                        memoryExplanation: machine.memoryPressureExplanation
                    )

                    SegmentedThermometer(
                        value: presentation.thermometerValue,
                        blockWidth: 34,
                        blockHeight: 9,
                        spacing: 3
                    )
                    .matchedThermometer(namespace, machine: machine.machine)

                    MachineStatusLabel(
                        machine: machine,
                        avatarSize: 34,
                        namespace: namespace
                    )
                    .padding(.top, 2)
                }
                .frame(width: 96)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Back to the overview")
            .accessibilityLabel("Back to the overview")

            Divider()

            MachineMetricDetailContent(
                machine: machine,
                metric: metric,
                herd: herd,
                onSignIn: onSignIn,
                onAllow: onAllow
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var presentation: OverviewMetricPresentation {
        machine.metricPresentation(
            for: metric,
            isReporting: machine.state == .live
        )
    }
}

/// What fills the right-hand side of a focused machine.
///
/// The CPU case is a real list rather than the three rows the hover strip
/// could fit: the sampler already collects more, and this pane has the room.
struct MachineMetricDetailContent: View {
    let machine: MachineMonitorModel
    let metric: OverviewMetric
    var herd: [DestinationAccount] = []
    var onSignIn: (() -> Void)?
    var onAllow: (MachineID, Bool) -> Void = { _, _ in }

    var body: some View {
        switch metric {
        case .cpu: MachineProcessPane(machine: machine, onSignIn: onSignIn)
        case .memory: MachineMemoryPane(machine: machine, onSignIn: onSignIn)
        case .disk: MachineStoragePane(machine: machine, onSignIn: onSignIn)
        case .ai:
            MachineAgentPane(
                machine: machine,
                herd: herd,
                onSignIn: onSignIn,
                onAllow: onAllow
            )
        }
    }
}

struct MachineProcessPane: View {
    let machine: MachineMonitorModel
    var onSignIn: (() -> Void)?

    var body: some View {
        MetricDetailPane(
            title: "WHAT\u{2019}S RUNNING",
            series: machine.series(for: .cpu),
            summary: machine.state == .live
                ? machine.cpu.value.map {
                    Text($0 / 100, format: .percent.precision(.fractionLength(0)))
                }
                : nil,
            emptyMessage: activities.isEmpty ? unavailableMessage(for: machine) : nil,
            emptyAction: onSignIn
        ) {
            ForEach(Array(activities.enumerated()), id: \.offset) { _, activity in
                MetricDetailRow(
                    symbolName: activity.symbolName,
                    tint: activity.agentTask == nil
                        ? MetricKind.cpu.color
                        : .orange,
                    title: Text(activity.shortLabel),
                    subtitle: coreCount.map { count in
                        Text(
                            "\(activity.cpuCores, format: .number.precision(.fractionLength(1))) of \(count) cores"
                        )
                    },
                    value: share(of: activity).map {
                        Text($0 / 100, format: .percent.precision(.fractionLength(0)))
                    }
                        // Without a core count there is no machine to be a share
                        // of, so the honest figure is the one we measured.
                        ?? Text(
                            "\(activity.cpuCores, format: .number.precision(.fractionLength(1)))c"
                        )
                )
                .help(Text(activity.tooltip))
            }
        }
    }

    private var coreCount: Int? { machine.coreCount }

    private func share(of activity: MachineActivity) -> Double? {
        ProcessShare.percent(
            ofOneCore: activity.cpuPercent,
            coreCount: coreCount
        )
    }

    /// Anything under a twentieth of a core rounds to "0.0c" and reads as
    /// padding rather than information, so the list stops where it stops being
    /// worth reading.
    private var activities: [MachineActivity] {
        machine.state == .live
            ? machine.activities.filter { $0.cpuCores >= 0.05 }
            : []
    }
}

struct MachineMemoryPane: View {
    let machine: MachineMonitorModel
    var onSignIn: (() -> Void)?

    var body: some View {
        MetricDetailPane(
            title: "WHAT\u{2019}S USING MEMORY",
            series: machine.series(for: .memory),
            summary: machine.state == .live
                ? machine.memoryPressure.map { Text($0.title) }
                : nil,
            emptyMessage: consumers.isEmpty ? unavailableMessage(for: machine) : nil,
            emptyAction: onSignIn
        ) {
            ForEach(consumers) { consumer in
                MetricDetailRow(
                    symbolName: "square.stack.3d.up",
                    tint: MetricKind.memory.color,
                    bundlePath: consumer.bundlePath,
                    title: Text(consumer.name),
                    // The size stays: "Chrome is using 4 GB" says something a
                    // percentage cannot, and says it across machines with
                    // different amounts of memory.
                    subtitle: Text(
                        Int64(consumer.residentBytes),
                        format: .byteCount(style: .memory)
                    ),
                    value: memoryShare(of: consumer).map {
                        Text($0 / 100, format: .percent.precision(.fractionLength(0)))
                    }
                        ?? Text(
                            Int64(consumer.residentBytes),
                            format: .byteCount(style: .memory)
                        )
                ) {
                    if let evidence = consumer.growthEvidence {
                        Circle()
                            .fill(.red)
                            .frame(width: 5, height: 5)
                            .help(Text(
                                "Grew \(Int64(evidence.growthBytes), format: .byteCount(style: .memory)) over \(Int(evidence.duration / 60)) min across \(evidence.sampleCount) samples — possibly a leak."
                            ))
                    }
                }
                .contextMenu {
                    if machine.isLocal, let bundlePath = consumer.bundlePath {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: bundlePath)]
                            )
                        }
                    }
                }
            }
        }
    }

    private func memoryShare(of consumer: MemoryConsumer) -> Double? {
        ProcessShare.percent(
            residentBytes: consumer.residentBytes,
            totalBytes: machine.memory.capacity
        )
    }

    private var consumers: [MemoryConsumer] {
        machine.state == .live ? machine.memoryConsumers : []
    }
}

struct MachineStoragePane: View {
    let machine: MachineMonitorModel
    var onSignIn: (() -> Void)?
    /// One browser per volume, made when a volume is first opened. Kept here
    /// rather than in the machine model because it is view state: what someone
    /// has open, not anything about the machine.
    @State private var browsers: [String: FolderBrowserModel] = [:]
    @State private var store = FolderSizeStore()

    var body: some View {
        MetricDetailPane(
            // No chart: disk usage moves in single percentage points over
            // days, so the line is flat whatever is happening. A graph that
            // always looks the same is the storage equivalent of a badge that
            // is always lit.
            title: "VOLUMES",
            summary: fullest.map {
                Text($0 / 100, format: .percent.precision(.fractionLength(0)))
            },
            emptyMessage: volumes.isEmpty ? unavailableMessage(for: machine) : nil,
            emptyAction: onSignIn
        ) {
            ForEach(volumes) { volume in
                let browser = browser(for: volume)
                let scanPath = scanPath(for: volume)
                MetricDetailRow(
                    // A volume the machine considers degraded says so here, so
                    // the row is not merely a capacity bar on failing hardware.
                    symbolName: volume.health.map(\.symbolName) ?? "internaldrive",
                    tint: volume.health.map(\.tint) ?? MetricKind.disk.color,
                    // A triangle, so the row looks like something that opens.
                    // Without one there is nothing to say the list is there.
                    title: Text(
                        Image(
                            systemName: browser.isExpanded(scanPath)
                                ? "chevron.down"
                                : "chevron.right"
                        )
                    )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        + Text("  ") + Text(volume.name),
                    subtitle: Text(capacityDescription(for: volume)),
                    value: Text(
                        volume.usedPercent / 100,
                        format: .percent.precision(.fractionLength(0))
                    )
                ) {
                    // A bar makes "how full" scannable in a way a number is not.
                    Capsule()
                        .fill(.quaternary)
                        .frame(width: 42, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(volume.usedPercent >= 90
                                    ? Color.orange
                                    : MetricKind.disk.color)
                                .frame(
                                    width: 42 * volume.usedPercent / 100,
                                    height: 4
                                )
                        }
                }
                // Only for this Mac: a remote machine's mount path either does
                // not exist here or, worse, names something different.
                .contextMenu {
                    if machine.isLocal, let path = volume.mountPath
                        .components(separatedBy: ", ").first
                    {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: path)]
                            )
                        }
                    }
                }
                // Opens whatever the machine can offer: a list, or the reason
                // there is none. A row that does nothing when tapped teaches
                // people not to tap it.
                .onTapGesture { browser.toggle(scanPath, isRoot: true) }

                if browser.isExpanded(scanPath) {
                    FolderBrowserView(model: browser, path: scanPath)
                        .padding(.leading, 10)
                }
            }

            // Physical drives, below the volumes they add up to. Only a NAS
            // reports these; a Mac can say a volume is full but not that the
            // hardware under it is dying.
            if !drives.isEmpty {
                ForEach(drives) { drive in
                    MetricDetailRow(
                        symbolName: drive.health.symbolName,
                        tint: drive.health.tint,
                        title: Text(drive.name),
                        subtitle: Text(driveDescription(for: drive)),
                        value: drive.health == .normal
                            ? nil
                            : Text(drive.health.label)
                    )
                    // Indented, because a drive belongs to the volume above it
                    // rather than sitting beside it. Without this the list reads
                    // as one flat run of unrelated things.
                    .padding(.leading, 14)
                }
            }
        }
    }

    private var volumes: [StorageVolume] {
        machine.state == .live || machine.isStorage ? machine.storageVolumes : []
    }

    /// In the order the machine reports them, which is bay order.
    ///
    /// Sorting by severity was worse: it puts the drives in an order that
    /// changes as hardware ages, and the number in "Drive 2" refers to a
    /// physical slot — a list where Drive 2 sits above Drive 1 reads as wrong
    /// before it reads as urgent. Health is already carried by the icon and the
    /// colour, which is what the eye finds first anyway.
    private var drives: [SynologyDrive] {
        guard machine.state == .live || machine.isStorage else { return [] }
        return machine.drives
    }

    /// Model and temperature, because the drive that needs replacing has to be
    /// identifiable at the front of the unit.
    private func driveDescription(for drive: SynologyDrive) -> String {
        var parts: [String] = []
        if !drive.model.isEmpty { parts.append(drive.model) }
        if let temperature = drive.temperatureCelsius {
            parts.append("\(Int(temperature))°C")
        }
        // The most concrete evidence a drive is going, and the number that
        // justifies replacing it. Leads the subtitle when there is one.
        if drive.uncorrectableSectors > 0 {
            parts.insert(
                "\(drive.uncorrectableSectors) bad sectors",
                at: 0
            )
        }
        return parts.isEmpty ? "No details reported" : parts.joined(separator: " · ")
    }

    /// APFS volumes sharing a container are reported as one row whose mount
    /// path lists all of them, so the scan takes the first — the row's own
    /// volume, and the one its name refers to.
    private func scanPath(for volume: StorageVolume) -> String {
        volume.mountPath.components(separatedBy: ", ").first ?? volume.mountPath
    }

    private func browser(for volume: StorageVolume) -> FolderBrowserModel {
        let path = scanPath(for: volume)
        if let existing = browsers[path] { return existing }
        let created = FolderBrowserModel(
            machine: machine.machine,
            availability: machine.folderScanning,
            store: store
        )
        // Assigning during a body pass would be a mutation mid-render, so the
        // dictionary is filled on the next turn of the loop.
        Task { @MainActor in browsers[path] = created }
        return created
    }

    private var fullest: Double? { volumes.map(\.usedPercent).max() }

    /// Says outright when a row covers several volumes. Without it "69%" reads
    /// as the named volume's usage when it is the whole container's — the
    /// volume itself may be using a fraction of that.
    private func capacityDescription(for volume: StorageVolume) -> LocalizedStringResource {
        let free = Int64(volume.availableBytes).formatted(.byteCount(style: .file))
        let total = Int64(volume.totalBytes).formatted(.byteCount(style: .file))
        // Condition leads when there is one: a degraded volume matters more than
        // how much room is left on it.
        if let health = volume.health, health == .warning || health == .critical {
            return "\(health.label) · \(free) free of \(total)"
        }
        guard volume.volumeCount > 1 else {
            return "\(free) free of \(total)"
        }
        return "\(free) free of \(total) · \(volume.volumeCount) volumes"
    }
}

struct MachineAgentPane: View {
    let machine: MachineMonitorModel
    /// The rest of the herd, so a version can be set against the newest copy
    /// of itself. Skew is only visible in comparison.
    var herd: [DestinationAccount] = []
    var onSignIn: (() -> Void)?
    var onAllow: (MachineID, Bool) -> Void = { _, _ in }

    @AppStorage(LittleHerdPreferences.requiresDestinationApprovalKey)
    private var requiresDestinationApproval = false

    var body: some View {
        MetricDetailPane(
            title: "AGENTS",
            summary: sessions.isEmpty
                ? nil
                : Text("\(sessions.count { $0.state == .active }) active"),
            emptyMessage: sessions.isEmpty ? agentEmptyMessage : nil,
            emptyAction: onSignIn
        ) {
            MachineAgentRows(
                machine: machine,
                sessions: sessions,
                versions: versions
            )

            // Only when the setting is on. A permission control on a machine
            // that needs no permission is a question nobody asked, and this
            // pane already carries the destination facts it would sit beside.
            if requiresDestinationApproval {
                MachineDestinationAllowance(machine: machine, onAllow: onAllow)
            }
        }
    }

    private var versions: [AgentVersionReport] {
        AgentVersionReader.reports(for: machine.machine, among: herd)
    }

    private var sessions: [AgentSession] { machine.agentSessions }

    private var agentEmptyMessage: LocalizedStringResource {
        machine.state == .live
            ? "No recent agent sessions"
            : unavailableMessage(for: machine)
    }
}

/// The one control that makes "ask before a machine can take work" usable.
///
/// It exists because the setting's gate is `mayHostSessions`, which defaults to
/// off — so without somewhere to say yes, turning the setting on would refuse
/// the whole herd and leave no way back. The setting and its setter ship
/// together, and neither is drawn when the other is absent.
struct MachineDestinationAllowance: View {
    let machine: MachineMonitorModel
    /// Writes the answer through to the configuration store. Required, not
    /// optional: the model's own `setMayHostSessions` changes memory and
    /// nothing else — persistence used to flow the other way, from the
    /// Settings checkbox that edited the stored configuration — so a control
    /// wired only to the model is forgotten on the next launch, which is the
    /// one thing a permission must never do.
    let onAllow: (MachineID, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.vertical, 4)

            Toggle(
                "Allow work to be moved here",
                isOn: Binding(
                    get: { machine.mayHostSessions },
                    set: { onAllow(machine.machine, $0) }
                )
            )
            .font(.caption.weight(.medium))
            .toggleStyle(.checkbox)

            Text(allowanceDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }

    /// What allowing it would actually get you, which is not the same question
    /// as whether it is allowed — a machine can be permitted and still unable.
    private var allowanceDetail: String {
        machine.mayHostSessions
            ? machine.destinationEligibility().detail
            : "Not offered as a destination."
    }
}

/// The pane's session rows, separated from the `ScrollView` that holds them.
///
/// Not a tidiness refactor, and the second time this project has needed it:
/// `MetricDetailPane` scrolls, `ImageRenderer` does not lay out a `ScrollView`,
/// and the first render of this pane produced a header over an empty box and
/// reported success. Exactly what `AIAgentPanelContent` exists to avoid.
struct MachineAgentRows: View {
    let machine: MachineMonitorModel
    let sessions: [AgentSession]
    var versions: [AgentVersionReport] = []

    /// Which session is being renamed, and what has been typed so far.
    @State private var renaming: String?
    @State private var draft = ""
    @FocusState private var isEditing: Bool

    /// The size the summary panel leads its rows with, so a session looks the
    /// same wherever you meet it.
    private static let iconSize: CGFloat = 26

    var body: some View {
        if !versions.isEmpty {
            InstalledAgentsHeader()

            ForEach(versions) { report in
                // No second line. It carried the path most of the time and a
                // skew note the rest, and neither is what you came to this
                // list for — which agent, and which version.
                MetricDetailRow(
                    symbolName: "shippingbox",
                    tint: report.installation.provider == .codex ? .green : .orange,
                    title: Text(report.installation.providerName),
                    value: Text(report.installation.version)
                )
            }

            if !sessions.isEmpty {
                SessionsHeader()
            }
        }

        ForEach(sessions) { session in
            sessionRow(session)
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: AgentSession) -> some View {
        MetricDetailRow(
            symbolName: "sparkles",
            tint: session.provider == .codex ? .green : .orange,
            leadingIconSize: Self.iconSize,
            provider: session.provider,
            title: Text(session.displayTitle),
            subtitle: session.statusLine.map(Text.init),
            value: Text(AgentRowMetrics.compactAge(of: session.updatedAt))
        )
        .overlay(alignment: .leading) {
            if renaming == session.id {
                renameField(for: session)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { beginRenaming(session) }
        // The pointer says which rows will answer a click. Only Codex will:
        // Claude Code has no supported way to rename a session from outside
        // it, so offering the gesture there would be a control that lies.
        .pointerStyle(canRename(session) ? .link : nil)
        .help(
            canRename(session)
                ? "Click to rename this session in Codex."
                : "Renaming is only supported for Codex sessions."
        )
    }

    private func renameField(for session: AgentSession) -> some View {
        TextField("", text: $draft)
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .focused($isEditing)
            .padding(.leading, Self.iconSize + 7)
            .onSubmit { commitRename(session) }
            .onExitCommand { cancelRename() }
            .onAppear { isEditing = true }
    }

    private func canRename(_ session: AgentSession) -> Bool {
        session.provider == .codex && codexInstall != nil
    }

    private var codexInstall: AgentInstallation? {
        machine.destinationReport?.installations
            .first { $0.provider == .codex }
    }

    private func beginRenaming(_ session: AgentSession) {
        guard canRename(session) else { return }
        draft = session.displayTitle
        renaming = session.id
    }

    private func cancelRename() {
        renaming = nil
        draft = ""
    }

    private func commitRename(_ session: AgentSession) {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelRename()
        guard !name.isEmpty, name != session.displayTitle,
              let install = codexInstall
        else {
            return
        }
        Task {
            // The result is not surfaced yet. The next probe re-reads the
            // name from Codex, so a rename that failed simply does not appear
            // to have happened — which is honest, if terse, and better than
            // showing a name the provider never accepted.
            _ = await AgentRenamer.rename(
                threadID: session.id,
                to: name,
                using: install,
                isLocal: machine.isLocal,
                host: machine.hostname,
                identityFile: machine.identityFile
            )
        }
    }
}

/// A word and a rule, so the two kinds of thing in this pane have a seam.
///
/// Version skew is the standing condition here rather than an incident — Codex
/// has been three different builds across three machines for as long as anyone
/// has looked — so a copy that is behind is named in the same grey as
/// everything else, where you are already looking at that machine. A warning
/// colour on a permanent condition is read once and then stops being read.
struct InstalledAgentsHeader: View {
    var body: some View {
        SeamHeader(title: "INSTALLED")
    }
}

struct SessionsHeader: View {
    var body: some View {
        SeamHeader(title: "SESSIONS")
            .padding(.top, 2)
    }
}

struct SeamHeader: View {
    let title: LocalizedStringResource

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .tracking(0.35)
                .foregroundStyle(.tertiary)
                .accessibilityAddTraits(.isHeader)

            VStack { Divider() }
        }
    }
}

/// One message for every pane, so an unreachable machine reads the same way
/// whichever metric you are looking through.
func unavailableMessage(
    for machine: MachineMonitorModel
) -> LocalizedStringResource {
    // Never having connected is a setup step, not a fault, and a NAS can say
    // exactly which step.
    if machine.hasNeverConnected {
        return machine.isStorage
            ? "Not connected \u{2014} sign in to DSM"
            : "Not connected yet"
    }
    switch machine.state {
    case .connecting: return "Checking\u{2026}"
    case .live: return "Nothing to report"
    case .offline: return "Unavailable"
    case .stopped: return "Monitoring paused"
    }
}

/// The identity column. The avatar here is the same view that was in the
/// overview — it travels rather than being redrawn, which is what makes the
/// machine you clicked feel like the machine you are now looking at.
struct MachineIdentityRail: View {
    let machine: MachineMonitorModel
    var namespace: Namespace.ID?
    let onBack: () -> Void
    /// Present when this machine can be signed in to. The status line is the
    /// thing that says it is not connected, so it is also the thing that fixes
    /// it — the same rule the storage rows already follow.
    var onSignIn: (() -> Void)?

    @State private var isHoveringIcon = false

    var body: some View {
        VStack(spacing: 6) {
            // The icon is the thing that carried you in here, so it is also the
            // way back out — same destination as the chevron.
            Button(action: onBack) {
                MachineAvatarView(avatar: machine.avatar, size: 84)
                    .matchedAvatar(namespace, machine: machine.machine)
                    .scaleEffect(isHoveringIcon ? 0.96 : 1)
                    .animation(.smooth(duration: 0.16), value: isHoveringIcon)
                    // The same badge as the overview, so the mark that brought
                    // you here is still on the machine when you arrive.
                    .overlay(alignment: .topTrailing) {
                        if let concern = machine.storageConcern {
                            Image(systemName: concern.health.symbolName)
                                .font(.system(size: 22))
                                .foregroundStyle(.white, concern.health.tint)
                                .background(Circle().fill(.background).frame(width: 20, height: 20))
                                .offset(x: 2, y: 2)
                                .accessibilityHidden(true)
                        }
                    }
            }
            .buttonStyle(.plain)
            .onHover { isHoveringIcon = $0 }
            .help("Back to the overview")
            .accessibilityLabel("Back to the overview")

            VStack(spacing: 3) {
                Text(machine.shortName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                if let onSignIn {
                    Button(action: onSignIn) {
                        MachineConnectionLabel(machine: machine)
                            .lineLimit(1)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Sign in to DSM")
                    .accessibilityHint(Text("Sign in to DSM"))
                } else {
                    MachineConnectionLabel(machine: machine)
                        .lineLimit(1)
                }

                // Says what the badge means, where you land after clicking it.
                // A mark that only signals "something is wrong" makes you hunt
                // for the something.
                if let concern = machine.storageConcern {
                    Text(concern.summary(trend: machine.driveSectorTrend))
                        .font(.caption2)
                        .foregroundStyle(concern.health.tint)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .help("Reported by the machine itself. See Disk for every drive.")
                }
            }
        }
        .frame(width: 112)
        .frame(maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 4)
    }
}

/// The one place a machine's status is written out in words rather than spoken.
///
/// The dots elsewhere carry `MachineStatus.label` as an accessibility label, so
/// until now the words on screen here were the only ones nothing else agreed
/// with: this said "Not connected" and "Unavailable" where every other surface
/// said "Not set up yet" and "Unreachable", and it drew a machine that had
/// dropped out in the same grey as one that was never set up. It reads the
/// shared vocabulary now, red fault dot included — a machine that stopped
/// answering says so on its own page as loudly as it does in the overview.
struct MachineConnectionLabel: View {
    let machine: MachineMonitorModel

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(machine.status.tint)
                .frame(width: 5, height: 5)

            Text(machine.status.label)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .help(helpText)
    }

    /// The status line has room for two words; the reason someone can act on
    /// goes here, where it costs nothing until they look for it.
    private var helpText: Text {
        guard machine.state == .offline, let unavailability = machine.unavailability else {
            return Text("")
        }
        return Text(unavailability.detail(host: machine.hostname))
    }
}
