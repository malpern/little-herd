import AppKit
import Observation
import SwiftUI

nonisolated enum DiscoveredMachineReadiness: Equatable, Sendable {
    case ready
    case permissionNeeded
}

nonisolated struct DiscoveredMachine: Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var hostname: String
    let hardwareSummary: String
    let platform: MachinePlatform
    let connection: MachineConnection
    var avatar: HerdwareAvatar
    let readiness: DiscoveredMachineReadiness
    /// Set once the user types in the review sheet. Bonjour re-reports a
    /// service whenever it drops and comes back — a sleeping Mac or a Wi-Fi
    /// blip is enough — and without this the refreshed values would overwrite
    /// whatever they had just entered.
    var isUserEdited = false

    var configuration: MachineConfiguration {
        MachineConfiguration(
            id: MachineID(id),
            name: name,
            shortName: suggestedShortName,
            hostname: hostname,
            hardwareSummary: hardwareSummary,
            platform: platform,
            connection: connection,
            avatar: avatar,
            identityFile: nil,
            serverNames: connection == .smb ? [hostname] : [],
            supportsGPU: platform == .macOS || avatar == .oxGPU
        )
    }

    private var suggestedShortName: String {
        if name.count <= 10 { return name }
        return switch platform {
        case .macOS: "Mac"
        case .linux: "Linux"
        case .storage: "Storage"
        }
    }
}

@MainActor
@Observable
final class AddMachinesModel {
    var machines: [DiscoveredMachine]
    var selectedMachineIDs: Set<DiscoveredMachine.ID>
    private(set) var isSearching = false
    private(set) var configuredDiscoveredCount = 0

    @ObservationIgnored
    private let store: MachineConfigurationStore

    @ObservationIgnored
    private let discovery: BonjourMachineDiscovery

    @ObservationIgnored
    private let onConfigurationsChanged: ([MachineConfiguration]) -> Void

    @ObservationIgnored
    private var discoverySettlementTask: Task<Void, Never>?

    @ObservationIgnored
    private var configuredDiscoveryIDs: Set<DiscoveredMachine.ID> = []

    init(
        store: MachineConfigurationStore,
        machines: [DiscoveredMachine] = [],
        discovery: BonjourMachineDiscovery = BonjourMachineDiscovery(),
        onConfigurationsChanged: @escaping ([MachineConfiguration]) -> Void = { _ in }
    ) {
        self.store = store
        self.discovery = discovery
        self.onConfigurationsChanged = onConfigurationsChanged
        self.machines = machines
        selectedMachineIDs = Set(
            machines.lazy
                .filter { $0.readiness == .ready }
                .map(\.id)
        )
        discovery.onMachineResolved = { [weak self] machine in
            self?.receive(machine)
        }
        discovery.onMachineRemoved = { [weak self] machineID in
            self?.removeDiscoveredMachine(withID: machineID)
        }
        discovery.onSearchingChanged = { [weak self] isSearching in
            self?.isSearching = isSearching
        }
    }

    var selectedReadyMachines: [DiscoveredMachine] {
        machines.filter {
            $0.readiness == .ready && selectedMachineIDs.contains($0.id)
        }
    }

    var selectedReadyCount: Int {
        selectedReadyMachines.count
    }

    var deferredCount: Int {
        machines.count { $0.readiness == .permissionNeeded }
    }

    var deferredMachines: [DiscoveredMachine] {
        machines.filter { $0.readiness == .permissionNeeded }
    }

    func toggleSelection(for machineID: DiscoveredMachine.ID) {
        guard let machine = machines.first(where: { $0.id == machineID }),
              machine.readiness == .ready
        else {
            return
        }

        if selectedMachineIDs.contains(machineID) {
            selectedMachineIDs.remove(machineID)
        } else {
            selectedMachineIDs.insert(machineID)
        }
    }

