import Foundation
import Observation
import UserNotifications

/// What Little Herd will interrupt you for.
///
/// Deliberately short: a monitor that cries wolf gets muted, and a muted
/// monitor is worse than none. These are the conditions where the machine is
/// already in trouble rather than merely busy — a full disk stops work, a
/// machine that stopped answering may not come back on its own.
nonisolated enum MachineAlert: String, CaseIterable, Sendable {
    case diskFull
    case memoryCritical
    case unreachable
    /// A drive or volume the machine itself considers damaged. The one condition
    /// here that is about hardware rather than load: a full disk is recoverable,
    /// a dying drive takes the data with it.
    case storageUnhealthy

    func title(machine: String) -> String {
        switch self {
        case .diskFull: "\(machine) is almost out of space"
        case .memoryCritical: "\(machine) is under memory pressure"
        case .unreachable: "\(machine) stopped responding"
        case .storageUnhealthy: "\(machine) storage needs attention"
        }
    }

    func recoveryTitle(machine: String) -> String {
        switch self {
        case .diskFull: "\(machine) has space again"
        case .memoryCritical: "\(machine) memory recovered"
        case .unreachable: "\(machine) is back"
        case .storageUnhealthy: "\(machine) storage reports healthy again"
        }
    }

    /// Conditions currently true for a machine.
    @MainActor
    static func active(for machine: MachineMonitorModel) -> Set<MachineAlert> {
        var alerts: Set<MachineAlert> = []

        // Only a machine that was reachable and stopped counts. A machine that
        // has never connected, or one you paused, is not news.
        if machine.state == .offline, machine.lastUpdated != nil {
            alerts.insert(.unreachable)
            // Everything else is last-known data, so do not raise alarms about
            // numbers that have stopped updating.
            return alerts
        }

        guard machine.state == .live else { return [] }

        if machine.storageVolumes.contains(where: { $0.usedPercent >= 95 }) {
            alerts.insert(.diskFull)
        }
        if machine.memoryPressure == .critical {
            alerts.insert(.memoryCritical)
        }
        // `.unknown` is not trouble — plenty of drives report no SMART status at
        // all, and treating silence as failure is how a monitor gets muted.
        // Volumes count as well as drives: a pool can be degraded while every
        // individual drive still reads normal.
        let damaged: (SynologyHealth?) -> Bool = {
            $0 == .warning || $0 == .critical
        }
        if machine.drives.contains(where: { damaged($0.health) })
            || machine.storageVolumes.contains(where: { damaged($0.health) }) {
            alerts.insert(.storageUnhealthy)
        }
        return alerts
    }
}

/// Raises a notification when a machine crosses into trouble, and one when it
/// comes back.
///
/// State is per machine and per condition, so a disk sitting at 96% for a week
/// produces exactly one notification, not one every ten seconds.
@MainActor
@Observable
final class MachineAlertCenter {
    @ObservationIgnored
    private var raised: [MachineID: Set<MachineAlert>] = [:]

    @ObservationIgnored
    private var hasRequestedAuthorization = false

    @ObservationIgnored
    private let notify: @MainActor (String, String) -> Void

    init(notify: (@MainActor (String, String) -> Void)? = nil) {
        self.notify = notify ?? MachineAlertCenter.deliver
    }

    func evaluate(_ machine: MachineMonitorModel, isEnabled: Bool) {
        let current = MachineAlert.active(for: machine)
        let previous = raised[machine.machine] ?? []
        guard current != previous else { return }
        raised[machine.machine] = current

        guard isEnabled else { return }
        requestAuthorizationIfNeeded()

        for alert in current.subtracting(previous) {
            notify(alert.title(machine: machine.name), body(for: alert, machine))
        }
        for alert in previous.subtracting(current) {
            notify(alert.recoveryTitle(machine: machine.name), "")
        }
    }

    /// Forgets everything, so reconfiguring machines does not fire recoveries
    /// for machines that simply went away.
    func reset() {
        raised.removeAll()
    }

    private func body(
        for alert: MachineAlert,
        _ machine: MachineMonitorModel
    ) -> String {
        switch alert {
        case .diskFull:
            guard let volume = machine.storageVolumes
                .max(by: { $0.usedPercent < $1.usedPercent })
            else {
                return ""
            }
            let free = Int64(volume.availableBytes)
                .formatted(.byteCount(style: .file))
            return "\(volume.name) is \(Int(volume.usedPercent))% full — \(free) left."
        case .memoryCritical:
            return machine.memoryConsumers.first.map {
                "Largest: \($0.name), \(Int64($0.residentBytes).formatted(.byteCount(style: .memory)))."
            } ?? ""
        case .unreachable:
            guard let reason = machine.unavailability else { return "" }
            return String(localized: reason.detail(host: machine.hostname))
        case .storageUnhealthy:
            // Names the drive, because the next step is opening the bay and
            // pulling the right one.
            let hurt = machine.drives.filter {
                $0.health == .warning || $0.health == .critical
            }
            if let worst = hurt.first(where: { $0.health == .critical })
                ?? hurt.first {
                let others = hurt.count > 1
                    ? " (\(hurt.count) drives affected)"
                    : ""
                let model = worst.model.isEmpty ? "" : " \(worst.model)"
                let sectors = worst.uncorrectableSectors > 0
                    ? ", \(worst.uncorrectableSectors) bad sectors"
                    : ""
                return "\(worst.name)\(model) reports \(worst.health.label.lowercased())\(sectors)\(others)."
            }
            // No individual drive is condemned, so the trouble is at the volume
            // or pool level — say that rather than saying nothing.
            guard let volume = machine.storageVolumes.first(where: {
                $0.health == .warning || $0.health == .critical
            }) else {
                return ""
            }
            return "\(volume.name) reports \(volume.health?.label.lowercased() ?? "trouble")."
        }
    }

    private func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func deliver(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        if !body.isEmpty { content.body = body }
        content.sound = .default

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
        )
    }
}
