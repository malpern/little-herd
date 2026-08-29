import SwiftUI
import Testing

@testable import LittleHerd

/// Draws the strip in each of its states, because none of them can be reached
/// in the running app yet — transfers are gated off — and a view nobody has
/// looked at is a view nobody has checked.
@MainActor
@Suite("Transfer strip, drawn")
struct TransferStripRenderTests {
    private let harness = PanelRenderHarness()

    private func transfer(_ title: String) -> Transfer {
        Transfer(
            origin: MachineID("local"),
            destination: MachineID("mini"),
            branch: "transfer/fan-layout-a1b2c3d4",
            title: title
        )
    }

    private func strip(_ phase: TransferPhase, count: Int = 1) -> some View {
        let all = (0..<count).map { transfer($0 == 0 ? "Fan layout" : "Other \($0)") }
        return TransferStrip(
            transfers: all,
            phase: { _ in phase },
            name: { $0 == MachineID("local") ? "Air" : "Mini" }
        )
    }

    @Test
    func drawEveryState() throws {
        let size = CGSize(width: 324, height: 68)
        try harness.render(strip(.preparing), size: size, named: "transfer-preparing")
        try harness.render(
            strip(.running(.agent)), size: size, named: "transfer-working"
        )
        try harness.render(
            strip(.running(.verification), count: 3),
            size: size,
            named: "transfer-many"
        )
        try harness.render(
            strip(.finished(.init(result: .landed, failingStep: nil, output: ""))),
            size: size,
            named: "transfer-landed"
        )
        try harness.render(
            strip(.finished(.init(
                result: .checkFailed,
                failingStep: .verification,
                output: "2 tests failed"
            ))),
            size: size,
            named: "transfer-red"
        )
    }
}
