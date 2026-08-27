import SwiftUI

/// The agents running on one machine, stacked behind its animal.
///
/// **No card around them.** The provider icons are already application icons —
/// rounded, self-contained, carrying their own ground — so a rounded rectangle
/// with a stroke around each one frames a frame, and a fan of six became
/// eighteen edges. What separates an icon from the art is the animal's own
/// silhouette in front of it, plus a soft shadow. Nothing else was doing any
/// work.
///
/// **The deck leans sideways, and it has to.** Stacked squarely, every card but
/// the top one is hidden behind the animal, so one session and four look
/// identical. A few points of lean per card puts their edges where they can be
/// seen.
struct MachineAgentStack: View {
    let activity: MachineAgentActivity
    /// The animal this sits behind, so the icons can be sized and placed
    /// against it rather than against a constant.
    let avatarSize: CGFloat

    /// What is drawn at rest, before anything is hovered or arriving.
    static func iconSize(forAvatar avatar: CGFloat) -> CGFloat { avatar * 0.44 }
    /// How far each card behind the top one leans, as a share of the avatar.
    private static let lean: CGFloat = 0.11
    /// The deck at rest shows about this much of itself above the animal.
    static let peek: CGFloat = 0.62

    /// The room the deck needs above the animal, which the thermometer gives
    /// up so the two do not overlap.
    ///
    /// In the sketches there was empty space over each animal and the deck
    /// simply peeked into it. There is none in the real column — the bars run
    /// down to the animal's head — so without this the deck sits on top of the
    /// lowest blocks, which are the ones that are always lit. The bars lose a
    /// few points; the same trade Disk's capacity lines already make.
    static func clearance(forAvatar avatar: CGFloat) -> CGFloat {
        iconSize(forAvatar: avatar) * peek
    }

    /// Three is as many edges as read as a deck; beyond that the count says it.
    private static let visibleCards = 3

    var body: some View {
        let icon = Self.iconSize(forAvatar: avatarSize)
        ZStack(alignment: .bottom) {
            ForEach(Array(cards.enumerated().reversed()), id: \.offset) { index, session in
                Image(nsImage: AgentProviderIcons.icon(for: session.provider))
                    .resizable()
                    .scaledToFit()
                    .frame(width: icon, height: icon)
                    .shadow(color: .black.opacity(0.22), radius: icon * 0.12, y: 1)
                    .offset(
                        x: CGFloat(index) * avatarSize * Self.lean,
                        y: -CGFloat(index) * avatarSize * 0.03
                    )
                    // The ones behind sit back a little, so the deck has depth
                    // without needing an outline to describe it.
                    .opacity(index == 0 ? 1 : 0.85)
            }
        }
        .overlay(alignment: .topTrailing) { countMark }
        .frame(width: icon, height: icon, alignment: .bottom)
        // Only the top of the deck clears the animal; the rest is behind it.
        .offset(y: -icon * Self.peek)
        .accessibilityLabel(Text(summary))
    }

    private var cards: [AgentSession] {
        Array(activity.sessions.prefix(Self.visibleCards))
    }

    /// The count, since a deck three deep cannot show that it is five deep.
    @ViewBuilder
    private var countMark: some View {
        if activity.showsCount {
            let icon = Self.iconSize(forAvatar: avatarSize)
            Text("\(activity.count)")
                .font(.system(size: icon * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: icon * 0.44, height: icon * 0.44)
                .background(Circle().fill(Color.accentColor))
                .overlay(Circle().strokeBorder(LittleHerdTheme.background, lineWidth: 1.5))
                .offset(x: icon * 0.16, y: -icon * 0.12)
        }
    }

    private var summary: String {
        activity.count == 1
            ? "\(activity.provider.shortName) running"
            : "\(activity.count) agent sessions running"
    }
}

extension AgentTaskProvider {
    /// The name as a sentence uses it.
    var shortName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}
