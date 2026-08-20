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
            DashboardView(
                model: model,
                machineStore: machineStore,
                onConfigurationsChanged: model.applyConfigurations
            )
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
    /// Whether Little Herd starts CodexBar when it finds it installed and not
    /// running. Default on, because the alternative is a usage figure that
    /// silently stops moving — but a setting rather than a habit, since this
    /// starts another developer's application on someone's Mac.
    static let startsUsageSourceKey = "startsUsageSource"
    /// Context sizes seen just before a compaction, by model. Learned from
    /// this Mac rather than shipped as a table — see `AgentCompactionThresholds`.
    ///
    /// The stored string keeps its old spelling deliberately. Renaming the
    /// Swift constant costs nothing; renaming the key would throw away every
    /// threshold already measured on this Mac and leave the panel silent again
    /// until each model was watched compacting a second time.
    static let observedCompactionThresholdsKey = "observedContextLimitsV1"
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
            storageHealth: storageConcern?.health,
            sustainedCPUPercent: SustainedLoad.average(
                of: cpu.history,
                endingAt: lastUpdated ?? .now
            )
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
                .fill(machine.status.tint)
                .frame(width: 6, height: 6)
                .accessibilityLabel(machine.status.label)

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
                Text(machine.status.label)
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
    @AppStorage(LittleHerdPreferences.startsUsageSourceKey)
    private var startsUsageSource = true
    @State private var configuringNAS: MachineConfiguration?
    /// Bumped when a password is saved.
    ///
    /// The row reads the keychain while drawing, and the keychain is not
    /// something SwiftUI observes. Saving a password for a machine that is
    /// already configured changes no stored value, so nothing invalidated the
    /// view and the row went on showing "Sign in again" after a sign-in that
    /// had in fact succeeded.
    @State private var credentialsRevision = 0

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
                Toggle("Start CodexBar if it isn’t running", isOn: $startsUsageSource)
                    .font(.body.weight(.medium))

                Text("Usage figures come from CodexBar, because neither vendor writes a limit anywhere Little Herd can read. When CodexBar isn’t running the figure quietly stops moving, which looks the same as having no limit at all.")
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
                    Text("\(machineStore.machines.count) saved. Drag to reorder; this is the order they appear in everywhere.")
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

            // A List rather than a VStack, because it is what gives rows drag
            // reordering for free. Styled back down to the plain grouped look
            // the rest of this window uses.
            List {
                ForEach(machineStore.machines) { machine in
                    SettingsMachineRow(
                        machine: machine,
                        canRemove: machineStore.canRemove(machine.id),
                        // Nothing to reorder in a herd of one, and an affordance
                        // offering a move that cannot happen is worse than none.
                        isReorderable: machineStore.machines.count > 1,
                        position: position(of: machine.id),
                        onRemove: { remove(machine.id) },
                        onConnect: { configuringNAS = machine },
                        onMove: { move(machine.id, by: $0) },
                        credentialsRevision: credentialsRevision
                    )
                    .listRowInsets(
                        EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
                    )
                    .listRowSeparator(.visible)
                    .listRowBackground(Color.clear)
                }
                .onMove { source, destination in
                    machineStore.move(fromOffsets: source, toOffset: destination)
                    onConfigurationsChanged(machineStore.machines)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: CGFloat(machineStore.machines.count) * 38 + 4)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(24)
        .frame(width: 420)
        .sheet(item: $configuringNAS) { machine in
            SynologyCredentialsView(machine: machine) { updated in
                machineStore.update(updated)
                onConfigurationsChanged(machineStore.machines)
                credentialsRevision += 1
            }
        }
    }

    private func remove(_ machineID: MachineID) {
        machineStore.remove(machineID)
        onConfigurationsChanged(machineStore.machines)
    }

    private func position(of machineID: MachineID) -> ListPosition {
        guard let index = machineStore.machines
            .firstIndex(where: { $0.id == machineID })
        else {
            return ListPosition(index: 0, count: machineStore.machines.count)
        }
        return ListPosition(index: index, count: machineStore.machines.count)
    }

    /// The same reordering the drag performs, reachable without a mouse.
    ///
    /// Dragging is the only way this list could be reordered, which quietly
    /// excluded anyone driving the app from the keyboard — and anyone who simply
    /// found a four-row drag fiddly.
    private func move(_ machineID: MachineID, by offset: Int) {
        guard let index = machineStore.machines
            .firstIndex(where: { $0.id == machineID }),
            let destination = ListPosition(
                index: index,
                count: machineStore.machines.count
            ).destination(movingBy: offset)
        else { return }

        machineStore.move(
            fromOffsets: IndexSet(integer: index),
            toOffset: destination
        )
        onConfigurationsChanged(machineStore.machines)
    }
}

/// The pointer half of "you can move this".
///
/// A `List` hands over reordering without ever mentioning it: the rows look
/// inert, the pointer stays an arrow, and the only hint is a sentence above the
/// list. An open hand on approach and a closed one once you have hold is the
/// oldest convention macOS has for direct manipulation.
///
/// The press is watched through a local event monitor rather than a
/// `DragGesture`, deliberately. The drag itself belongs to AppKit's table view,
/// and a SwiftUI gesture layered on top is liable to swallow the very drag it is
/// decorating — a monitor sees the click without consuming it.
///
/// Cursors are `set()` rather than pushed. The push/pop stack has to be balanced
/// across every way a view can lose the pointer — disappearing mid-hover, the
/// window resigning key, the row moving out from under the mouse as the list
/// reorders — and an unbalanced stack leaves the whole app wearing a hand
/// cursor.
private struct Grabbable: ViewModifier {
    let isEnabled: Bool