    func startDiscovery() {
        machines.removeAll()
        selectedMachineIDs.removeAll()
        configuredDiscoveryIDs.removeAll()
        configuredDiscoveredCount = 0
        isSearching = true
        discovery.start()
        discoverySettlementTask?.cancel()
        discoverySettlementTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.isSearching = false
        }
    }

    func stopDiscovery() {
        discoverySettlementTask?.cancel()
        discoverySettlementTask = nil
        discovery.stop()
    }

    func addManualMachine(
        name: String,
        hostname: String,
        kind: ManualMachineKind
    ) {
        let normalizedHostname = hostname.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedHostname.isEmpty else { return }

        let machineID = normalizedHostname.lowercased()
        guard !machines.contains(where: { $0.id == machineID }) else { return }

        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let machine = DiscoveredMachine(
            id: machineID,
            name: normalizedName.isEmpty
                ? Self.suggestedName(from: normalizedHostname)
                : normalizedName,
            hostname: normalizedHostname,
            hardwareSummary: kind.hardwareSummary,
            platform: kind.platform,
            connection: kind.connection,
            avatar: kind.avatar,
            readiness: .ready
        )
        machines.append(machine)
        selectedMachineIDs.insert(machine.id)
    }

    func saveSelectedMachines() {
        let configurations = (selectedReadyMachines + deferredMachines)
            .map(\.configuration)
        store.add(configurations)
        onConfigurationsChanged(store.machines)
    }

    private func receive(_ machine: DiscoveredMachine) {
        if store.contains(hostname: machine.hostname)
            || store.contains(name: machine.name)
        {
            configuredDiscoveryIDs.insert(machine.name.lowercased())
            configuredDiscoveredCount = configuredDiscoveryIDs.count
            return
        }
        if let index = machines.firstIndex(where: { $0.id == machine.id }) {
            if machines[index].connection == .ssh, machine.connection == .smb {
                return
            }
            guard !machines[index].isUserEdited else { return }
            machines[index] = machine
            return
        }
        machines.append(machine)
        if machine.readiness == .ready {
            selectedMachineIDs.insert(machine.id)
        }
    }

    private func removeDiscoveredMachine(withID machineID: DiscoveredMachine.ID) {
        machines.removeAll { $0.id == machineID }
        selectedMachineIDs.remove(machineID)
        configuredDiscoveryIDs.remove(machineID)
        configuredDiscoveredCount = configuredDiscoveryIDs.count
    }

    private static func suggestedName(from hostname: String) -> String {
        let firstComponent = hostname.split(separator: ".").first.map(String.init)
            ?? hostname
        return firstComponent
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}

nonisolated enum ManualMachineKind: String, CaseIterable, Identifiable, Sendable {
    case macLaptop
    case macDesktop
    case linux
    case networkStorage

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .macLaptop: "Mac laptop"
        case .macDesktop: "Mac desktop"
        case .linux: "Linux or GPU box"
        case .networkStorage: "Network storage"
        }
    }

    var avatar: HerdwareAvatar {
        switch self {
        case .macLaptop: .chickLaptop
        case .macDesktop: .calfMini
        case .linux: .oxGPU
        case .networkStorage: .pigletNAS
        }
    }

    var hardwareSummary: String {
        switch self {
        case .macLaptop: "Mac laptop"
        case .macDesktop: "Mac desktop"
        case .linux: "Linux machine"
        case .networkStorage: "Network storage"
        }
    }

    var platform: MachinePlatform {
        switch self {
        case .macLaptop, .macDesktop: .macOS
        case .linux: .linux
        case .networkStorage: .storage
        }
    }

    var connection: MachineConnection {
        self == .networkStorage ? .smb : .ssh
    }
}

struct AddMachinesSceneView: View {
    @State private var model: AddMachinesModel

    init(
        store: MachineConfigurationStore,
        onConfigurationsChanged: @escaping ([MachineConfiguration]) -> Void
    ) {
        _model = State(
            initialValue: AddMachinesModel(
                store: store,
                onConfigurationsChanged: onConfigurationsChanged
            )
        )
    }

    var body: some View {
        AddMachinesView(model: model)
            .onAppear { model.startDiscovery() }
            .onDisappear { model.stopDiscovery() }
    }
}

struct AddMachinesView: View {
    @Bindable var model: AddMachinesModel
    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: AddMachinesSheet?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AddMachinesHeader()
                .padding(.horizontal, 30)
                .padding(.top, 18)
                .padding(.bottom, 10)

            DiscoveredMachinesList(
                machines: model.machines,
                isSearching: model.isSearching,
                configuredDiscoveredCount: model.configuredDiscoveredCount,
                selectedMachineIDs: model.selectedMachineIDs,
                onToggle: model.toggleSelection,
                onReview: { activeSheet = .settings }
            )
            .padding(.horizontal, 30)

