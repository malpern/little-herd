import SwiftUI

/// How many agents there are, when the deck cannot show it by being deep.
///
/// Shared by the resting deck and the fan **because the two hand over to each
/// other**. It used to belong to the stack alone, so the count appeared out of
/// nothing the instant the fan was taken away — one more thing changing at the
/// moment the whole point is that nothing changes.
///
/// **No ring.** It was a stroke in the window's own background colour, there to
/// separate the circle from a dark icon behind it. Against the art it reads as
/// a white line drawn round a number, which is what it looks like rather than
/// what it was for.
struct AgentDeckCountMark: View {
    let count: Int
    /// The icon this sits on the corner of, so it scales with the deck.
    let iconSize: CGFloat

    var body: some View {
        Text("\(count)")
            .font(.system(size: iconSize * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: iconSize * 0.44, height: iconSize * 0.44)
            .background(Circle().fill(Color.accentColor))
            .offset(x: iconSize * 0.16, y: -iconSize * 0.12)
    }
}
