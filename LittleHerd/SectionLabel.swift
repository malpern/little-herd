import SwiftUI

/// The small capitalised label over a group of rows.
///
/// One implementation, because there were three: a pane's title, the seam
/// between installed agents and sessions, and the AI panel's section headers
/// all wanted the same typography and had each been written separately. They
/// had drifted to two tracking values and two greys, which is the kind of
/// difference nobody sees and everybody feels.
///
/// The two prominences are a real hierarchy rather than the drift preserved:
/// a pane has one title, and any seam inside it is subordinate to that title.
struct SectionLabel: View {
    let title: Text
    var prominence: Prominence = .title
    /// A rule running to the trailing edge, for a seam *between* groups rather
    /// than a heading above one.
    var hasRule = false

    /// Positive tracking, because at this size capitals set solid read as a
    /// block rather than as words. Shared so the AI panel's own headers, which
    /// carry a glyph and a count and so cannot be this view, still agree with
    /// it — they had drifted to 0.3.
    static let tracking: CGFloat = 0.35

    enum Prominence {
        /// The one heading a pane carries.
        case title
        /// A division inside a pane that already has a title.
        case seam
    }

    var body: some View {
        HStack(spacing: 6) {
            title
                .font(.caption2.weight(.semibold))
                .tracking(Self.tracking)
                .foregroundStyle(prominence == .title ? .secondary : .tertiary)
                .accessibilityAddTraits(.isHeader)

            if hasRule {
                VStack { Divider() }
            }
        }
    }
}
