import AppKit
import SwiftUI

struct DashboardView: View {
    let model: MonitorModel
    /// Needed so a NAS can be signed in from the page that says it is not
    /// connected, rather than only from Settings.
    var machineStore: MachineConfigurationStore?
    var onConfigurationsChanged: ([MachineConfiguration]) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(
        LittleHerdPreferences.networkVolumeAccessOnboardingCompletedKey
    )
    private var hasCompletedNetworkVolumeOnboarding = false
    @Namespace private var machineTransition
    @State private var hoveredAgentID: MachineAgentSession.ID?
    @State private var isShowingLaunchSplash =
        LittleHerdLaunchSplashSession.claimPresentation()
    @State private var isShowingNetworkVolumeOnboarding = false
    @State private var isRequestingNetworkVolumeAccess = false
    @State private var signingInMachine: MachineConfiguration?

    var body: some View {
        let agentSessions = MachineAgentSessionBuilder.visibleSessions(
            from: model.machines.flatMap { machine in
                machine.agentSessions.map {
                    MachineAgentSession(
                        machine: machine.machine,
                        session: $0,
                        machineName: machine.shortName,
                        machineSymbolName: machine.symbolName
                    )
                }
            }
        )

        ZStack {
            VStack(spacing: 0) {
                if let transfer = visibleTransfer {
                    TaskTransferView(event: transfer, machines: model.machines)
                        .id(transfer.id)
                } else {
                    if model.selection.isMetricFocus {
                        CPUOverviewHeaderArea(
                            machines: model.overviewMachines,
                            agentSessions: agentSessions,
                            hoveredAgentID: hoveredAgentID,
                            aiUsageLimits: model.aiUsageLimits,
                            metric: model.overviewMetric,
                            onSelect: model.selectOverviewMetric
                        )
                    } else if let selectedMachine = model.selectedMachine {
                        MachineDetailBar(
                            machine: selectedMachine,
                            aiUsageLimits: model.aiUsageLimits,
                            onBack: { model.selection = .overview }
                        )
                    } else {
                        CPUOverviewHeaderArea(
                            machines: model.overviewMachines,
                            agentSessions: agentSessions,
                            hoveredAgentID: hoveredAgentID,
                            aiUsageLimits: model.aiUsageLimits,
                            metric: model.overviewMetric,
                            onSelect: model.selectOverviewMetric
                        )
                    }

                    Divider()
                        .padding(.horizontal, 14)

                    if let selectedMachine = model.selectedMachine,
                       model.selection.isMetricFocus {
                        MachineMetricDetail(
                            machine: selectedMachine,
                            metric: model.overviewMetric,
                            namespace: machineTransition,
                            onBack: { model.selection = .overview },
                            onSignIn: signInAction(for: selectedMachine)
                        )
                    } else if let selectedMachine = model.selectedMachine {
                        HStack(spacing: 0) {
                            MachineIdentityRail(
                                machine: selectedMachine,
                                namespace: machineTransition,
                                onBack: { model.selection = .overview },
                                onSignIn: signInAction(for: selectedMachine)
                            )

                            Divider()

                            // Unchanged: the same rows, in the same order,
                            // whichever overview you arrived from.
                            MachineMetricsView(machine: selectedMachine)
                        }
                    } else {
                        OverviewMetricContent(
                            machines: model.overviewMachines,
                            agentSessions: agentSessions,
                            hoveredAgentID: $hoveredAgentID,
                            metric: model.overviewMetric,
                            compactionThresholds: model.compactionThresholds,
                            agentCPU: model.agentCPU,
                            agentCompactedAt: model.agentCompactedAt,
                            namespace: machineTransition,
                            onSelectMetric: { model.selection = .machineMetric($0) },
                            onSelectMachine: { model.selection = .machine($0) }
                        )
                        .id(model.overviewMetric)
                        .transition(.opacity)
                    }
                }
            }
            .opacity(isLaunchOverlayVisible ? 0 : 1)
            .allowsHitTesting(!isLaunchOverlayVisible)
            .accessibilityHidden(isLaunchOverlayVisible)

            if isShowingLaunchSplash {
                LittleHerdSplashView()
                    .ignoresSafeArea(.container, edges: .top)
                    .transition(.opacity)
            } else if isShowingNetworkVolumeOnboarding {
                NetworkVolumeOnboardingView(
                    isRequesting: isRequestingNetworkVolumeAccess,
                    onContinue: requestNetworkVolumeAccess,
                    onNotNow: skipNetworkVolumeAccess
                )
                .transition(.opacity)
            }
        }
        .frame(
            width: windowContentSize.width,
            height: windowContentSize.height
        )
        .sheet(item: $signingInMachine) { machine in
            SynologyCredentialsView(machine: machine) { updated in
                machineStore?.update(updated)
                onConfigurationsChanged(machineStore?.machines ?? [])
            }
        }
        .background(LittleHerdTheme.background)
        .background {
            DashboardWindowBridge(
                presentation: isShowingLaunchSplash ? .splash : .dashboard,
                reduceMotion: reduceMotion,
                dashboardContentSize: dashboardContentSize
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .animation(.easeInOut(duration: 0.22), value: model.overviewMetric)
        .animation(
            DashboardTransition.animation(reduceMotion: reduceMotion),
            value: model.selection
        )
        .task {
            await advanceLaunchFlowWhenReady()
        }
        .onAppear {
            model.setNetworkStorageMonitoringEnabled(
                hasCompletedNetworkVolumeOnboarding
                    && !shouldPresentNetworkVolumeOnboarding
            )
            model.activate(.dashboard)
            startUsageSourceIfWanted()
        }
        .onDisappear {
            model.deactivate(.dashboard)
        }
    }

    /// Starts the usage source if it is installed, not running, and allowed.
    ///
    /// Little Herd cannot measure a vendor limit itself, so a usage figure is
    /// only as alive as CodexBar is — and CodexBar not running looks exactly
    /// like having no limit. Starting it is cheap, reversible by quitting it,
    /// and off by one switch in Settings for anyone who would rather Little
    /// Herd did not launch another application on their Mac.
    private func startUsageSourceIfWanted() {
        guard UserDefaults.standard.object(
            forKey: LittleHerdPreferences.startsUsageSourceKey
        ) as? Bool ?? true else {
            return
        }
        CodexBarSource.launchIfNeeded()
    }

    private var visibleTransfer: TaskTransferEvent? {
        // The handoff animation draws machines as CPU thermometers, so it only
        // stands in for the CPU overview — not for memory, disk, or AI.
        guard model.selection == .overview, model.overviewMetric == .cpu else {
            return nil
        }
        return model.taskTransfers.currentEvent
    }

    private var isLaunchOverlayVisible: Bool {
        isShowingLaunchSplash || isShowingNetworkVolumeOnboarding
    }

    private var windowContentSize: CGSize {
        isShowingLaunchSplash
            ? LittleHerdSplashMetrics.contentSize
            : dashboardContentSize
    }

    /// NSSize and CGSize are the same type on macOS, so the window bridge and
    /// the SwiftUI frame read one table rather than two that can drift apart.
    private var dashboardContentSize: NSSize {
        if isShowingNetworkVolumeOnboarding {
            return NSSize(width: 420, height: 374)
        }
        if model.selection == .overview {
            // Disk stacks a volume name, bar, and capacity above the machine
            // name, so it needs more room than the other three.
            return NSSize(width: 300, height: 296)
        }
        return model.selection.isMetricFocus
            ? NSSize(width: 400, height: 330)
            : NSSize(width: 420, height: 340)
    }

    private var shouldPresentNetworkVolumeOnboarding: Bool {
        ProcessInfo.processInfo.environment[
            "LITTLE_HERD_SHOW_NETWORK_ONBOARDING"
        ] == "1" || !hasCompletedNetworkVolumeOnboarding
    }

    private func advanceLaunchFlowWhenReady() async {
        if isShowingLaunchSplash {
            guard ProcessInfo.processInfo.environment[
                "LITTLE_HERD_HOLD_SPLASH"
            ] != "1" else { return }

            let configuredDelay = ProcessInfo.processInfo.environment[
                "LITTLE_HERD_SPLASH_DELAY"
            ].flatMap(Double.init)
            let minimumSplashDuration = min(
                max(configuredDelay ?? LittleHerdSplashMetrics.minimumDuration, 0),
                10
            )
            try? await Task.sleep(for: .seconds(minimumSplashDuration))
            guard !Task.isCancelled else { return }

            let readinessDeadline = ContinuousClock.now + .seconds(2)
            while !model.machines.contains(where: { $0.lastUpdated != nil }),
                  ContinuousClock.now < readinessDeadline
            {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
        }

        withAnimation(
            reduceMotion
                ? .linear(duration: 0.01)
                : .easeInOut(duration: 0.32)
        ) {
            isShowingLaunchSplash = false
            isShowingNetworkVolumeOnboarding =
                shouldPresentNetworkVolumeOnboarding
        }
    }

    /// Offered only for a NAS that is not currently reporting: a machine that
    /// is working does not need a sign-in button in front of it.
    private func signInAction(
        for machine: MachineMonitorModel
    ) -> (() -> Void)? {
        guard machine.isStorage, machine.state != .live,
              let configuration = machineStore?.machines.first(where: {
                  $0.id == machine.machine
              })
        else {
            return nil
        }
        return { signingInMachine = configuration }
    }

    private func requestNetworkVolumeAccess() {
        guard !isRequestingNetworkVolumeAccess else { return }
        isRequestingNetworkVolumeAccess = true

        Task {
            await model.requestNetworkStorageAccess()
            hasCompletedNetworkVolumeOnboarding = true
            model.setNetworkStorageMonitoringEnabled(true)

            withAnimation(
                reduceMotion
                    ? .linear(duration: 0.01)
                    : .easeInOut(duration: 0.24)
            ) {
                isRequestingNetworkVolumeAccess = false
                isShowingNetworkVolumeOnboarding = false
            }
        }
    }

    private func skipNetworkVolumeAccess() {
        model.setNetworkStorageMonitoringEnabled(false)
        withAnimation(
            reduceMotion
                ? .linear(duration: 0.01)
                : .easeInOut(duration: 0.24)
        ) {
            isShowingNetworkVolumeOnboarding = false
        }
    }
}

private struct CPUOverviewHeaderArea: View {
    let machines: [MachineMonitorModel]
    let agentSessions: [MachineAgentSession]
    let hoveredAgentID: MachineAgentSession.ID?
    let aiUsageLimits: AIUsageLimitsModel
    let metric: OverviewMetric
    let onSelect: (OverviewMetric) -> Void

    var body: some View {
        ZStack {
            if metric == .ai,
               let hoveredAgent = agentSessions.first(where: {
                   $0.id == hoveredAgentID
               })
            {
                HoveredAgentHeader(machineSession: hoveredAgent)
            } else {
                CPUOverviewHeader(
                    liveMachineCount: machines.count(where: {
                        $0.state == .live
                    }),
                    machineCount: machines.count,
                    activeAgentCount: agentSessions.count {
                        $0.session.state == .active
                    },
                    agentCount: agentSessions.count,
                    aiUsageLimits: aiUsageLimits,
                    metric: metric,
                    onSelect: onSelect
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 68)
    }
}

private struct CPUOverviewHeader: View {
    let liveMachineCount: Int
    let machineCount: Int
    let activeAgentCount: Int
    let agentCount: Int
    let aiUsageLimits: AIUsageLimitsModel
    let metric: OverviewMetric
    let onSelect: (OverviewMetric) -> Void

    var body: some View {
        HStack(spacing: 8) {
            OverviewMetricMenu(
                selection: metric,
                liveMachineCount: liveMachineCount,
                machineCount: machineCount,
                activeAgentCount: activeAgentCount,
                agentCount: agentCount,
                onSelect: onSelect
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            AIUsageLimitsSummary(model: aiUsageLimits)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

private struct OverviewMetricMenu: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let selection: OverviewMetric
    let liveMachineCount: Int
    let machineCount: Int
    let activeAgentCount: Int
    let agentCount: Int
    let onSelect: (OverviewMetric) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: selection.symbolName)
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(LittleHerdTheme.forest)
                        .id(selection)
                        .transition(.opacity)
                }
                .frame(width: 24, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(selection.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    OverviewMetricStatusLine(
                        metric: selection,
                        liveMachineCount: liveMachineCount,
                        machineCount: machineCount,
                        activeAgentCount: activeAgentCount,
                        agentCount: agentCount
                    )
                }
                .id(selection)
                .transition(.opacity)
            }
            .allowsHitTesting(false)

            OverviewMetricPopUpButton(selection: selection, onSelect: onSelect)
                .frame(width: 142, height: 44)
        }
        .frame(width: 142, alignment: .leading)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.18),
            value: selection
        )
        .help("Choose metric")
    }
}

private struct OverviewMetricPopUpButton: NSViewRepresentable {
    let selection: OverviewMetric
    let onSelect: (OverviewMetric) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: selection, onSelect: onSelect)
    }

