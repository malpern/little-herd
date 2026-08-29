import SwiftUI
import Testing

@testable import LittleHerd

/// Draws the card in transit over the kind of background it actually sits on —
/// the thermometer blocks — which is where the bar's first position failed.
@MainActor
@Suite("Transit card, drawn")
struct TransitCardRenderTests {
    private let harness = PanelRenderHarness()

    private var session: AgentSession {
        AgentSession(
            id: "s1", provider: .claude, projectName: "little-herd",
            state: .active, updatedAt: Date(), progress: nil
        )
    }

    private func board(_ card: some View) -> some View {
        ZStack {
            // Stand-in thermometer blocks, in the colours that made the bar
            // disappear into the chart.
            VStack(spacing: 4) {
                ForEach(0..<9, id: \.self) { row in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(row > 5 ? Color.green : Color.gray.opacity(0.35))
                        .frame(width: 64, height: 9)
                }
            }
            card
        }
        .frame(width: 130, height: 150)
    }

    @Test
    func drawEveryStage() throws {
        for (fraction, name) in [(0.10, "start"), (0.60, "agent"), (0.96, "push")] {
            try harness.render(
                board(
                    AgentTransitCard(
                        session: session,
                        state: .working(fraction),
                        size: 54
                    )
                ),
                size: CGSize(width: 130, height: 150),
                named: "transit-\(name)"
            )
        }
        try harness.render(
            board(
                AgentTransitCard(session: session, state: .succeeded, size: 54)
            ),
            size: CGSize(width: 130, height: 150),
            named: "transit-done"
        )
    }
}