            AddMachinesSettingsDisclosure(
                onReview: { activeSheet = .settings }
            )
            .padding(.horizontal, 30)
            .padding(.top, 10)

            Spacer(minLength: 6)

            AddMachinesFooter(
                selectedCount: model.selectedReadyCount,
                deferredCount: model.deferredCount,
                onAddManually: { activeSheet = .manual },
                onAdd: addSelectedMachines
            )
        }
        .frame(width: 728, height: 503)
        .background(LittleHerdTheme.background)
        .environment(\.colorScheme, .light)
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .manual:
                ManualMachineEntryView { name, hostname, kind in
                    model.addManualMachine(
                        name: name,
                        hostname: hostname,
                        kind: kind
                    )
                    activeSheet = nil
                }

            case .settings:
                MachineSettingsReviewView(machines: $model.machines)
            }
        }
    }

    private func addSelectedMachines() {
        model.saveSelectedMachines()
        dismiss()
    }
}

private enum AddMachinesSheet: Hashable, Identifiable {
    case manual
    case settings

    var id: Self { self }
}

private struct AddMachinesHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your herd is ready")
                .font(.title.weight(.bold))

            Text("Little Herd chose sensible defaults for everything it found.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DiscoveredMachinesList: View {
    let machines: [DiscoveredMachine]
    let isSearching: Bool
    let configuredDiscoveredCount: Int
    let selectedMachineIDs: Set<DiscoveredMachine.ID>
    let onToggle: (DiscoveredMachine.ID) -> Void
    let onReview: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text("DISCOVERED MACHINES")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .frame(height: 31)

            Divider()

            if machines.isEmpty {
                DiscoveryStatusView(
                    isSearching: isSearching,
                    configuredDiscoveredCount: configuredDiscoveredCount
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(machines) { machine in
                            DiscoveredMachineRow(
                                name: machine.name,
                                hostname: machine.hostname,
                                hardwareSummary: machine.hardwareSummary,
                                avatar: machine.avatar,
                                readiness: machine.readiness,
                                isSelected: selectedMachineIDs.contains(machine.id),
                                onToggle: { onToggle(machine.id) },
                                onReview: onReview
                            )

                            if machine.id != machines.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
            }
        }
        .frame(height: 303, alignment: .top)
        .background(.white.opacity(0.34))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(LittleHerdTheme.forest.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct DiscoveryStatusView: View {
    let isSearching: Bool
    let configuredDiscoveredCount: Int

    var body: some View {
        VStack(spacing: 10) {
            if isSearching {
                ProgressView()
                    .controlSize(.small)
                Text("Looking for nearby Macs, Linux boxes, and storage…")
                    .font(.callout.weight(.medium))
            } else {
                Image(systemName: "network")
                    .font(.title2)
                    .foregroundStyle(LittleHerdTheme.forest)
                Text(statusTitle)
                    .font(.callout.weight(.medium))
                Text("Already-added machines are hidden. You can also add one by hostname.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var statusTitle: String {
        if configuredDiscoveredCount == 1 {
            return "1 nearby machine is already in your herd"
        }
        if configuredDiscoveredCount > 1 {
            return "\(configuredDiscoveredCount) nearby machines are already in your herd"
        }
        return "No new machines found"
    }
}

private struct DiscoveredMachineRow: View {
    let name: String
    let hostname: String
    let hardwareSummary: String
    let avatar: HerdwareAvatar
    let readiness: DiscoveredMachineReadiness
    let isSelected: Bool
    let onToggle: () -> Void
    let onReview: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Button(action: onToggle) {
                Image(
                    systemName: isSelected
                        ? "checkmark.circle.fill"
                        : "circle"
                )
                .font(.title2)
                .foregroundStyle(selectionColor)
            }
            .buttonStyle(.plain)
            .disabled(readiness == .permissionNeeded)
            .accessibilityLabel(selectionLabel)

            Image(avatar.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                    .lineLimit(1)

                Text(hardwareSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(hostname)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(width: 250, alignment: .leading)

            Spacer(minLength: 8)

            MachineReadinessView(readiness: readiness)
                .frame(width: 170, alignment: .trailing)

            Menu {
                Button("Review Name and Connection", action: onReview)
                Button("Choose Another Avatar…", action: onReview)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More options for \(name)")
        }
        .padding(.horizontal, 13)
        .frame(height: 68)
        .contentShape(Rectangle())
        .onTapGesture {
            if readiness == .ready {
                onToggle()
            }
        }
    }

    private var selectionColor: Color {
        if readiness == .permissionNeeded { return .secondary.opacity(0.45) }
        return isSelected ? LittleHerdTheme.loadGreen : .secondary.opacity(0.5)
    }

    private var selectionLabel: LocalizedStringResource {
        if readiness == .permissionNeeded {
            return "Permission required before this machine can be selected"
        }
        return isSelected ? "Remove machine from selection" : "Add machine to selection"
    }
}

private struct MachineReadinessView: View {
    let readiness: DiscoveredMachineReadiness

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Label(title, systemImage: "circle.fill")
                .font(.callout.weight(.medium))
                .foregroundStyle(tint)
                .labelStyle(ReadinessLabelStyle())

            if readiness == .permissionNeeded {
                Text("Approve network storage access after adding")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var title: LocalizedStringResource {
        switch readiness {
        case .ready: "Ready"
        case .permissionNeeded: "Permission needed"
        }
    }

    private var tint: Color {
        switch readiness {
        case .ready: LittleHerdTheme.loadGreen
        case .permissionNeeded: .orange
        }
    }
}

private struct ReadinessLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 7))
            configuration.title
        }
    }
}

private struct AddMachinesSettingsDisclosure: View {
    let onReview: () -> Void

    var body: some View {
        Button(action: onReview) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)

                Text("Review names and connection settings")
                    .font(.callout.weight(.medium))

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(LittleHerdTheme.forest.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct MachineSettingsReviewView: View {
    @Binding var machines: [DiscoveredMachine]
    @Environment(\.dismiss) private var dismiss

    /// Marks the row as user-owned as it is typed into, so later discovery
    /// updates leave it alone.
    private func edited(
        _ machine: Binding<DiscoveredMachine>,
        _ field: WritableKeyPath<DiscoveredMachine, String>
    ) -> Binding<String> {
        Binding(
            get: { machine.wrappedValue[keyPath: field] },
            set: {
                machine.wrappedValue[keyPath: field] = $0
                machine.wrappedValue.isUserEdited = true
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Names and connections")
                    .font(.title2.weight(.semibold))
                Text("The suggested settings work for most herds.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 9) {
                ForEach($machines) { $machine in
                    HStack(spacing: 10) {
                        Image(machine.avatar.assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)

                        TextField("Name", text: edited($machine, \.name))
                            .textFieldStyle(.roundedBorder)

                        TextField("Hostname", text: edited($machine, \.hostname))
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            HStack {
                Label("Existing SSH keys are used automatically.", systemImage: "key")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(LittleHerdTheme.forest)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 350)
        .background(LittleHerdTheme.background)
        .environment(\.colorScheme, .light)
    }
}

private struct AddMachinesFooter: View {
    let selectedCount: Int
    let deferredCount: Int
    let onAddManually: () -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Button("Add Manually…", action: onAddManually)
                .controlSize(.large)

            Spacer()

            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onAdd) {
                Text(buttonTitle)
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(LittleHerdTheme.forest)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedCount == 0)
        }
        .padding(.horizontal, 30)
        .frame(height: 58)
        .background(.white.opacity(0.24))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var summary: String {
        if deferredCount == 0 {
            return "\(selectedCount) ready now"
        }
        return "\(selectedCount) ready now · \(deferredCount) can finish later"
    }

    private var buttonTitle: String {
        if selectedCount == 1 { return "Add Ready Machine" }
        return "Add \(selectedCount) Ready Machines"
    }
}

private struct ManualMachineEntryView: View {
    let onAdd: (String, String, ManualMachineKind) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var hostname = ""
    @State private var kind: ManualMachineKind = .macDesktop

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add a machine manually")
                    .font(.title2.weight(.semibold))
                Text("Little Herd will use SSH for computers and mounted access for storage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                TextField("Hostname", text: $hostname)
                TextField("Name (optional)", text: $name)
                Picker("Device", selection: $kind) {
                    ForEach(ManualMachineKind.allCases) { machineKind in
                        Text(machineKind.title).tag(machineKind)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Machine") {
                    onAdd(name, hostname, kind)
                }
                .buttonStyle(.borderedProminent)
                .tint(LittleHerdTheme.forest)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 430, height: 310)
        .background(LittleHerdTheme.background)
        .environment(\.colorScheme, .light)
    }
}
