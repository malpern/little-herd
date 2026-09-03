import SwiftUI
import Testing

@testable import LittleHerd

/// Draws the diff window, which cannot be opened in the app without a real
/// transfer behind it.
///
/// **The two panes do not render here and that is the harness, not the view.**
/// `ImageRenderer` cannot lay out lazy containers, so the file list and the
/// scrolling patch both come out as a placeholder — the same limitation that
/// stops it drawing a `ProgressView`. What these check is the frame: the
/// header, the summary bar, and that a diff with no files says so instead of
/// showing an empty list.
@MainActor
@Suite("Transfer diff, drawn")
struct TransferDiffRenderTests {
    private let harness = PanelRenderHarness()

    private var transfer: Transfer {
        Transfer(
            origin: MachineID("local"),
            destination: MachineID("mini"),
            branch: "transfer/fan-layout-a1b2c3d4",
            title: "Fan layout",
            repository: "/Users/malpern/local-code/little-herd"
        )
    }

    @Test
    func drawTheDiff() throws {
        let diff = TransferDiffReader.parse(
            numstat: """
                12\t3\tLittleHerd/MachineAgentFan.swift
                6\t0\tLittleHerdTests/SuccessorSSHTests.swift
                -\t-\tLittleHerd/Assets.xcassets/Herdware/crab-mini.png
                """,
            patch: """
                diff --git a/LittleHerd/MachineAgentFan.swift b/LittleHerd/MachineAgentFan.swift
                index 945208b..63e2dd0 100644
                --- a/LittleHerd/MachineAgentFan.swift
                +++ b/LittleHerd/MachineAgentFan.swift
                @@ -136,4 +136,10 @@ struct MachineAgentFan: View {
                     }
                 
                +    /// The distance from the fan's row down to where the deck rests.
                +    private var rise: CGFloat {
                +        avatarSize * CPUOverviewView.deckDrop
                +    }
                 }
                """
        )
        try harness.render(
            TransferDiffView(
                transfer: transfer,
                phase: .finished(
                    .init(result: .checkFailed, failingStep: .verification, output: "")
                ),
                diff: diff,
                error: nil
            ),
            size: CGSize(width: 720, height: 460),
            named: "transfer-diff"
        )
        try harness.render(
            TransferDiffView(
                transfer: transfer,
                phase: .finished(.init(result: .landed, failingStep: nil, output: "")),
                diff: TransferDiffReader.parse(numstat: "", patch: ""),
                error: nil
            ),
            size: CGSize(width: 720, height: 300),
            named: "transfer-diff-empty"
        )

        // The two failures that leave nothing to read, drawn because the
        // difference between them is the whole of what this window has to
        // say. The one that made no branch must not print a branch name --
        // that name is selectable text somebody will paste into a shell.
        try harness.render(
            TransferDiffView(
                transfer: transfer,
                phase: .finished(
                    .init(
                        result: .couldNotStart,
                        failingStep: nil,
                        output: "",
                        remnant: .nothing
                    )
                ),
                diff: nil,
                error: "This transfer did not get as far as pushing "
                    + "anything, so there is nothing on the branch to read."
            ),
            size: CGSize(width: 720, height: 460),
            named: "transfer-diff-nothing-left"
        )
        try harness.render(
            TransferDiffView(
                transfer: transfer,
                phase: .finished(
                    .init(
                        result: .couldNotStart,
                        failingStep: nil,
                        output: "",
                        remnant: .pushedBranch
                    )
                ),
                diff: nil,
                error: "Couldn’t read the branch. The work is still on "
                    + "\(transfer.branch); nothing has been merged."
            ),
            size: CGSize(width: 720, height: 460),
            named: "transfer-diff-never-arrived"
        )
    }
}
