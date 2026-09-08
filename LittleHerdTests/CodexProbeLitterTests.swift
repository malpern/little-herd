import Foundation
import Testing

@testable import LittleHerd

/// Hiding the app's own sign-in probes, for both providers.
///
/// The probe asks a machine whether its agent can sign in. That conversation is the
/// app's, not the person's, and counting it as work was measured on 3 September at
/// **9 of 21 Claude sessions** — nearly half the herd was Little Herd talking to
/// itself. Claude's probe is pinned to one id and recognised by it; Codex has no
/// `--session-id`, so the only handle it leaves is the sentence it sends.
@Suite("Sign-in probes are not work")
struct CodexProbeLitterTests {
    private func session(
        _ id: String, provider: AgentTaskProvider, title: String?
    ) -> AgentSession {
        AgentSession(
            id: id, provider: provider, projectName: "p", state: .completed,
            updatedAt: .now, progress: nil, title: title, workingDirectory: "/x"
        )
    }

    /// **The real title, from this Mac's own Codex database.** Codex names a thread
    /// after its first message, and the probe's first message is only ever this.
    @Test
    func acodexProbeIsRecognisedByItsTitle() {
        #expect(AgentAuthProbe.isProbe(
            sessionID: "01a03b69-4e43-7bb1-9463-53787a68993a",
            title: "Reply with exactly: AUTH_OK"))
    }

    /// Claude's, still by its pinned id, whatever its title says.
    @Test
    func aclaudeProbeIsStillRecognisedByItsIdentifier() {
        #expect(AgentAuthProbe.isProbe(
            sessionID: "claude:\(AgentAuthProbe.sessionIdentifier)", title: nil))
        #expect(AgentAuthProbe.isProbe(sessionID: AgentAuthProbe.sessionIdentifier, title: "anything"))
    }

    /// **Real work is not hidden**, which is the failure that would matter more: a
    /// session missing from the herd is worse than a probe showing in it.
    @Test
    func ordinaryWorkIsLeftAlone() {
        for title in ["Daily brief", "Sandpiper weekly security status",
                      "Check Apple notarization support reply", "Little Herder"] {
            #expect(!AgentAuthProbe.isProbe(sessionID: "01a07c7e-1111", title: title),
                    "“\(title)” was hidden")
        }
        #expect(!AgentAuthProbe.isProbe(sessionID: "01a07c7e-1111", title: nil))
        #expect(!AgentAuthProbe.isProbe(sessionID: "01a07c7e-1111", title: ""))
    }

    /// The snapshot is where the filtering has to happen, because the dashboard and the
    /// command line read it by different routes and only one of them would have
    /// remembered to filter.
    @Test
    func thesnapshotHidesBothAndKeepsTheRest() {
        let snapshot = SystemSnapshot(
            timestamp: .now,
            readings: [:],
            agentSessions: [
                session("claude:\(AgentAuthProbe.sessionIdentifier)", provider: .claude, title: nil),
                session("01a03b69", provider: .codex, title: "Reply with exactly: AUTH_OK"),
                session("01a07c7e", provider: .codex, title: "Daily brief"),
            ]
        )
        #expect(snapshot.agentSessions.count == 1)
        #expect(snapshot.agentSessions.first?.title == "Daily brief")
    }
}
