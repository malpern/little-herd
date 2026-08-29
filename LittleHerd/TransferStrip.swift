import SwiftUI

/// How a transfer's state reads at a glance.
nonisolated enum TransferTint: Equatable {
    /// Under way. Nothing to do but watch, or call it off.
    case working
    /// Landed on the branch.
    case landed
    /// Ended in a way that leaves something to read.
    case wantsReading
    /// Called off. Not a failure, and not worth colouring like one.
    case quiet
}

extension TransferPhase {
    var tint: TransferTint {
        switch self {
        case .preparing, .running: .working
        case .finished(let outcome):
            switch outcome.result {
            case .landed: .landed
            case .checkFailed, .agentFailed, .couldNotStart: .wantsReading
            case .cancelled: .quiet
            }
        }
    }

    /// What the control on the right does.
    ///
    /// **A running transfer offers to stop; a finished one offers to go away.**
    /// They are deliberately not the same button wearing two labels: stopping
    /// something on another machine and clearing a row you have read are
    /// different enough that a mis-click should not be able to do one while
    /// meaning the other.
    var control: TransferControl {
        isCancellable ? .stop : .dismiss
    }
}

nonisolated enum TransferControl: Equatable {
    case stop
    case dismiss
}

/// One transfer, in the band the overview header usually occupies.
///
/// **The same height as the header it stands in for**, so a transfer starting
/// does not move the herd underneath it. This window's height is set to the
/// point and anything that grows the content pushes the metric tabs off the
/// bottom — which has happened three times.
///
/// It replaces the header rather than sitting above it because a transfer is
/// the most important thing on the screen while it is happening, and because
/// the header says how many machines are live, which the herd below already
/// shows.
struct TransferStrip: View {
    let transfers: [Transfer]
    let phase: (Transfer) -> TransferPhase?
    let name: (MachineID) -> String
    var onStop: (Transfer) -> Void = { _ in }
    var onDismiss: (Transfer) -> Void = { _ in }
    var onOpen: (Transfer) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            if let transfer = transfers.first, let phase = phase(transfer) {
                row(transfer, phase)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 68)
    }

    @ViewBuilder
    private func row(_ transfer: Transfer, _ phase: TransferPhase) -> some View {
        HStack(spacing: 10) {
            mark(phase)

            VStack(alignment: .leading, spacing: 2) {
                Text(transfer.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(name(transfer.origin))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7, weight: .bold))
                    Text(name(transfer.destination))
                    Text("·")
                    Text(phase.summary)
                        .lineLimit(1)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            // The count, when more than one is in flight. There is room for
            // one row here and no more; the rest are on the machine's own page.
            if transfers.count > 1 {
                Text("+\(transfers.count - 1)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            control(transfer, phase)
        }
        .padding(.horizontal, 14)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onOpen(transfer) }
    }

    @ViewBuilder
    private func mark(_ phase: TransferPhase) -> some View {
        switch phase.tint {
        case .working:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .landed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .wantsReading:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        case .quiet:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func control(
        _ transfer: Transfer,
        _ phase: TransferPhase
    ) -> some View {
        switch phase.control {
        case .stop:
            Button {
                onStop(transfer)
            } label: {
                Image(systemName: "stop.circle")
            }
            .buttonStyle(.plain)
            .help(Text("Stop this transfer"))
            .accessibilityLabel(Text("Stop transfer"))
        case .dismiss:
            Button {
                onDismiss(transfer)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(Text("Clear"))
            .accessibilityLabel(Text("Clear transfer"))
        }
    }
}
