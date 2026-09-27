import Foundation
import UIKit
import UserNotifications

/// Turns what the watcher reports into notifications on this phone.
///
/// **Two routes to one notification.** When the watcher has an APNs key, it
/// pushes each critical alert the moment it raises it, and that reaches the
/// phone asleep in a pocket. Whether or not it does, every read of the herd —
/// in the foreground, or when iOS wakes the app for a background refresh —
/// compares the watcher's current alerts with the ones already told, and says
/// the new ones itself. Both use the alert's episode id as the notification's
/// identifier (`apns-collapse-id` on the push), so when both arrive the second
/// replaces the first rather than buzzing twice.
///
/// Also says when a move finishes, landed or not — the phone started it, so
/// the phone is where the answer is wanted — and keeps the app's badge at the
/// number of sessions waiting on you.
@MainActor
final class HerdNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = HerdNotifier()

    /// Called with a machine id when a notification about it is opened.
    var onOpenMachine: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private static let toldAlertsKey = "herdToldAlerts"
    private static let toldTransfersKey = "herdToldTransfers"

    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    override private init() {
        super.init()
        center.delegate = self
    }

    /// Asks once, after the herd has first been read — a permission prompt
    /// on a blank screen is a prompt with no reason attached.
    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        if settings.authorizationStatus == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            authorization = granted ? .authorized : .denied
        }
        if authorization == .authorized || authorization == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Compares a fresh reading with what has already been said.
    func observe(_ snapshot: HerdWire.Snapshot) {
        let waiting = snapshot.machines.flatMap(\.sessions).filter(\.needsYou).count
        center.setBadgeCount(waiting)

        let current = snapshot.alerts ?? []
        let told = Set(defaults.stringArray(forKey: Self.toldAlertsKey) ?? [])
        for alert in current where !told.contains(alert.id) {
            post(id: alert.id, title: alert.title, body: alert.body, machine: alert.machine)
        }
        // An episode that has ended leaves the list; its notification leaves
        // the lock screen with it, since what it says is no longer true.
        let ended = told.subtracting(current.map(\.id))
        if !ended.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: Array(ended))
        }
        defaults.set(current.map(\.id), forKey: Self.toldAlertsKey)

        let finished = (snapshot.transfers ?? []).filter { $0.phase == "landed" || $0.phase == "failed" }
        let toldTransfers = Set(defaults.stringArray(forKey: Self.toldTransfersKey) ?? [])
        for transfer in finished where !toldTransfers.contains(transfer.id) {
            let to = snapshot.machines.first { $0.id == transfer.destination }?.shortName ?? transfer.destination
            post(
                id: "transfer:\(transfer.id)",
                title: transfer.phase == "landed"
                    ? "“\(transfer.title)” landed on \(to)"
                    : "“\(transfer.title)” didn’t land on \(to)",
                body: transfer.detail ?? "",
                machine: transfer.destination
            )
        }
        // Remember only what the watcher still reports, so the list cannot
        // grow without end.
        defaults.set(finished.map(\.id), forKey: Self.toldTransfersKey)
    }

    private func post(id: String, title: String, body: String, machine: String) {
        guard authorization == .authorized || authorization == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        if !body.isEmpty { content.body = body }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["machine": machine]
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Shown even with the app open: the herd screen may be on a different
    /// lens from the machine in trouble.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let machine = response.notification.request.content.userInfo["machine"] as? String
            ?? Self.machine(fromCollapseID: response.notification.request.identifier)
        guard let machine else { return }
        await MainActor.run { onOpenMachine?(machine) }
    }

    /// A pushed alert carries no userInfo of our own; its identifier is the
    /// episode id, `machine:kind`.
    nonisolated static func machine(fromCollapseID id: String) -> String? {
        let parts = id.split(separator: ":", maxSplits: 1)
        return parts.count == 2 && parts[0] != "transfer" ? String(parts[0]) : nil
    }
}

/// Where iOS hands over the push token.
final class HerdAppDelegate: NSObject, UIApplicationDelegate {
    /// Set by the app once the client exists.
    @MainActor static var onToken: ((String) -> Void)?

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in HerdAppDelegate.onToken?(token) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // The simulator and an unprovisioned build land here. Nothing to do:
        // the phone still raises alerts itself whenever it reads the herd.
    }
}

/// Which APNs environment this build's entitlement names. Debug builds signed
/// for development get sandbox tokens; the watcher must send to the matching
/// host or Apple answers `BadDeviceToken`.
enum PushEnvironment {
    static var current: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }
}
