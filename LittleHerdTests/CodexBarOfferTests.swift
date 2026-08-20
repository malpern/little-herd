import Foundation
import Testing
@testable import LittleHerd

/// What Little Herd offers about the app its usage figures come from.
///
/// The rule this encodes is narrow on purpose. Little Herd reads CodexBar and
/// does not recommend it, so it may only name it where a number is missing
/// *because of the source* — not as advice, not during onboarding, and never
/// when the figure is fine.
struct CodexBarOfferTests {
    private let recent = AIUsageLimit(
        provider: .codex,
        remainingPercent: 38,
        windowMinutes: 10_080,
        resetsAt: nil,
        updatedAt: .now
    )

    /// A working reading is never an occasion to talk about tooling — even if
    /// CodexBar has quit since it wrote, which is not yet a problem.
    @Test
    func aCurrentReadingOffersNothing() {
        #expect(
            CodexBarOffer.resolve(
                availability: .available(recent),
                isInstalled: true,
                isRunning: false
            ) == .none
        )
    }

    /// The case this exists for: installed, stopped, so the figure silently
    /// stopped moving. Starting it is the fix, and it is one click.
    @Test
    func aStoppedSourceIsOfferedAStart() {
        #expect(
            CodexBarOffer.resolve(
                availability: .stale(since: .now.addingTimeInterval(-86_400)),
                isInstalled: true,
                isRunning: false
            ) == .start
        )
        #expect(
            CodexBarOffer.resolve(
                availability: .noReading,
                isInstalled: true,
                isRunning: false
            ) == .start
        )
    }

    /// Running but with nothing to say is CodexBar's business, not ours: there
    /// is no button that fixes it, so offering one would be theatre.
    @Test
    func aRunningSourceWithNoReadingIsNotOfferedAStart() {
        #expect(
            CodexBarOffer.resolve(
                availability: .noReading,
                isInstalled: true,
                isRunning: true
            ) == .none
        )
    }

    /// Absent entirely: say what is missing, once, where the number would be.
    @Test
    func anAbsentSourceIsNamedRatherThanLeftBlank() {
        #expect(
            CodexBarOffer.resolve(
                availability: .sourceMissing,
                isInstalled: false,
                isRunning: false
            ) == .install
        )
        // Not installed beats every other reading, including a stale one left
        // behind by an uninstall — the directories outlive the app.
        #expect(
            CodexBarOffer.resolve(
                availability: .stale(since: .now),
                isInstalled: false,
                isRunning: false
            ) == .install
        )
    }

    /// The link is the app's own home, taken from the Sparkle feed it ships
    /// with rather than from anyone's memory.
    @Test
    func theInstallLinkPointsAtTheProject() {
        #expect(CodexBarSource.downloadURL.host() == "github.com")
        #expect(CodexBarSource.downloadURL.path().contains("CodexBar"))
        #expect(CodexBarSource.bundleIdentifier == "com.steipete.codexbar")
    }
}
