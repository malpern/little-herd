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

/// The pad these states used to paint is gone — the agents ride the animals
/// now, and a drop lands on an animal rather than on a surface under it. The
/// states themselves survive because they are the question a drag asks of each
/// machine, which has not changed: nothing, could take it, pointed at, refused.
