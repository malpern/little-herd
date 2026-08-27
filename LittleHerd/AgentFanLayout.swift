import CoreGraphics

/// Where each agent icon goes when a machine's deck fans out.
///
/// Out here rather than in the view for the reason `HerdColumns` is: it is
/// arithmetic with clamping and a remainder in it, and the last time this
/// project put that sort of thing inside a gesture handler it hid an off-by-one
/// for a whole release.
///
/// **The fan belongs to the window, not to the column.** A column is sixty-odd
/// points wide and a fan of six is most of the window, so the only constraint
/// that matters is the window's own width. It centres on the animal it came
/// from, stops at either margin rather than running off, and when more agents
/// are running than the window can hold, the last place goes to a card standing
/// for the rest.
nonisolated struct AgentFanLayout: Equatable, Sendable {
    /// One rect per icon, in the order the agents were given.
    let icons: [CGRect]
    /// The trailing card, and how many agents it stands for.
    let overflow: (rect: CGRect, count: Int)?

    static func == (lhs: AgentFanLayout, rhs: AgentFanLayout) -> Bool {
        lhs.icons == rhs.icons
            && lhs.overflow?.rect == rhs.overflow?.rect
            && lhs.overflow?.count == rhs.overflow?.count
    }

    /// - Parameters:
    ///   - count: how many agents are running on the machine.
    ///   - centre: the middle of the animal they belong to, in window
    ///     coordinates.
    ///   - width: the window's width.
    ///   - tile: how big each icon is drawn when raised.
    static func lay(
        out count: Int,
        centredOn centre: CGFloat,
        inWindowOfWidth width: CGFloat,
        tile: CGFloat,
        gap: CGFloat,
        margin: CGFloat = 10
    ) -> AgentFanLayout {
        guard count > 0, tile > 0, width > 0 else {
            return AgentFanLayout(icons: [], overflow: nil)
        }
        let usable = max(tile, width - margin * 2)
        let pitch = tile + gap

        // How many whole tiles the window holds, and whether one of those
        // places has to be spent on the remainder card.
        let fitting = max(1, Int((usable + gap) / pitch))
        let shown = count > fitting ? max(1, fitting - 1) : count
        let remainder = count - shown
        let cards = shown + (remainder > 0 ? 1 : 0)

        let total = CGFloat(cards) * tile + CGFloat(cards - 1) * gap
        // Centred on the animal until a margin stops it. Clamped low-first, so
        // a fan wider than the window still starts at the left margin rather
        // than being pushed off it.
        let left = min(max(centre - total / 2, margin), max(margin, width - margin - total))

        var icons: [CGRect] = []
        for index in 0 ..< shown {
            icons.append(
                CGRect(x: left + CGFloat(index) * pitch, y: 0, width: tile, height: tile)
            )
        }
        guard remainder > 0 else {
            return AgentFanLayout(icons: icons, overflow: nil)
        }
        return AgentFanLayout(
            icons: icons,
            overflow: (
                CGRect(x: left + CGFloat(shown) * pitch, y: 0, width: tile, height: tile),
                remainder
            )
        )
    }
}
