import SwiftUI

/// One place for the overview ↔ machine-detail transition.
///
/// The avatar morphs between the two layouts with `matchedGeometryEffect`
/// while everything else cross-fades, so the machine you clicked stays on
/// screen and carries you into its details. Window resizing is handled by
/// `.windowResizability(.contentSize)`, which follows the content, so the
/// content animation is the only timing that matters — but it has to be a
/// single value, or the avatar and the fade drift apart.
enum DashboardTransition {
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .smooth(duration: 0.34)
    }

    /// Namespace id for a machine's avatar, shared by the overview column and
    /// the detail rail.
    static func avatarID(_ machine: MachineID) -> String {
        "machine-avatar-\(machine.rawValue)"
    }
}

extension View {
    /// Applies the shared avatar geometry only when a namespace is supplied,
    /// so the same label can be reused outside the transition.
    @ViewBuilder
    func matchedAvatar(_ namespace: Namespace.ID?, machine: MachineID) -> some View {
        if let namespace {
            matchedGeometryEffect(
                id: DashboardTransition.avatarID(machine),
                in: namespace
            )
        } else {
            self
        }
    }
}
