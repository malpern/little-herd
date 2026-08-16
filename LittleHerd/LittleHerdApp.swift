import AppKit
import SwiftUI

private final class LittleHerdAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }
}

@main
struct LittleHerdApp: App {
    @NSApplicationDelegateAdaptor(LittleHerdAppDelegate.self)
    private var appDelegate
    @State private var model: MonitorModel
    @State private var machineStore: MachineConfigurationStore
    @State private var updater = SoftwareUpdater()
    @AppStorage(LittleHerdPreferences.menuBarEnabledKey)
    private var menuBarEnabled = false

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
        LittleHerdPreferences.migrateLegacySettingsIfNeeded()
        let machineStore = MachineConfigurationStore()
        let isForcingNetworkOnboarding = ProcessInfo.processInfo.environment[
            "LITTLE_HERD_SHOW_NETWORK_ONBOARDING"
        ] == "1"
        _machineStore = State(initialValue: machineStore)
        let model = MonitorModel(
            configurations: machineStore.machines,
            networkStorageMonitoringEnabled:
                !isForcingNetworkOnboarding
                && UserDefaults.standard.bool(
                    forKey: LittleHerdPreferences
                        .networkVolumeAccessOnboardingCompletedKey
                )
        )
        // Remember the certificate a NAS presented the first time it answered,
        // so a later change to it is refused rather than trusted.
        model.onCertificateDiscovered = { [machineStore, weak model] machineID, fingerprint in
            guard var configuration = machineStore.machines.first(where: {
                $0.id == machineID
            }), configuration.dsmCertificateFingerprint == nil else {
                return
            }
            configuration.dsmCertificateFingerprint = fingerprint
            machineStore.update(configuration)
            // Rebuild so the pin takes effect now rather than on next launch.
            // Without this, the session that first sees a certificate keeps
            // running with nothing to check against — which is exactly the
            // session an impersonating server would want.
            model?.applyConfigurations(machineStore.machines)
        }
        _model = State(initialValue: model)
    }

    var body: some Scene {
        Window("Little Herd", id: LittleHerdWindowID.dashboard) {
            DashboardView(model: model)
                .toolbar(removing: .title)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        }
        .defaultSize(width: 420, height: 326)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Little Herd") {
                    AboutLittleHerdPresenter.present()
                }

                Button("Check for Updates…") {
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates)
            }
            AddMachinesCommands()
            DashboardCommands(model: model)
        }

        Window("Add Machines", id: LittleHerdWindowID.addMachines) {
            AddMachinesSceneView(
                store: machineStore,
                onConfigurationsChanged: model.applyConfigurations
            )
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 728, height: 503)
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact(showsTitle: true))

        MenuBarExtra(isInserted: $menuBarEnabled) {
            MenuBarPanel(model: model)
        } label: {
            MenuBarStatusLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            LittleHerdSettingsView(
                machineStore: machineStore,
                onConfigurationsChanged: model.applyConfigurations
            )
        }
    }
}

enum LittleHerdPreferences {
    static let menuBarEnabledKey = "menuBarItemEnabled"
    static let machineConfigurationsKey = "machineConfigurationsV1"
    static let alertsEnabledKey = "alertsEnabled"
    static let networkVolumeAccessOnboardingCompletedKey =
        "networkVolumeAccessOnboardingCompleted"

    private static let legacyBundleIdentifier = "com.malpern.Pulseboard"
    private static let legacyMigrationCompletedKey =
        "didMigrateFromPulseboardPreferences"

    static func migrateLegacySettingsIfNeeded(
        defaults: UserDefaults = .standard,
        legacyDomain suppliedLegacyDomain: [String: Any]? = nil
    ) {
        guard !defaults.bool(forKey: legacyMigrationCompletedKey) else { return }

        let legacyDomain = suppliedLegacyDomain
            ?? defaults.persistentDomain(forName: legacyBundleIdentifier)
            ?? [:]
        for key in [
            menuBarEnabledKey,
            machineConfigurationsKey,
            networkVolumeAccessOnboardingCompletedKey,
        ] where defaults.object(forKey: key) == nil {
            if let value = legacyDomain[key] {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: legacyMigrationCompletedKey)
    }
}

enum LittleHerdWindowID {
    static let dashboard = "dashboard"
    static let addMachines = "add-machines"
}

private extension MachineMonitorModel {
    var menuBarSnapshot: MenuBarMachineSnapshot {
        let diskMetric = metrics.first(where: { $0.kind == .disk })?.value
        return MenuBarMachineSnapshot(
            machine: machine,
            state: state,
            cpuPercent: cpu.value,
            memoryPressure: memoryPressure,
            diskUsedPercent: storageVolumes.map(\.usedPercent).max() ?? diskMetric,
            storageHealth: storageConcern?.health
        )
    }
}

private struct MenuBarStatusLabel: View {
    let model: MonitorModel

