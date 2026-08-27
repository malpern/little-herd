import CoreGraphics

/// The shapes and sizes the dashboard repeats, in one place.
///
/// Not an abstraction for its own sake: an audit found ten distinct corner
/// radii and a row-icon size that one file was reading out of an unrelated
/// view's namespace. Values that two views must agree on need somewhere to
/// live that is neither of them, or they agree by coincidence until somebody
/// edits one.
///
/// **The very small radii are deliberately not here.** A thermometer block or
/// a progress segment is rounded in proportion to its own height, and pinning
/// those to a shared scale would make a two-point bar and a panel corner the
/// same idea, which they are not.
nonisolated enum HerdRadius {
    /// Pills and tabs — something you click that is smaller than a row.
    static let control: CGFloat = 6
    /// Rows, pads, inline cards: a surface inside a panel.
    static let surface: CGFloat = 8
    /// A panel or sheet in its own right.
    static let panel: CGFloat = 12
    /// The largest, for a card that stands alone on its ground.
    static let card: CGFloat = 16
}

/// How large a leading mark is drawn in a list.
nonisolated enum HerdIconSize {
    /// What a row leads with — an application's icon, an agent's mark, a
    /// symbol standing in for either. Large enough to be identified rather
    /// than merely noticed.
    static let row: CGFloat = 26
    /// A mark beside a label rather than at the head of a row.
    static let inline: CGFloat = 15
}
