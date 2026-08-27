import CoreGraphics

/// Which machine a carried token is over, given how far it has been carried.
///
/// Out here rather than in the view because it is arithmetic with an off-by-one
/// in it, and the version that lived in a gesture handler had one: it used the
/// gesture's *location*, which is reported in the token's own coordinate space,
/// so a token sitting perfectly still already read as twenty-odd points along.
/// The column under the pointer and the column being offered disagreed for the
/// whole gesture, and nothing about the code said so.
nonisolated struct HerdColumns: Equatable, Sendable {
    /// The machines, in the order they are drawn.
    let ids: [MachineID]
    /// Column width plus the gap between columns.
    let stride: CGFloat

    /// - Parameter dx: how far the token has been carried sideways from where
    ///   it started, which is the only quantity that is the same in every
    ///   coordinate space anyone might hand us.
    func machine(draggedFrom origin: MachineID, displacedBy dx: CGFloat) -> MachineID? {
        guard stride > 0, let start = ids.firstIndex(of: origin) else { return nil }
        // Rounded, so a column is claimed from the moment the token is closer
        // to it than to its neighbour — halfway, not all the way. Waiting for
        // full overlap makes the herd feel reluctant.
        let index = start + Int((dx / stride).rounded())
        guard ids.indices.contains(index) else { return nil }
        return ids[index]
    }
}