    var body: some View {
        Group {
            switch headline {
            case .connecting:
                Label("Connecting", systemImage: "ellipsis.circle")

            case let .normal(machine, cpuPercent, _, _):
                HStack(spacing: 3) {
                    Image(systemName: "waveform.path.ecg")
                    if let machine, let cpuPercent {
                        Text(model.shortName(for: machine))
                        Text("\(cpuPercent)%")
                    } else {
                        Text("Live")
                    }
                }

            case let .unavailable(live, total):
                Label("\(live)/\(total)", systemImage: "network.slash")

            case let .highCPU(machine, percent, critical):
                HStack(spacing: 3) {
                    Image(systemName: critical ? "exclamationmark.triangle.fill" : "cpu.fill")
                    Text(model.shortName(for: machine))
                    Text("\(percent)%")
                }

            case let .memoryPressure(machine, critical):
                HStack(spacing: 3) {
                    Image(systemName: critical ? "exclamationmark.triangle.fill" : "memorychip.fill")
                    Text(model.shortName(for: machine))
                    Text("RAM")
                }

            case let .lowDisk(machine, _, critical):
                HStack(spacing: 3) {
                    Image(systemName: critical ? "exclamationmark.triangle.fill" : "internaldrive.fill")
                    Text(model.shortName(for: machine))
                    Text("Disk")
                }

            case let .storageUnhealthy(machine, critical):
                HStack(spacing: 3) {
                    Image(systemName: critical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    Text(model.shortName(for: machine))
                    Text("Drive")
                }
            }
        }
        .onAppear {
            model.activate(.menuBar)
        }
        .onDisappear {
            model.deactivate(.menuBar)
        }
    }

    private var headline: MenuBarHeadline {
        MenuBarStatusSelector.headline(for: model.machines.map(\.menuBarSnapshot))
    }
}

private struct MenuBarPanel: View {
    let model: MonitorModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            MenuBarHeadlineView(headline: headline, model: model)
                .padding(16)

            Divider()

            VStack(spacing: 4) {
                ForEach(model.machines) { machine in
                    MenuBarMachineRow(machine: machine)
                }
            }
            .padding(10)

            Divider()

            HStack(spacing: 12) {
                Button {
                    showDashboard()
                } label: {
                    Label("Show Little Herd", systemImage: "macwindow")
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                SettingsLink()
                    .buttonStyle(.plain)
            }
            .font(.callout)
            .padding(12)
        }
        .frame(width: 292)
        .background(.background)
    }

    private var headline: MenuBarHeadline {
        MenuBarStatusSelector.headline(for: model.machines.map(\.menuBarSnapshot))
    }

