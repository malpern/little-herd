import Foundation
import Testing

@testable import LittleHerd

@Suite("Transfer eligibility")
struct TransferEligibilityTests {
    private func session(_ state: AgentSessionState) -> AgentSession {
        AgentSession(
            id: "s1",
            provider: .claude,
            projectName: "little-herd",
            state: state,
            updatedAt: Date(),
            progress: nil
        )
    }

    /// The good case: it ended its turn and is holding for a person, so
    /// nothing is in flight and it can be asked where it got to.
    @Test
    func awaitingSessionIsReady() {
        #expect(
            TransferEligibility.verdict(
                for: session(.waiting),
                hasRepository: true
            ) == .ready
        )
    }

    /// **A session mid-turn is waited for, not refused.** Interrupting can
    /// leave a half-written file or a git operation part-done, and it will be
    /// movable in a minute — refusing it would be turning down work that is
    /// about to be fine.
    @Test
    func anactiveSessionIsWaitedFor() {
        #expect(
            TransferEligibility.verdict(
                for: session(.active),
                hasRepository: true
            ) == .afterItFinishes
        )
    }

    /// **A stalled session is the one to refuse loudly.** It stopped inside a
    /// tool call, so it cannot be asked where it got to — any brief would be
    /// assembled from outside and presented as its own account of itself — and
    /// its working tree may be half-written by whatever was interrupted.
    @Test
    func astalledSessionIsRefusedRatherThanGuessedAt() {
        let verdict = TransferEligibility.verdict(
            for: session(.stalled),
            hasRepository: true
        )
        #expect(verdict == .refused(.cannotBeAsked))
        #expect(
            TransferEligibility.explanation(for: .cannotBeAsked)
                .contains("stopped part-way")
        )
    }

    /// Nothing in flight is not a transfer, however willing the destination.
    @Test
    func afinishedSessionHasNothingToSend() {
        #expect(
            TransferEligibility.verdict(
                for: session(.completed),
                hasRepository: true
            ) == .refused(.nothingInFlight)
        )
    }

    /// The repository is how work travels, and it is checked before the state
    /// — a stalled session outside a repository has two problems and the
    /// useful thing to say is the one a person can act on.
    @Test
    func noRepositoryMeansNoBranchToSendItOn() {
        for state in [
            AgentSessionState.waiting, .active, .completed, .stalled,
        ] {
            #expect(
                TransferEligibility.verdict(
                    for: session(state),
                    hasRepository: false
                ) == .refused(.noRepository)
            )
        }
    }
}
