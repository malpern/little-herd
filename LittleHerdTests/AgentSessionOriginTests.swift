import Foundation
import Testing

@testable import LittleHerd

@Suite("Where a session lives")
struct AgentSessionOriginTests {
    @Test
    func itReadsTheRegistryLines() {
        let origins = AgentLiveRegistryParser.parse("""
            agent_session=claude\tsomething\telse
            agent_live=abc-123\tinteractive\tclaude-desktop
            agent_live=def-456\tbackground\tcli
            """)
        #expect(origins.count == 2)
        #expect(origins["abc-123"]?.isDesktop == true)
        #expect(origins["def-456"]?.isInteractive == false)
    }

    /// **A label on everything is a label that says nothing.** An interactive
    /// terminal session is the ordinary case and gets none; what is worth
    /// marking is a session somebody else dispatched, or one living in the
    /// desktop app rather than where you are typing.
    @Test
    func onlyTheUnusualCasesAreLabelled() {
        #expect(
            AgentSessionOrigin(kind: "interactive", entrypoint: "cli").label == nil
        )
        #expect(
            AgentSessionOrigin(kind: "interactive", entrypoint: "claude-desktop")
                .label == "Desktop"
        )
        #expect(
            AgentSessionOrigin(kind: "background", entrypoint: "cli")
                .label == "Dispatched"
        )
    }

    /// A registry file missing a field must not drop the session: the probe
    /// substitutes "unknown", and unknown is simply not worth a label.
    @Test
    func aMissingFieldIsNotALostSession() {
        let origins = AgentLiveRegistryParser.parse(
            "agent_live=ghi-789\tunknown\tunknown"
        )
        #expect(origins["ghi-789"] != nil)
        #expect(origins["ghi-789"]?.label == "Dispatched")
    }
}
