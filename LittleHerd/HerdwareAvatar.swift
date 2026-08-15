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

enum LittleHerdTheme {
    static let background = Color(
        red: 0.984,
        green: 0.973,
        blue: 0.946
    )
    static let forest = Color(
        red: 0.075,
        green: 0.31,
        blue: 0.235
    )
    static let loadGreen = Color(
        red: 0.12,
        green: 0.62,
        blue: 0.32
    )
    static let loadTeal = Color(
        red: 0.10,
        green: 0.61,
        blue: 0.54
    )
    static let emptyBlock = Color(
        red: 0.33,
        green: 0.31,
        blue: 0.27,
        opacity: 0.09
    )
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
