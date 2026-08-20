import AppKit
import Foundation

/// The app the usage figures come from, and what Little Herd may do about it.
///
/// Usage is the one thing here Little Herd cannot measure for itself: neither
/// vendor writes a limit to disk, so the numbers are read out of CodexBar's
/// files. That makes CodexBar's *state* part of the feature — a limit that
/// stopped updating a day ago is not a limit, and a blank space where a number
/// should be currently means "no limit" and "the source is not running"
/// identically.
///
/// What this does not do is recommend it. The decision recorded on 18 August
/// stands: CodexBar is another developer's application, it is not bundled, and
/// it is not pushed during onboarding. Offering to start it, or naming it as
/// the missing piece, happens at the point where a number is absent and only
/// there — the same rule Full Disk Access already follows in this app.
@MainActor
enum CodexBarSource {
    static let bundleIdentifier = "com.steipete.codexbar"

    /// Taken from CodexBar's own Sparkle feed
    /// (`raw.githubusercontent.com/steipete/CodexBar/main/appcast.xml`) rather
    /// than from anyone's memory, so the link points where the app itself says
    /// it lives.
    static let downloadURL = URL(string: "https://github.com/steipete/CodexBar")!

    /// Whether the application is on this Mac at all.
    ///
    /// Asked of Launch Services rather than of the file system. The usage model
    /// infers this from CodexBar's directories in the home folder, which is
    /// enough to decide whether a *reading* can exist but wrong about the app:
    /// uninstalling leaves those directories behind, so a Mac that has not had
    /// CodexBar for months still looks like it has it.
    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) != nil
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).isEmpty
    }

    /// Starts CodexBar if it is installed and not already running.
    ///
    /// Returns whether anything was started, so a caller can tell "it is now
    /// running because we started it" from "it was already running" — those
    /// look the same a moment later and mean different things.
    @discardableResult
    static func launchIfNeeded() -> Bool {
        guard !isRunning,
              let url = NSWorkspace.shared.urlForApplication(
                  withBundleIdentifier: bundleIdentifier
              )
        else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        // It is a menu-bar app and this is a background errand: bringing it to
        // the front would steal focus from whatever the user is actually doing.
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return true
    }
}

/// What Little Herd should offer about the usage source, given its state.
///
/// Separate from the AppKit above so the decision can be tested without an
/// application to look up.
nonisolated enum CodexBarOffer: Equatable, Sendable {
    /// Nothing to say: the source is running, or the reading is current.
    case none
    /// Installed but not running, so the numbers have stopped moving.
    case start
    /// Not on this Mac. Say what is missing, once, where the number would be.
    case install

    static func resolve(
        availability: AIUsageAvailability,
        isInstalled: Bool,
        isRunning: Bool
    ) -> CodexBarOffer {
        // A current reading needs no offer, whatever the source is doing —
        // including the case where CodexBar has quit since it last wrote, which
        // is not yet a problem and should not be dressed as one.
        if case .available = availability { return .none }
        guard isInstalled else { return .install }
        return isRunning ? .none : .start
    }
}
