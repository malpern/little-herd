import AppKit
import SwiftUI

struct DashboardView: View {
    let model: MonitorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(
        LittleHerdPreferences.networkVolumeAccessOnboardingCompletedKey
    )
    private var hasCompletedNetworkVolumeOnboarding = false
    @State private var hoveredMachineID: MachineID?
    @State private var hoveredAgentID: MachineAgentSession.ID?
    @State private var isShowingLaunchSplash =
        LittleHerdLaunchSplashSession.claimPresentation()
    @State private var isShowingNetworkVolumeOnboarding = false
    @State private var isRequestingNetworkVolumeAccess = false

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
                    if let selectedMachine = model.selectedMachine {
                        MachineDashboardHeader(
                            machine: selectedMachine,
                            lastUpdated: selectedMachine.lastUpdated,
                            state: selectedMachine.state,
                            aiUsageLimits: model.aiUsageLimits
                        )
                    } else {
                        CPUOverviewHeaderArea(
                            machines: model.overviewMachines,
                            hoveredMachineID: hoveredMachineID,
                            agentSessions: agentSessions,
                            hoveredAgentID: hoveredAgentID,
                            aiUsageLimits: model.aiUsageLimits,
                            metric: model.overviewMetric,
                            onSelect: model.showOverview
                        )
                    }

                    Divider()
                        .padding(.horizontal, 14)

                    if let selectedMachine = model.selectedMachine {
                        MachineMetricsView(machine: selectedMachine)
                    } else {
                        OverviewMetricContent(
                            machines: model.overviewMachines,
                            hoveredMachineID: $hoveredMachineID,
                            agentSessions: agentSessions,
                            hoveredAgentID: $hoveredAgentID,
                            metric: model.overviewMetric
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
        .environment(\.colorScheme, .light)
        .animation(.easeInOut(duration: 0.22), value: model.overviewMetric)
        .task {
            await advanceLaunchFlowWhenReady()
        }
        .onAppear {
            model.setNetworkStorageMonitoringEnabled(
                hasCompletedNetworkVolumeOnboarding
                    && !shouldPresentNetworkVolumeOnboarding
            )
            model.activate(.dashboard)
        }
        .onDisappear {
            model.deactivate(.dashboard)
        }
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
            ? CGSize(width: 300, height: 218)
            : dashboardContentSize
    }

    /// NSSize and CGSize are the same type on macOS, so the window bridge and
    /// the SwiftUI frame read one table rather than two that can drift apart.
    private var dashboardContentSize: NSSize {
        if isShowingNetworkVolumeOnboarding {
            return NSSize(width: 420, height: 374)
        }
        return model.selection == .overview
            ? NSSize(width: 300, height: 250)
            : NSSize(width: 420, height: 326)
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
            let minimumSplashDuration = min(max(configuredDelay ?? 1.05, 0), 10)
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
    let hoveredMachineID: MachineID?
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
            } else if metric != .ai,
                      let hoveredMachine = machines.first(where: {
                $0.machine == hoveredMachineID
                      })
            {
                HoveredMachineMetricHeader(
                    machine: hoveredMachine,
                    metric: metric
                )
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
    @Binding var hoveredMachineID: MachineID?
    let agentSessions: [MachineAgentSession]
    @Binding var hoveredAgentID: MachineAgentSession.ID?
    let metric: OverviewMetric

    var body: some View {
        if metric == .ai {
            AIAgentsView(
                sessions: agentSessions,
                hoveredAgentID: $hoveredAgentID
            )
        } else if metric == .disk {
            DiskOverviewView(
                machines: machines,
                hoveredMachineID: $hoveredMachineID
            )
        } else {
            CPUOverviewView(
                machines: machines,
                hoveredMachineID: $hoveredMachineID,
                metric: metric
            )
        }
    }
}

private struct MachineMetricsView: View {
    let machine: MachineMonitorModel

    var body: some View {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

private struct MachineDashboardHeader: View {
    let machine: MachineMonitorModel
    let lastUpdated: Date?
    let state: MonitorConnectionState
    let aiUsageLimits: AIUsageLimitsModel

    var body: some View {
        HStack(spacing: 10) {
            MachineAvatarView(avatar: machine.avatar, size: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(machine.name)
                    .font(.headline)
                    .lineLimit(1)

                MachineConnectionLabel(
                    lastUpdated: lastUpdated,
                    state: state,
                    unavailability: machine.unavailability,
                    hostname: machine.hostname
                )
            }

            Spacer(minLength: 8)

            AIUsageLimitsSummary(model: aiUsageLimits)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}

struct HoveredMachineActivityHeader: View {
    let machine: MachineMonitorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                    .accessibilityLabel(statusLabel)

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

    private var statusColor: Color {
        switch machine.state {
        case .connecting: .orange
        case .live: .green
        case .offline: .red
        case .stopped: .secondary
        }
    }

    private var statusLabel: LocalizedStringResource {
        switch machine.state {
        case .connecting: "Connecting"
        case .live: "Live"
        case .offline: "Unreachable"
        case .stopped: "Paused"
        }
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
    let codex: AIUsageLimit?
    let claude: AIUsageLimit?

    var body: some View {
        VStack(spacing: 0) {
            AIUsageLimitRow(
                provider: .codex,
                limit: codex
            )
            AIUsageLimitRow(
                provider: .claude,
                limit: claude
            )
        }
    }
}

private struct AIUsageLimitRow: View {
    let provider: AIUsageProvider
    let limit: AIUsageLimit?

    var body: some View {
        AIUsageProviderControl(
            provider: provider,
            limit: limit,
            isUrgent: isUrgent,
            accessibilityValue: accessibilityValue,
            helpText: helpText
        )
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
            Text("\(provider.displayName) usage unavailable from CodexBar")
        }
    }
}

private struct AIUsageProviderControl: View {
    let provider: AIUsageProvider
    let limit: AIUsageLimit?
    let isUrgent: Bool
    let accessibilityValue: Text
    let helpText: Text

    var body: some View {
        if isUrgent {
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
            .background(Color.white.opacity(0.96), in: Circle())
            .overlay {
                Circle()
                    .stroke(Color.white, lineWidth: 1.25)
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

private struct MachineConnectionLabel: View {
    let lastUpdated: Date?
    let state: MonitorConnectionState
    var unavailability: RemoteUnavailability?
    var hostname: String = ""

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)

            if let lastUpdated, state == .live {
                Text("Updated \(lastUpdated, format: .dateTime.hour().minute().second())")
            } else {
                switch state {
                case .connecting:
                    Text("Connecting…")
                case .live:
                    Text("Live")
                case .offline:
                    Text("Unavailable")
                case .stopped:
                    Text("Paused")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .help(helpText)
    }

    /// The status line has room for two words; the reason someone can act on
    /// goes here, where it costs nothing until they look for it.
    private var helpText: Text {
        guard state == .offline, let unavailability else { return Text("") }
        return Text(unavailability.detail(host: hostname))
    }

    private var statusColor: Color {
        switch state {
        case .connecting: .orange
        case .live: .green
        case .offline, .stopped: .secondary
        }
    }
}
