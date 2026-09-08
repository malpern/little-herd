import Foundation
import Testing

@testable import LittleHerd

/// `little-herd agents` — the herd-level question the dashboard gave up.
@Suite("Agents across the herd")
struct HerdCommandAgentsTests {
    private func install(_ p: AgentTaskProvider, _ v: String) -> AgentInstallation {
        AgentInstallation(provider: p, version: v, path: "/x/\(p.rawValue)")
    }
    private func row(_ name: String, _ i: [AgentInstallation]?, storage: Bool = false)
        -> HerdCommand.AgentRow
    {
        HerdCommand.AgentRow(machine: name, installations: i, couldCarryAnAgent: !storage)
    }

    /// **The real herd on 7 September**, which is what settled whether this was worth
    /// building: every machine on a different build of both agents.
    @Test
    func itnamesEveryVersionAndWhoHasIt() {
        let text = HerdCommand.agents([
            row("Air", [install(.claude, "2.1.260"), install(.codex, "0.153.4")]),
            row("Mac mini", [install(.claude, "2.1.255"), install(.codex, "0.153.0-alpha.5")]),
            row("Linux", [install(.claude, "2.1.258"), install(.codex, "0.152.1")]),
        ], json: false)
        #expect(text.contains("Air"))
        #expect(text.contains("2.1.260"))
        #expect(text.contains("is on 3 versions"))
    }

    /// **Newest first, compared numerically.** A plain string sort puts 2.1.9 above
    /// 2.1.260, which would report the herd's newest machine as its oldest — the exact
    /// opposite of the answer this verb exists to give.
    @Test
    func versionsAreOrderedNewestFirstAndNumerically() {
        let drift = HerdCommand.drift(in: [
            row("A", [install(.claude, "2.1.9")]),
            row("B", [install(.claude, "2.1.260")]),
            row("C", [install(.claude, "2.1.58")]),
        ])
        #expect(drift.count == 1)
        #expect(drift.first?.versions.map(\.version) == ["2.1.260", "2.1.58", "2.1.9"])
    }

    /// Agreement is not drift, and reporting it as such would make the summary noise.
    @Test
    func aherdThatAgreesReportsNoDrift() {
        let rows = [row("A", [install(.claude, "2.1.260")]), row("B", [install(.claude, "2.1.260")])]
        #expect(HerdCommand.drift(in: rows).isEmpty)
        #expect(!HerdCommand.agents(rows, json: false).contains("is on"))
    }

    /// One machine carrying a version alone still names it, since "who is behind" is the
    /// question and the answer is a machine name.
    @Test
    func eachVersionCarriesTheMachinesThatHaveIt() {
        let drift = HerdCommand.drift(in: [
            row("A", [install(.claude, "2.1.260")]),
            row("B", [install(.claude, "2.1.255")]),
            row("C", [install(.claude, "2.1.260")]),
        ])
        #expect(drift.first?.versions.first?.machines == ["A", "C"])
        #expect(drift.first?.versions.last?.machines == ["B"])
    }

    /// **Three states, not two.** Storage has no agents by design; a machine that did
    /// not answer is a failure; a machine that answered with nothing is neither.
    @Test
    func storageSilenceAndEmptinessReadDifferently() {
        let text = HerdCommand.agents([
            row("Synology", nil, storage: true),
            row("Asleep", nil),
            row("Bare", []),
        ], json: false)
        #expect(text.contains("storage — no agents"))
        #expect(text.contains("not answering"))
        #expect(text.contains("nothing Little Herd can run"))
    }

    @Test
    func thejsonCarriesOneRowPerAgent() throws {
        let json = HerdCommand.agents([
            row("Air", [install(.claude, "2.1.260"), install(.codex, "0.153.4")]),
        ], json: true)
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]]
        #expect(parsed?.count == 2)
        #expect(parsed?.allSatisfy { $0["machine"] == "Air" } == true)
        #expect(Set(parsed?.compactMap { $0["version"] } ?? []) == ["2.1.260", "0.153.4"])
    }
}