    @State private var isHovering = false
    @State private var isHolding = false
    @State private var pressMonitor: Any?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering && isEnabled
                if isHovering {
                    startWatchingForPress()
                } else {
                    stopWatchingForPress()
                    isHolding = false
                }
                applyCursor()
            }
            .onChange(of: isEnabled) { _, enabled in
                guard !enabled else { return }
                isHovering = false
                releasePointer()
            }
            .onDisappear { releasePointer() }
    }

    private func applyCursor() {
        guard isHovering else { return NSCursor.arrow.set() }
        (isHolding ? NSCursor.closedHand : NSCursor.openHand).set()
    }

    private func releasePointer() {
        stopWatchingForPress()
        isHolding = false
        NSCursor.arrow.set()
    }

    private func startWatchingForPress() {
        guard pressMonitor == nil else { return }
        pressMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp]
        ) { event in
            isHolding = event.type == .leftMouseDown
            applyCursor()
            // Handed straight back: the drag depends on this event arriving.
            return event
        }
    }

    private func stopWatchingForPress() {
        guard let pressMonitor else { return }
        NSEvent.removeMonitor(pressMonitor)
        self.pressMonitor = nil
    }
}

extension View {
    func grabbable(_ isEnabled: Bool = true) -> some View {
        modifier(Grabbable(isEnabled: isEnabled))
    }
}

/// The visible half: something to aim at.
///
/// Reserved rather than revealed — the space is always there and only the glyph
/// fades in, because a grip that appears on hover and pushes the row sideways
/// moves the thing you were reaching for.
private struct DragGrip: View {
    let isVisible: Bool

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 11)
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(true)
    }
}

private struct SettingsMachineRow: View {
    let machine: MachineConfiguration
    let canRemove: Bool
    let isReorderable: Bool
    let position: ListPosition
    let onRemove: () -> Void
    let onConnect: () -> Void
    let onMove: (Int) -> Void
    /// Read so that saving a password redraws this row. The keychain is not
    /// observable, so without it the label can outlive the thing it describes.
    let credentialsRevision: Int

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// What the row can honestly claim.
    ///
    /// This said "Connected" whenever the machine was configured for DSM, which
    /// describes the setting rather than the situation: after the saved password
    /// is removed — or when it was written by a different build and can no
    /// longer be read — the row went on claiming a connection that no longer
    /// existed. The keychain check cannot raise a dialog, so asking is free.
    private enum SignInState {
        case notSignedIn
        case signedIn(account: String)
        case passwordMissing(account: String)

        var label: String {
            switch self {
            case .notSignedIn: "Connect…"
            case .signedIn: "Signed in"
            case .passwordMissing: "Sign in again"
            }
        }

        var needsAttention: Bool {
            if case .passwordMissing = self { return true }
            return false
        }

        var help: String {
            switch self {
            case .notSignedIn:
                "Sign in to DSM to read capacity and drive health without a mounted share"
            case .signedIn(let account):
                "Signed in to DSM as \(account). Click to change."
            case .passwordMissing(let account):
                // Not "no saved password": the commoner cause is a password
                // that is saved and unreadable by this build, and telling
                // someone it is missing sends them looking for the wrong thing.
                "Little Herd can’t read a saved password for \(account) — enter it again to resume monitoring."
            }
        }
    }

    private var signInState: SignInState {
        guard let endpoint = machine.dsmEndpoint else { return .notSignedIn }
        return KeychainSecret.exists(
            account: KeychainSecret.account(for: endpoint)
        )
            ? .signedIn(account: endpoint.username)
            : .passwordMissing(account: endpoint.username)
    }

    var body: some View {
        HStack(spacing: 9) {
            // Everything up to the controls is the grab area. It carries the
            // pointer, so the whole of a row's identity reads as the handle —
            // the controls past it set their own pointer, and an open hand over
            // a button invites the wrong gesture entirely.
            HStack(spacing: 9) {
                DragGrip(isVisible: isReorderable && isHovering)

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
            }
            .contentShape(Rectangle())
            .grabbable(isReorderable)
            .onHover { isHovering = $0 }

            // Only a NAS has anything to sign in to. Storage machines start out
            // reading a mounted share; connecting to DSM is what gets them drive
            // health and measurements that do not depend on the Finder.
            if machine.isStorage {
                Button(signInState.label) { onConnect() }
                    .buttonStyle(.link)
                    .font(.caption)
                    .foregroundStyle(signInState.needsAttention ? .orange : .accentColor)
                    .help(signInState.help)
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
        // A row that lights up under the pointer is the other half of saying it
        // can be picked up, and it is what makes the drop target legible once
        // one is moving.
        .background {
            RoundedRectangle(cornerRadius: 5)
                .fill(.quaternary.opacity(isHovering && isReorderable ? 0.55 : 0))
                .padding(.horizontal, -4)
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: isHovering
        )
        .contextMenu {
            Button("Move Up") { onMove(-1) }
                .disabled(!position.canMoveUp)
            Button("Move Down") { onMove(1) }
                .disabled(!position.canMoveDown)
        }
        // Read as one element, so VoiceOver says which machine and where it sits
        // rather than walking the avatar and the hostname separately.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(machine.name), \(machine.hostname)")
        .accessibilityValue(position.description)
        .accessibilityActions {
            if position.canMoveUp {
                Button("Move Up") { onMove(-1) }
            }
            if position.canMoveDown {
                Button("Move Down") { onMove(1) }
            }
        }
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