    func makeNSView(context: Context) -> InvisibleMenuButton {
        let button = InvisibleMenuButton(frame: .zero)
        button.target = context.coordinator
        button.action = #selector(Coordinator.showMenu(_:))
        button.setAccessibilityRole(.menuButton)
        button.setAccessibilityLabel("Metric")
        return button
    }

    func updateNSView(_ button: InvisibleMenuButton, context: Context) {
        context.coordinator.selection = selection
        context.coordinator.onSelect = onSelect
        button.setAccessibilityValue(String(localized: selection.title))
        button.toolTip = "Choose metric"
    }

    final class Coordinator: NSObject {
        var selection: OverviewMetric
        var onSelect: (OverviewMetric) -> Void

        init(selection: OverviewMetric, onSelect: @escaping (OverviewMetric) -> Void) {
            self.selection = selection
            self.onSelect = onSelect
        }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false

            for metric in OverviewMetric.allCases {
                let title = String(localized: metric.title)
                let item = NSMenuItem(
                    title: title,
                    action: #selector(didSelectMetric(_:)),
                    keyEquivalent: ""
                )
                let image = NSImage(
                    systemSymbolName: metric.symbolName,
                    accessibilityDescription: title
                )
                image?.size = NSSize(width: 15, height: 15)
                image?.isTemplate = true
                if let image {
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    attachment.bounds = NSRect(x: 0, y: -2, width: 15, height: 15)
                    let attributedTitle = NSMutableAttributedString(attachment: attachment)
                    attributedTitle.append(NSAttributedString(string: "  \(title)"))
                    item.attributedTitle = attributedTitle
                }
                item.state = metric == selection ? .on : .off
                item.representedObject = metric.rawValue
                item.target = self
                menu.addItem(item)
            }

