import SwiftUI

/// How a pad looks during a drag. A plain value, outside the view, because it
/// is a decision rather than a drawing — and because a state nested inside a
/// generic view cannot be named without inventing a content type to stand in
/// for the thing the pad happens to be holding.
nonisolated enum AgentPadState: Equatable, Sendable {
    /// Nothing is being dragged.
    case idle
    /// A drag is in progress somewhere and this machine could take it.
    case available
    /// A drag is in progress, this machine could take it, and the pointer is
    /// here.
    case targeted
    /// A drag is in progress and this machine cannot take it.
    case refused
}

/// The surface a machine's agent tokens rest on, and the place one can be
/// dropped.
///
/// A pad per machine rather than one band across the herd, and that is the
/// drag deciding the drawing: a band would be one surface with four meanings,
/// and every drop would need the app to work out which quarter of it you were
/// over. A pad is a target in its own right — it lights when a token could
/// land on it and refuses when it could not.
///
/// At rest it is nearly invisible, and only under a machine that has something
/// running. During a drag every machine shows one, because the question has
/// changed from "what is happening here" to "where could this go", and a
/// machine with nothing running is the most interesting answer to the second.
struct MachineAgentPad<Content: View>: View {
    var state: AgentPadState = .idle
    var height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        // `Color.clear` behind the content, and it is load-bearing. A pad with
        // nothing on it is `EmptyView`, which produces no layout at all and
        // silently discards the frame below it — so during a drag the machines
        // with nothing running, the most interesting answer to "where could
        // this go", were the only ones that drew no pad. Nothing about the
        // code said so; a render did.
        ZStack {
            Color.clear
            content()
        }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(fill)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(stroke, style: strokeStyle)
                    }
            }
            .animation(.easeOut(duration: 0.18), value: state)
    }

    /// Colour carries availability; the dashed edge carries "this is a place
    /// something could go". Neither is used at rest, where a lit pad under
    /// every machine would be four permanent boxes saying nothing.
    private var fill: Color {
        switch state {
        case .idle: Color.secondary.opacity(0.06)
        case .available: Color.secondary.opacity(0.10)
        case .targeted: Color.accentColor.opacity(0.18)
        // Fainter than a pad at rest, because a machine that will not take
        // this is further from the conversation than one nobody is asking.
        case .refused: Color.secondary.opacity(0.03)
        }
    }

    private var stroke: Color {
        switch state {
        case .idle: .clear
        case .available: Color.secondary.opacity(0.35)
        case .targeted: Color.accentColor
        case .refused: Color.red.opacity(0.3)
        }
    }

    /// **The dashes mean "a thing could go here."** Only the pads that could
    /// take the token get them; the one that cannot gets a solid, dimmer edge.
    /// Dashing a refusal the same as an offer — which is what this did first —
    /// leaves the two states a person most needs to tell apart looking like
    /// the same grey box, and no amount of colour tuning fixes that while the
    /// silhouette still says yes.
    private var strokeStyle: StrokeStyle {
        switch state {
        case .targeted: StrokeStyle(lineWidth: 1.5)
        case .refused: StrokeStyle(lineWidth: 1)
        default: StrokeStyle(lineWidth: 1, dash: [3, 3])
        }
    }
}
