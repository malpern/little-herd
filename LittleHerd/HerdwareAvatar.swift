import AppKit
import SwiftUI

nonisolated enum HerdwareAvatar: String, CaseIterable, Codable, Identifiable,
    Sendable
{
    case chickLaptop = "chick-laptop"
    case calfMini = "calf-mini"
    case lambStudio = "lamb-studio"
    case duckAllInOne = "duck-all-in-one"
    case rabbitNUC = "rabbit-nuc"
    case catEdge = "cat-edge"
    case pigletNAS = "piglet-nas"
    case ponyTower = "pony-tower"
    case oxGPU = "ox-gpu"
    case goatRack = "goat-rack"
    case roosterCoordinator = "rooster-coordinator"
    case owlCloud = "owl-cloud"

    var id: Self { self }
    var assetName: String { rawValue }
}

extension MachineID {
    var herdwareAvatar: HerdwareAvatar {
        switch self {
        case .macBookAir: .chickLaptop
        case .macMini: .calfMini
        case .linux: .pigletNAS
        case .synology: .pigletNAS
        default: .rabbitNUC
        }
    }
}

/// The palette, defined once for both appearances.
///
/// These were literals, which meant the app kept its cream background in Dark
/// Mode while the semantic text colours inverted around it — near-white type on
/// near-white paper. A monitor that sits on screen all day is exactly the sort
/// of app people run in a dark room, so it has to follow the system.
///
/// Asset colours rather than a dynamic `NSColor`: SwiftUI resolves a colour set
/// against the view's own appearance, where a dynamic NSColor bridged through
/// `Color(nsColor:)` kept resolving light no matter what the system was set to.
enum LittleHerdTheme {
    /// Warm paper in light, a warm near-black in dark — not pure black, which
    /// would leave the avatars looking like stickers floating in a void.
    static let background = Color("HerdBackground", bundle: .main)

    /// The brand green, lifted in dark so it clears the background instead of
    /// sinking into it.
    static let forest = Color("HerdForest", bundle: .main)

    static let loadGreen = Color("HerdLoadGreen", bundle: .main)
    static let loadTeal = Color("HerdLoadTeal", bundle: .main)

    /// The unlit segments of a thermometer. Dark needs a lighter, more opaque
    /// value: a dark wash on a dark ground is invisible, and the empty blocks
    /// are what give the bar its shape.
    static let emptyBlock = Color("HerdEmptyBlock", bundle: .main)
}

struct MachineAvatarView: View {
    let avatar: HerdwareAvatar
    var size: CGFloat

    init(machine: MachineID, size: CGFloat) {
        avatar = machine.herdwareAvatar
        self.size = size
    }

    init(avatar: HerdwareAvatar, size: CGFloat) {
        self.avatar = avatar
        self.size = size
    }

    var body: some View {
        Image(avatar.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