            let selectedItem = menu.items.first { $0.state == .on }
            menu.popUp(
                positioning: selectedItem,
                at: NSPoint(x: 0, y: sender.bounds.midY),
                in: sender
            )
        }

        @objc func didSelectMetric(_ item: NSMenuItem) {
            guard
                let rawValue = item.representedObject as? String,
                let metric = OverviewMetric(rawValue: rawValue)
            else { return }
            onSelect(metric)
        }
    }

    final class InvisibleMenuButton: NSButton {
        override var intrinsicContentSize: NSSize {
            NSSize(width: 142, height: 44)
        }

        override func draw(_ dirtyRect: NSRect) {}
    }
}

private struct OverviewMetricStatusLine: View {
    let metric: OverviewMetric
    let liveMachineCount: Int
    let machineCount: Int
    let activeAgentCount: Int
    let agentCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)
                .accessibilityHidden(true)

            if metric == .ai {
                Text("\(activeAgentCount) active · \(agentCount) tracked")
            } else {
                Text("\(liveMachineCount) of \(machineCount) live")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var statusColor: Color {
        if metric == .ai {
            return activeAgentCount > 0 ? .green : .blue
        }
        return liveMachineCount == machineCount ? .green : .orange
    }
}

private struct OverviewMetricContent: View {
    let machines: [MachineMonitorModel]
    let agentSessions: [MachineAgentSession]
    var selectedMachine: MachineID?
    @Binding var hoveredAgentID: MachineAgentSession.ID?
    let metric: OverviewMetric
    var compactionThresholds = AgentCompactionThresholds()
    var agentCPU: [String: Double] = [:]
    var agentCompactedAt: [String: Date] = [:]
    var namespace: Namespace.ID?
    var onSelectMetric: ((MachineID) -> Void)?
    var onSelectMachine: ((MachineID) -> Void)?