    private func showDashboard() {
        // The dashboard is a single Window scene, so this focuses the existing
        // one and only creates it when there is none. Matching on the window's
        // title instead would break the moment the title is localized, and
        // every click would open another dashboard.
        openWindow(id: LittleHerdWindowID.dashboard)
        NSApp.activate()
    }
}

private struct MenuBarHeadlineView: View {
    let headline: MenuBarHeadline
    let model: MonitorModel

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbolName)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.headline)
                    .lineLimit(1)

                detail
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }

    private var symbolName: String {
        switch headline {
        case .connecting: "ellipsis.circle"
        case .normal: "checkmark.circle.fill"
        case .unavailable: "network.slash"
        case let .highCPU(_, _, critical),
             let .memoryPressure(_, critical),
             let .lowDisk(_, _, critical):
            critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"
        case let .storageUnhealthy(_, critical):
            critical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch headline {
        case .connecting: .secondary
        case .normal: .green
        case .unavailable: .red
        case let .highCPU(_, _, critical),
             let .memoryPressure(_, critical),
             let .lowDisk(_, _, critical):
            critical ? .red : .orange
        case let .storageUnhealthy(_, critical):
            critical ? .red : .orange
        }
    }

    @ViewBuilder
    private var title: some View {
        switch headline {
        case .connecting:
            Text("Connecting to machines")
        case .normal:
            Text("Systems steady")
        case let .unavailable(live, total):
            if total - live == 1 {
                Text("1 machine unavailable")
            } else {
                Text("\(total - live) machines unavailable")
            }
        case let .highCPU(machine, _, _):
            Text("High CPU on \(model.name(for: machine))")
        case let .memoryPressure(machine, _):
            Text("Memory pressure on \(model.name(for: machine))")
        case let .lowDisk(machine, _, _):
            Text("Storage low on \(model.name(for: machine))")
        case let .storageUnhealthy(machine, critical):
            if critical {
                Text("Drive failing on \(model.name(for: machine))")
            } else {
                Text("Drive needs attention on \(model.name(for: machine))")
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch headline {
        case let .connecting(live, total):
            Text("\(live) of \(total) live")
        case let .normal(_, cpuPercent, live, total):
            if let cpuPercent {
                Text("Busiest CPU is \(cpuPercent)% · \(live) of \(total) live")
            } else {
                Text("\(live) of \(total) live")
            }
        case let .unavailable(live, total):
            Text("\(live) of \(total) live")
        case let .highCPU(_, percent, _):
            Text("CPU is at \(percent)%")
        case let .memoryPressure(_, critical):
            Text(critical ? "Memory pressure is critical" : "Memory pressure is elevated")
        case let .lowDisk(_, usedPercent, _):
            Text("Disk is \(usedPercent)% full")
        case let .storageUnhealthy(_, critical):
            Text(
                critical
                    ? "A drive reports critical health"
                    : "A drive reports degraded health"
            )
        }
    }
}

private struct MenuBarMachineRow: View {
    let machine: MachineMonitorModel

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(connectionColor)
                .frame(width: 6, height: 6)

            MachineAvatarView(machine: machine.machine, size: 24)
                .frame(width: 24)

            Text(machine.name)
                .lineLimit(1)

            Spacer(minLength: 8)

            if machine.state == .live {
                if machine.memoryPressure == .warning || machine.memoryPressure == .critical {
                    Image(systemName: "memorychip.fill")
                        .foregroundStyle(machine.memoryPressure == .critical ? .red : .orange)
                        .help("Elevated memory pressure")
                }

                if diskUsedPercent >= 90 {
                    Image(systemName: "internaldrive.fill")
                        .foregroundStyle(diskUsedPercent >= 95 ? .red : .orange)
                        .help("Storage is nearly full")
                }

                Text(cpuText)
                    .monospacedDigit()
                    .foregroundStyle(cpuColor)
                    .frame(width: 38, alignment: .trailing)
            } else {
                Text(stateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(unavailabilityHelp)
            }
        }
        .font(.callout)
        .padding(.horizontal, 7)
        .frame(height: 34)
        .contentShape(Rectangle())
    }

    private var diskUsedPercent: Double {
        machine.menuBarSnapshot.diskUsedPercent ?? 0
    }

    private var cpuText: String {
        guard let value = machine.cpu.value else { return "—" }
        return "\(min(max(Int(value.rounded()), 0), 100))%"
    }

    private var cpuColor: Color {
        guard let value = machine.cpu.value else { return .secondary }
        if value >= 95 { return .red }
        if value >= 80 { return .orange }
        return .primary
    }

    private var connectionColor: Color {
        switch machine.state {
        case .connecting: .orange
        case .live: .green
        case .offline: .red
        case .stopped: .secondary
        }
    }

    private var stateText: LocalizedStringResource {
        switch machine.state {
        case .connecting: "Connecting"
        case .live: "Live"
        case .offline: "Unavailable"
        case .stopped: "Paused"
        }
    }

    private var unavailabilityHelp: Text {
        guard let unavailability = machine.unavailability else { return Text("") }
        return Text(unavailability.detail(host: machine.hostname))
    }
}

private struct LittleHerdSettingsView: View {
    let machineStore: MachineConfigurationStore
    let onConfigurationsChanged: ([MachineConfiguration]) -> Void
    @Environment(\.openWindow) private var openWindow
    @AppStorage(LittleHerdPreferences.menuBarEnabledKey)
    private var menuBarEnabled = false
    @AppStorage(LittleHerdPreferences.alertsEnabledKey)
    private var alertsEnabled = false
    @State private var configuringNAS: MachineConfiguration?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Toggle("Notify me when a machine needs attention", isOn: $alertsEnabled)
                    .font(.body.weight(.medium))

                Text("A notification when a disk is nearly full, memory is critical, or a machine stops responding — once per event, and once when it recovers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 7) {
                Toggle("Show status in menu bar", isOn: $menuBarEnabled)
                    .font(.body.weight(.medium))

                Text("Shows the busiest machine during normal use. High CPU, memory pressure, low storage, or an unreachable machine takes priority when attention is needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label(
                "Uses Little Herd’s existing low-frequency samples—no extra monitoring loop.",
                systemImage: "leaf"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Machines")
                        .font(.body.weight(.medium))
                    Text("\(machineStore.machines.count) saved. Discover nearby computers and add several at once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button("Add Machines…") {
                    openWindow(id: LittleHerdWindowID.addMachines)
                    NSApp.activate()
                }
            }

            VStack(spacing: 0) {
                ForEach(machineStore.machines) { machine in
                    SettingsMachineRow(
                        machine: machine,
                        canRemove: machineStore.canRemove(machine.id),
                        onRemove: { remove(machine.id) },
                        onConnect: { configuringNAS = machine }
                    )

                    if machine.id != machineStore.machines.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(24)
        .frame(width: 420)
        .sheet(item: $configuringNAS) { machine in
            SynologyCredentialsView(machine: machine) { updated in
                machineStore.update(updated)
                onConfigurationsChanged(machineStore.machines)
            }
        }
    }

    private func remove(_ machineID: MachineID) {
        machineStore.remove(machineID)
        onConfigurationsChanged(machineStore.machines)
    }
}

private struct SettingsMachineRow: View {
    let machine: MachineConfiguration
    let canRemove: Bool
    let onRemove: () -> Void
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(machine.avatar.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Text(machine.name)
                    .font(.callout)
                    .lineLimit(1)

                Text(machine.hostname)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Only a NAS has anything to sign in to. Storage machines start out
            // reading a mounted share; connecting to DSM is what gets them drive
            // health and measurements that do not depend on the Finder.
            if machine.isStorage {
                Button(machine.connection == .dsm ? "Connected" : "Connect…") {
                    onConnect()
                }
                .buttonStyle(.link)
                .font(.caption)
                .help(
                    machine.connection == .dsm
                        ? "Signed in to DSM as \(machine.dsmUsername ?? "?"). Click to change."
                        : "Sign in to DSM to read capacity and drive health without a mounted share"
                )
            }

            if canRemove {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Remove \(machine.name) from the herd")
                .accessibilityLabel("Remove \(machine.name)")
            } else {
                Text("This Mac")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 36)
    }
}

private struct AddMachinesCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Machines…") {
                openWindow(id: LittleHerdWindowID.addMachines)
                NSApp.activate()
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }
}

private struct DashboardCommands: Commands {
    let model: MonitorModel

    var body: some Commands {
        CommandGroup(replacing: .toolbar) {
            OverviewDestinationButton(
                title: "CPU",
                symbolName: "cpu",
                shortcut: "1",
                metric: .cpu,
                model: model
            )

            OverviewDestinationButton(
                title: "RAM",
                symbolName: "memorychip",
                shortcut: "2",
                metric: .memory,
                model: model
            )

            OverviewDestinationButton(
                title: "Disk",
                symbolName: "internaldrive",
                shortcut: "3",
                metric: .disk,
                model: model
            )

            OverviewDestinationButton(
                title: "AI",
                symbolName: "sparkles",
                shortcut: "4",
                metric: .ai,
                model: model
            )

            Divider()

            ForEach(model.machines) { machine in
                DashboardDestinationButton(
                    title: machine.name,
                    symbolName: machine.symbolName,
                    destination: .machine(machine.machine),
                    model: model
                )
            }

        }
    }
}

private struct OverviewDestinationButton: View {
    let title: LocalizedStringResource
    let symbolName: String
    let shortcut: KeyEquivalent
    let metric: OverviewMetric
    let model: MonitorModel

    var body: some View {
        Button {
            model.showOverview(metric)
        } label: {
            Label(
                title,
                systemImage: isSelected ? "checkmark" : symbolName
            )
        }
        .keyboardShortcut(shortcut, modifiers: .command)
    }

    private var isSelected: Bool {
        model.selection == .overview && model.overviewMetric == metric
    }
}

private struct DashboardDestinationButton: View {
    let title: String
    let symbolName: String
    let destination: DashboardSelection
    let model: MonitorModel

    var body: some View {
        Button {
            model.selection = destination
        } label: {
            Label(
                title,
                systemImage: model.selection == destination ? "checkmark" : symbolName
            )
        }
    }
}
