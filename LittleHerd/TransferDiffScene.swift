import SwiftUI

/// Loads a finished transfer's diff and shows it.
///
/// A view of its own so the reading happens once, when the window opens, and
/// not on every redraw of the dashboard — and so the window can say "reading
/// the branch…" rather than appearing empty while a `git fetch` runs.
struct TransferDiffSceneView: View {
    let model: MonitorModel

    @State private var diff: TransferDiff?
    @State private var failure: String?

    var body: some View {
        Group {
            if let transfer = model.transferBeingRead {
                TransferDiffView(
                    transfer: transfer,
                    phase: model.transfers.phase(for: transfer),
                    diff: diff,
                    error: failure
                )
                .task(id: transfer) {
                    diff = nil
                    failure = nil
                    switch await model.diff(for: transfer) {
                    case .success(let read): diff = read
                    case .failure(let error): failure = error.message
                    }
                }
            } else {
                // Reachable by opening the window from the menu with nothing
                // selected, which is not an error worth an alarm.
                Text("No transfer selected.")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 420, minHeight: 260)
            }
        }
    }
}