    var body: some View {
        if metric == .ai {
            // One machine at a time, like the metric detail screens.
            let focused = AgentPanelFocus.machine(
                for: agentSessions,
                selected: selectedMachine,
                order: machines.map(\.machine)
            )
            AIAgentsView(
                sessions: AgentPanelFocus.sessions(agentSessions, on: focused),
                hoveredAgentID: $hoveredAgentID,
                onSelectMachine: onSelectMetric,
                workload: HerdWorkloadReader.finding(for: workloadInputs),
                compactionThresholds: compactionThresholds,
                agentCPU: agentCPU,
                agentCompactedAt: agentCompactedAt,
                machineName: machines.first { $0.machine == focused }?.shortName,
                destinationAccounts: machines.map(\.destinationAccount)
            )
        } else {
            CPUOverviewView(
                machines: machines,
                metric: metric,
                namespace: namespace,
                onSelectMetric: onSelectMetric,
                onSelectMachine: onSelectMachine
            )
        }
    }

    /// Both halves of the join, read from the models that already hold them.
    /// The sustained average is computed the same way the menu bar computes
    /// it, so the panel and the menu bar cannot disagree about which machine
    /// is busy.
    private var workloadInputs: [HerdWorkloadInput] {
        machines.map { machine in
            HerdWorkloadInput(
                machine: machine.machine,
                name: machine.shortName,
                isLive: machine.state == .live,
                sustainedCPUPercent: SustainedLoad.average(
                    of: machine.cpu.history,
                    endingAt: machine.lastUpdated ?? .now
                ),
                activeSessionCount: agentSessions.count {
                    $0.machine == machine.machine
                        && $0.session.state == .active
                }
            )
        }
    }
}

