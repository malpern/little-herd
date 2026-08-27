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
                            herd: model.machines.map(\.destinationAccount),
                            namespace: machineTransition,
                            onBack: { model.selection = .overview },
                            onSignIn: signInAction(for: selectedMachine),
                            onAllow: allow
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
                            metric: model.overviewMetric,
                            compactionThresholds: model.compactionThresholds,
                            agentCPU: model.agentCPU,
                            agentCompactedAt: model.agentCompactedAt,
                            namespace: machineTransition,
                            onSelectMetric: { model.selection = .machineMetric($0) },
                            onSelectMachine: { model.selection = .machine($0) },
                            onSelectAgents: { model.showAgents(on: $0) },
                            herd: model.machines.map(\.destinationAccount),
                            // Only here. The menu bar draws its own rows and
                            // is dismissed by the click that would read the
                            // card anyway.
                            announcesArrivals: true
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

    /// Records that a machine may host work, and *persists it*.
    ///
    /// Through the configuration store, not the machine model: the model's own
    /// setter changes memory and nothing else, because persistence used to
    /// flow the other way — from a Settings checkbox that edited the stored
    /// configuration and pushed it down. A permission that a relaunch forgets
    /// is worse than no permission, so this writes first and lets
    /// `applyConfigurations` carry the answer back into the herd.
    private func allow(_ machine: MachineID, _ mayHost: Bool) {
        guard let store = machineStore,
              store.setMayHostSessions(mayHost, on: machine)
        else { return }
        onConfigurationsChanged(store.machines)
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
            // name, so it needs more room than the other three. The extra
            // width and height over the original 300 x 296 are the agent pads:
            // they are surfaces with things resting on them, and a surface
            // that touches the window edge reads as a rendering mistake rather
            // than a place.
            return DashboardMetrics.overviewContent
        }
        return model.selection.isMetricFocus
            ? DashboardMetrics.metricFocusContent
            : DashboardMetrics.machineContent
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

private struct OverviewMetricContent: View {
    let machines: [MachineMonitorModel]
    let agentSessions: [MachineAgentSession]
    var selectedMachine: MachineID?
    let metric: OverviewMetric
    var compactionThresholds = AgentCompactionThresholds()
    var agentCPU: [String: Double] = [:]
    var agentCompactedAt: [String: Date] = [:]
    var namespace: Namespace.ID?
    var onSelectMetric: ((MachineID) -> Void)?
    var onSelectMachine: ((MachineID) -> Void)?
    /// Opens a machine's AI page — what an agent token on the overview points
    /// at, which is neither the machine's summary nor the current metric.
    var onSelectAgents: ((MachineID) -> Void)?
    var herd: [DestinationAccount] = []
    var announcesArrivals = false

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
                onSelectMachine: onSelectMetric,
                workload: HerdWorkloadReader.finding(for: workloadInputs),
                compactionThresholds: compactionThresholds,
                agentCPU: agentCPU,
                agentCompactedAt: agentCompactedAt,
                machineName: machines.first { $0.machine == focused }?.shortName
            )
        } else {
            CPUOverviewView(
                machines: machines,
                metric: metric,
                namespace: namespace,
                onSelectMetric: onSelectMetric,
                onSelectMachine: onSelectMachine,
                onSelectAgents: onSelectAgents,
                agentCPU: agentCPU,
                herd: herd,
                announcesArrivals: announcesArrivals
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
