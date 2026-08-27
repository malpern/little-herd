import CoreGraphics

/// How big a machine's animal is drawn, wherever the herd is laid out in
/// columns.
///
/// One rule in one place, because there were two: the overview picked a size
/// from the number of machines while a machine's own page hard-coded 34, so
/// the animal changed size as you clicked into it — but only for a herd of
/// three or fewer, which is why nobody noticed for months.
///
/// **Derived from the column, not the count.** The column already knows how
/// much room there is; the count only knew how many ways it had been divided,
/// which is the same thing said less directly and wrong the moment the window
/// changes width.
nonisolated enum HerdAvatarSize {
    /// The size to aim for. The animal is the primary mark on these screens —
    /// it is how you find a machine before you have read anything — so it is
    /// drawn as large as a column of four will hold.
    static let preferred: CGFloat = 60
    /// Below this the animal would touch its neighbours.
    static let minimum: CGFloat = 24

    /// The gap between the animal and the name under it, and between that
    /// block and whatever sits above. One number, so a machine's identity is
    /// spaced the same on the overview as it is beside a metric — they used to
    /// differ by two points, which is invisible alone and reads as a wobble
    /// when you move between the screens.
    static let captionSpacing: CGFloat = 3

    static func forColumn(ofWidth width: CGFloat) -> CGFloat {
        // Four points of air on each side, so a wide animal in a narrow
        // column has somewhere to be.
        min(preferred, max(minimum, width - 8))
    }
}