private struct MachineMetricsView: View {
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
private struct MachineDetailBar: View {
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
private struct MachineMetricDetail: View {
    let machine: MachineMonitorModel
    let metric: OverviewMetric
    var namespace: Namespace.ID?
    let onBack: () -> Void
    var onSignIn: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                VStack(spacing: 6) {
                    OverviewMetricValue(
                        metric: metric,
                        value: presentation.value,
                        memoryPressure: presentation.memoryPressure
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
                onSignIn: onSignIn
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
private struct MachineMetricDetailContent: View {
    let machine: MachineMonitorModel
    let metric: OverviewMetric
    var onSignIn: (() -> Void)?

    var body: some View {
        switch metric {
        case .cpu: MachineProcessPane(machine: machine, onSignIn: onSignIn)
        case .memory: MachineMemoryPane(machine: machine, onSignIn: onSignIn)
        case .disk: MachineStoragePane(machine: machine, onSignIn: onSignIn)
        case .ai: MachineAgentPane(machine: machine, onSignIn: onSignIn)
        }
    }
}

private struct MachineProcessPane: View {
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

private struct MachineMemoryPane: View {
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

private struct MachineStoragePane: View {
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

private struct MachineAgentPane: View {
    let machine: MachineMonitorModel
    var onSignIn: (() -> Void)?

    var body: some View {
        MetricDetailPane(
            title: "AGENTS",
            summary: sessions.isEmpty
                ? nil
                : Text("\(sessions.count { $0.state == .active }) active"),
            emptyMessage: sessions.isEmpty ? agentEmptyMessage : nil,
            emptyAction: onSignIn
        ) {
            ForEach(sessions) { session in
                MetricDetailRow(
                    symbolName: "sparkles",
                    tint: session.provider == .codex ? .green : .orange,
                    // The same three things the overview panel shows, so a
                    // session reads the same on both screens: its own name,
                    // what it is doing, and how long since it moved.
                    title: Text(session.displayTitle),
                    subtitle: session.statusLine.map(Text.init),
                    value: Text(AIAgentRow.compactAge(of: session.updatedAt))
                )
            }
        }
    }

    private var sessions: [AgentSession] { machine.agentSessions }

    private func sessionDetail(for session: AgentSession) -> String {
        if let step = session.progress?.currentStep, !step.isEmpty {
            return step
        }
        let elapsed = Date.now.timeIntervalSince(session.updatedAt)
        guard elapsed >= 60 else { return "just now" }
        return Duration.seconds(elapsed).formatted(
            .units(allowed: [.hours, .minutes], width: .narrow)
        ) + " ago"
    }

    private var agentEmptyMessage: LocalizedStringResource {
        machine.state == .live
            ? "No recent agent sessions"
            : unavailableMessage(for: machine)
    }
}

/// One message for every pane, so an unreachable machine reads the same way
/// whichever metric you are looking through.
private func unavailableMessage(
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
private struct MachineIdentityRail: View {
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

struct HoveredMachineActivityHeader: View {
    let machine: MachineMonitorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(machine.status.tint)
                    .frame(width: 5, height: 5)
                    .accessibilityLabel(machine.status.label)

                MachineAvatarView(avatar: machine.avatar, size: 18)

                Text(machine.shortName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("WHAT IT’S DOING")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.35)
                    .foregroundStyle(.secondary)

                HoveredMachineCPUValue(
                    value: machine.state == .live ? machine.cpu.value : nil
                )
            }

            HoveredMachineActivityRows(
                state: machine.state,
                activities: machine.activities,
                unavailability: machine.unavailability
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

}

private struct HoveredMachineCPUValue: View {
    let value: Double?

    var body: some View {
        if let value {
            Text(value / 100, format: .percent.precision(.fractionLength(0)))
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(value > 99 ? Color.red : Color.secondary)
                .contentTransition(.numericText(value: value))
        } else {
            Text("—")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

private struct AIUsageLimitsSummary: View {
    let model: AIUsageLimitsModel

    var body: some View {
        AIUsageLimitRows(
            codex: model.codex,
            claude: model.claude
        )
        .fixedSize()
    }
}

private struct AIUsageLimitRows: View {
    let codex: AIUsageAvailability
    let claude: AIUsageAvailability

    var body: some View {
        VStack(spacing: 0) {
            AIUsageLimitRow(
                provider: .codex,
                availability: codex
            )
            AIUsageLimitRow(
                provider: .claude,
                availability: claude
            )
        }
    }
}

private struct AIUsageLimitRow: View {
    let provider: AIUsageProvider
    let availability: AIUsageAvailability

    /// Asked on each render rather than cached: the answer changes the moment
    /// someone starts or quits CodexBar, and a stale "not running" that offers
    /// to start an app already running is worse than no offer.
    private var offer: CodexBarOffer {
        CodexBarOffer.resolve(
            availability: availability,
            isInstalled: CodexBarSource.isInstalled,
            isRunning: CodexBarSource.isRunning
        )
    }

    var body: some View {
        AIUsageProviderControl(
            provider: provider,
            limit: limit,
            // A reading nobody can see is as useless as no reading, so every
            // state that cannot show a number offers the provider's own usage
            // page instead. Previously only the urgent state was clickable,
            // which left the one case with nothing to show also with nothing
            // to do. The link goes to the provider rather than to CodexBar:
            // Little Herd reads that app but does not recommend it.
            isActionable: isUrgent || limit == nil,
            accessibilityValue: accessibilityValue,
            helpText: helpText,
            offer: offer
        )
    }

    private var limit: AIUsageLimit? {
        availability.limit
    }

    private var isUrgent: Bool {
        limit?.budgetStatus == .urgent
    }

    private var accessibilityValue: Text {
        if let limit {
            Text(
                "\(limit.remainingPercent / 100, format: .percent.precision(.fractionLength(0))) left"
            )
        } else {
            Text("Usage unavailable")
        }
    }

    private var helpText: Text {
        if let limit, let resetsAt = limit.resetsAt {
            if isUrgent {
                Text(
                    "\(provider.displayName): \(limit.remainingPercent / 100, format: .percent.precision(.fractionLength(0))) remaining in the \(limit.windowDescription). Resets \(resetsAt, format: .dateTime.month().day().hour().minute()). Click to open usage and billing."
                )
            } else {
                Text(
                    "\(provider.displayName): \(limit.remainingPercent / 100, format: .percent.precision(.fractionLength(0))) remaining in the \(limit.windowDescription). Resets \(resetsAt, format: .dateTime.month().day().hour().minute())."
                )
            }
        } else if let limit {
            if isUrgent {
                Text(
                    "\(provider.displayName): \(limit.remainingPercent / 100, format: .percent.precision(.fractionLength(0))) remaining in the \(limit.windowDescription). Click to open usage and billing."
                )
            } else {
                Text(
                    "\(provider.displayName): \(limit.remainingPercent / 100, format: .percent.precision(.fractionLength(0))) remaining in the \(limit.windowDescription)."
                )
            }
        } else {
            switch availability {
            case .available:
                Text("\(provider.displayName) usage unavailable")
            case .sourceMissing:
                Text(
                    "\(provider.displayName) usage needs CodexBar, which isn’t installed on this Mac. Little Herd reads it; it can’t measure this itself. Click to see what it is."
                )
            case let .stale(since):
                Text(
                    "\(provider.displayName) usage last updated \(since, format: .relative(presentation: .named)). CodexBar isn’t running, so the figure has stopped moving. Click to start it."
                )
            case .noReading:
                Text(
                    "CodexBar has no \(provider.displayName) reading yet. Click to open usage and billing."
                )
            }
        }
    }
}

private struct AIUsageProviderControl: View {
    let provider: AIUsageProvider
    let limit: AIUsageLimit?
    let isActionable: Bool
    let accessibilityValue: Text
    let helpText: Text
    /// What to offer about the source itself, when the number is missing
    /// because of the source rather than because of the vendor.
    var offer: CodexBarOffer = .none

    var body: some View {
        if offer == .start {
            // A number that stopped moving is fixed by starting the thing that
            // moves it, not by opening a billing page. One click, no dialog:
            // the app is already on this Mac and starting it is undone by
            // quitting it.
            Button {
                CodexBarSource.launchIfNeeded()
            } label: {
                AIUsageProviderStatusMark(provider: provider, limit: limit)
            }
            .buttonStyle(.plain)
            .help(helpText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(provider.displayName))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Start CodexBar to resume usage readings")
        } else if offer == .install {
            Link(destination: CodexBarSource.downloadURL) {
                AIUsageProviderStatusMark(provider: provider, limit: limit)
            }
            .buttonStyle(.plain)
            .help(helpText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(provider.displayName))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Open the CodexBar project page")
        } else if isActionable {
            Link(destination: provider.usageAndBillingURL) {
                AIUsageProviderStatusMark(provider: provider, limit: limit)
            }
            .buttonStyle(.plain)
            .help(helpText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(provider.displayName))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Open usage and billing")
        } else {
            AIUsageProviderStatusMark(provider: provider, limit: limit)
                .help(helpText)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(provider.displayName))
                .accessibilityValue(accessibilityValue)
        }
    }
}

private struct AIUsageProviderStatusMark: View {
    let provider: AIUsageProvider
    let limit: AIUsageLimit?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AIUsageProviderIcon(provider: provider)

            AIUsageStatusLED(limit: limit)
                .offset(x: 2.5, y: 2.5)
        }
        .frame(width: 18, height: 18)
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
}

private struct AIUsageStatusLED: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let limit: AIUsageLimit?
    @State private var isDimmed = false

    var body: some View {
        statusShape
            .frame(width: 9, height: 9)
            // Follows the window, not a fixed white: this dot sits on the
            // avatar and has to separate from whatever is behind it.
            .background(LittleHerdTheme.background.opacity(0.96), in: Circle())
            .overlay {
                Circle()
                    .stroke(LittleHerdTheme.background, lineWidth: 1.25)
            }
            .scaleEffect(isBlinking && isDimmed ? 0.86 : 1)
            .opacity(isBlinking && isDimmed ? 0.35 : 1)
            .animation(
                isBlinking && !reduceMotion
                    ? .easeInOut(duration: 0.56).repeatForever()
                    : .easeOut(duration: 0.16),
                value: isDimmed
            )
            .animation(.easeInOut(duration: 0.35), value: limit?.remainingPercent)
            .onAppear {
                updateBlinkingState()
            }
            .onChange(of: isBlinking) { _, _ in
                updateBlinkingState()
            }
            .onChange(of: reduceMotion) { _, _ in
                updateBlinkingState()
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statusShape: some View {
        if let limit {
            Circle()
                .fill(statusColor(for: limit.budgetStatus))
        } else {
            Circle()
                .stroke(Color.secondary.opacity(0.42), lineWidth: 1)
        }
    }

    private var isBlinking: Bool {
        limit?.budgetStatus == .urgent && !reduceMotion
    }

    private var statusColor: Color {
        guard let limit else { return .clear }
        return statusColor(for: limit.budgetStatus)
    }

    private func statusColor(for status: AIUsageBudgetStatus) -> Color {
        switch status {
        case .normal: .green
        case .warning: .yellow
        case .critical: .orange
        case .urgent: .red
        }
    }

    private func updateBlinkingState() {
        isDimmed = isBlinking
    }
}

private struct AIUsageProviderIcon: View {
    let provider: AIUsageProvider

    var body: some View {
        Image(nsImage: AIUsageProviderIcons.icon(for: provider))
            .resizable()
            .scaledToFit()
            .foregroundStyle(providerColor)
            .frame(width: 14, height: 14)
    }

    private var providerColor: Color {
        switch provider {
        case .codex: .primary
        case .claude: Color(red: 0.91, green: 0.29, blue: 0.16)
        }
    }
}

@MainActor
private enum AIUsageProviderIcons {
    static let codex = providerGlyph(
        bundleIdentifier: "com.openai.codex",
        resourceName: "chatgptTemplate@2x",
        fallbackSymbolName: "sparkles"
    )
    static let claude = providerGlyph(
        bundleIdentifier: "com.anthropic.claudefordesktop",
        resourceName: "TrayIconTemplate-Dark@3x",
        fallbackSymbolName: "brain.head.profile"
    )

    static func icon(for provider: AIUsageProvider) -> NSImage {
        switch provider {
        case .codex: codex
        case .claude: claude
        }
    }

    static func icon(for provider: AgentTaskProvider) -> NSImage {
        switch provider {
        case .codex: codex
        case .claude: claude
        }
    }

    private static func providerGlyph(
        bundleIdentifier: String,
        resourceName: String,
        fallbackSymbolName: String
    ) -> NSImage {
        if let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ),
           let bundle = Bundle(url: applicationURL),
           let imageURL = bundle.url(
               forResource: resourceName,
               withExtension: "png"
           ),
           let image = NSImage(contentsOf: imageURL)
        {
            image.isTemplate = true
            return image
        }

        let fallback = NSImage(
            systemSymbolName: fallbackSymbolName,
            accessibilityDescription: nil
        ) ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }
}

private struct HoveredMachineActivityRows: View {
    let state: MonitorConnectionState
    let activities: [MachineActivity]
    var unavailability: RemoteUnavailability?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if state == .live, !activities.isEmpty {
                ForEach(activities.prefix(3), id: \.processName) { activity in
                    HoveredMachineActivityRow(activity: activity)
                }
            } else {
                Text(stateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stateLabel: LocalizedStringResource {
        switch state {
        case .connecting: "Checking activity…"
        case .live: "No notable CPU activity"
        case .offline: "Unreachable"
        case .stopped: "Monitoring paused"
        }
    }
}

private struct HoveredMachineActivityRow: View {
    let activity: MachineActivity

    var body: some View {
        HStack(spacing: 4) {
            ActivitySourceIcon(activity: activity)

            if activity.agentTask == nil {
                Text("CPU")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(activityTint)
                    .fixedSize()
            }

            activityDisplayTitle
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 3)

            Text(
                "\(activity.cpuCores, format: .number.precision(.fractionLength(1)))c"
            )
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
        }
        .font(.caption)
        .help(Text(activity.tooltip))
        .accessibilityElement(children: .combine)
    }

    private var activityDisplayTitle: Text {
        if let agentTask = activity.agentTask {
            Text(agentTask.projectName)
        } else {
            Text(activity.shortLabel)
        }
    }

    private var activityTint: Color {
        switch activity.kind {
        case .codex, .claudeCode:
            .purple
        case .compiling, .building:
            .orange
        default:
            .secondary
        }
    }
}

private struct ActivitySourceIcon: View {
    let activity: MachineActivity

    var body: some View {
        if let provider = activity.agentTask?.provider {
            Image(systemName: "sparkles")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint(for: provider))
                .frame(width: 12)
                .help(Text(provider.displayName))
                .accessibilityLabel(Text(provider.displayName))
        } else {
            Image(systemName: activity.symbolName)
                .foregroundStyle(symbolTint)
                .frame(width: 12)
                .accessibilityHidden(true)
        }
    }

    private func tint(for provider: AgentTaskProvider) -> Color {
        switch provider {
        case .codex: .blue
        case .claude: .orange
        }
    }

    private var symbolTint: Color {
        switch activity.kind {
        case .compiling, .building:
            .orange
        default:
            .secondary
        }
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
private struct MachineConnectionLabel: View {
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
