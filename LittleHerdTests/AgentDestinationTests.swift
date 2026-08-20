import Foundation
import Testing
@testable import LittleHerd

/// Whether a machine could host a session, measured rather than assumed.
struct AgentDestinationTests {
    private func line(_ provider: String, _ version: String, _ path: String) -> String {
        let v = Data(version.utf8).base64EncodedString()
        let p = Data(path.utf8).base64EncodedString()
        return "agent_install=\(provider)\t\(v)\t\(p)"
    }

    /// The lines the linux box produced, after the shim's banner was stripped.
    @Test
    func theLinesTheLinuxBoxProducedAreRead() throws {
        let installs = AgentInstallOutputParser.parse(
            [
                line("claude", "2.1.234", "/home/malpern/.local/bin/claude"),
                line("codex", "0.147.0", "/home/malpern/.local/bin/codex"),
            ].joined(separator: "\n")
        )
        #expect(installs.count == 2)
        let claude = try #require(installs.first { $0.provider == .claude })
        #expect(claude.version == "2.1.234")
        #expect(claude.path == "/home/malpern/.local/bin/claude")
    }

    /// The mini carries two copies of Claude — 2.1.234 in ~/.local/bin and
    /// 2.1.221 inside an application bundle. The newer is the one to report.
    @Test
    func theNewestCopyOnAMachineWins() throws {
        let installs = AgentInstallOutputParser.parse(
            [
                line("claude", "2.1.221", "/Users/clawd/Library/…/claude"),
                line("claude", "2.1.234", "/Users/clawd/.local/bin/claude"),
            ].joined(separator: "\n")
        )
        #expect(installs.count == 1)
        #expect(try #require(installs.first).version == "2.1.234")
    }

    /// Compared as numbers. As strings "2.1.9" sorts above "2.1.221", and that
    /// is the exact pair the mini has.
    @Test
    func versionsAreComparedAsNumbersNotText() {
        #expect(AgentInstallOutputParser.isNewer("2.1.234", than: "2.1.221"))
        #expect(!AgentInstallOutputParser.isNewer("2.1.9", than: "2.1.221"))
        #expect(AgentInstallOutputParser.isNewer("2.2.0", than: "2.1.999"))
        #expect(!AgentInstallOutputParser.isNewer("2.1.0", than: "2.1.0"))
        // Codex numbers its pre-releases; the numeric parts still order.
        #expect(
            AgentInstallOutputParser.isNewer(
                "0.148.0-alpha.15",
                than: "0.148.0-alpha.9"
            )
        )
    }

    /// A machine you have said no to reads as excluded, not as a list of what
    /// it lacks. Both may be true; only one is the reason, and the other would
    /// invite someone to fix a machine they had already decided about.
    @Test
    func intentIsReportedBeforeCapability() {
        #expect(
            DestinationEligibility.resolve(
                installations: [],
                hasGit: false,
                isAllowed: false,
                hasReported: true
            ) == .excluded
        )
    }

    /// Each missing piece is named, because they have different fixes — the
    /// same reason RemoteUnavailability distinguishes a name that will not
    /// resolve from a key that was refused.
    @Test
    func eachMissingPieceIsNamedSeparately() {
        #expect(
            DestinationEligibility.resolve(
                installations: [],
                hasGit: true,
                isAllowed: true,
                hasReported: true
            ) == .noAgent
        )
        #expect(
            DestinationEligibility.resolve(
                installations: [
                    AgentInstallation(provider: .claude, version: "2.1.234", path: "/x"),
                ],
                hasGit: false,
                isAllowed: true,
                hasReported: true
            ) == .noGit
        )
    }

    /// Never asked is not the same as answered no. A machine that has not
    /// reported yet must not read as ineligible.
    @Test
    func anUnmeasuredMachineIsNotCalledIneligible() {
        let eligibility = DestinationEligibility.resolve(
            installations: [],
            hasGit: false,
            isAllowed: true,
            hasReported: false
        )
        #expect(eligibility == .unknown)
        #expect(!eligibility.isEligible)
        #expect(eligibility.detail == "Not measured yet.")
    }

    @Test
    func acapableAllowedMachineNamesWhatItWouldRun() throws {
        let eligibility = DestinationEligibility.resolve(
            installations: [
                AgentInstallation(provider: .claude, version: "2.1.234", path: "/x"),
            ],
            hasGit: true,
            isAllowed: true,
            hasReported: true
        )
        #expect(eligibility.isEligible)
        #expect(eligibility.detail.contains("2.1.234"))
    }
}
