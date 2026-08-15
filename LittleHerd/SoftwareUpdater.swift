import Observation
import Sparkle

/// Owns the Sparkle updater for the life of the app.
///
/// Sparkle checks the appcast published alongside each GitHub release and
/// verifies both the EdDSA signature in `SUPublicEDKey` and the Developer ID
/// signature of the downloaded build before installing anything.
///
/// Automatic checking is deliberately not forced on in Info.plist. Sparkle asks
/// once, on an early launch, and honours the answer — which matches the rest of
/// Little Herd, where every recurring network or disk read is something the
/// user opted into.
@MainActor
@Observable
final class SoftwareUpdater {
    /// False while a check or install is already under way, so the menu item
    /// can disable itself instead of quietly doing nothing.
    private(set) var canCheckForUpdates = false

    @ObservationIgnored
    private let controller: SPUStandardUpdaterController

    @ObservationIgnored
    private var availabilityObservation: NSKeyValueObservation?

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        availabilityObservation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.initial, .new]
        ) { [weak self] _, change in
            // Take the value out of the change itself. Sparkle isolates the
            // updater's own properties to the main actor, so the observation
            // closure must not reach back into it.
            guard let isAvailable = change.newValue else { return }
            Task { @MainActor in
                self?.canCheckForUpdates = isAvailable
            }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
