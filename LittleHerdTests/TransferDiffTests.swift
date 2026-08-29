import Foundation
import Testing

@testable import LittleHerd

@Suite("Transfer diff")
struct TransferDiffTests {
    /// **From the commit the source pushed, not from the branch's parent.**
    /// The branch carries the departure commit as well — the brief, and
    /// whatever was uncommitted when the session left — and diffing from its
    /// parent would show all of that as though the agent had written it.
    @Test
    func theDiffStartsWhereTheAgentDid() {
        let commands = TransferDiffReader.commands(
            repository: "/repo",
            branch: "transfer/x",
            since: "abc123"
        )
        #expect(commands.first?.contains("fetch") == true)
        #expect(commands.contains { $0.contains("abc123..FETCH_HEAD") })
        #expect(!commands.contains { $0.contains("FETCH_HEAD~1") })
    }

    @Test
    func itCountsWhatChanged() {
        let diff = TransferDiffReader.parse(
            numstat: "12\t3\tLittleHerd/A.swift\n4\t0\tLittleHerdTests/B.swift",
            patch: "diff --git a/A b/A"
        )
        #expect(diff.files.count == 2)
        #expect(diff.addedTotal == 16)
        #expect(diff.removedTotal == 3)
        #expect(diff.summary == "2 files · +16 −3")
    }

    /// A binary file is counted in neither direction, and must not be read as
    /// zero lines changed — which would say nothing happened to it.
    @Test
    func aBinaryFileIsNotZeroLines() {
        let diff = TransferDiffReader.parse(
            numstat: "-\t-\tArt/crab.png\n2\t1\tA.swift",
            patch: ""
        )
        let binary = diff.files.first { $0.path == "Art/crab.png" }
        #expect(binary?.isBinary == true)
        #expect(binary?.added == nil)
        // And it still counts as a file that changed.
        #expect(diff.files.count == 2)
        #expect(diff.addedTotal == 2)
    }

    /// A transfer that changed nothing says so rather than showing an empty
    /// list, because "the agent did nothing" is a real outcome worth reading.
    @Test
    func nothingChangedSaysSo() {
        let diff = TransferDiffReader.parse(numstat: "", patch: "")
        #expect(diff.isEmpty)
        #expect(diff.summary == "No changes")
    }

    /// Paths with spaces survive, since `--numstat` splits on tabs and a path
    /// is the last field however many spaces it has.
    @Test
    func aPathWithSpacesSurvives() {
        let diff = TransferDiffReader.parse(
            numstat: "1\t1\tDocumentation/my notes.md",
            patch: ""
        )
        #expect(diff.files.first?.path == "Documentation/my notes.md")
    }
}
