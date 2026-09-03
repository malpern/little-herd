import SwiftUI

/// What came back, in a window of its own.
///
/// **Not in the dashboard.** That window is 324 points wide and sized to the
/// point; a diff is the one thing here that genuinely needs room, and squeezing
/// it into the herd's window would cost the herd its size for something you
/// look at occasionally and read carefully.
struct TransferDiffView: View {
    let transfer: Transfer
    let phase: TransferPhase?
    let diff: TransferDiff?
    let error: String?
    var onOpenInTerminal: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if let error {
                message(error, systemImage: "exclamationmark.triangle")
            } else if let diff {
                if diff.isEmpty {
                    // A real outcome, and one worth saying plainly: the agent
                    // finished and changed nothing.
                    message(
                        "The agent finished without changing any files.",
                        systemImage: "doc"
                    )
                } else {
                    content(diff)
                }
            } else {
                message("Reading the branch…", systemImage: "clock")
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transfer.title)
                .font(.headline)

            HStack(spacing: 6) {
                if let phase {
                    Text(phase.detail)
                } else {
                    Text(transfer.branch)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            // Only when there is one. A branch name under "nothing was
            // changed anywhere" is the same contradiction as the sentence this
            // window used to print above it, and a name somebody can select
            // and paste into a shell is a promise that it resolves.
            if phase.map(\.leftABranch) ?? true {
                Text(transfer.branch)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
    }

    @ViewBuilder
    private func content(_ diff: TransferDiff) -> some View {
        // A plain split rather than `HSplitView`: one less AppKit-backed
        // container, and the draggable divider was buying very little for a
        // window whose two halves have obvious sizes.
        HStack(spacing: 0) {
            // What changed, at a glance, and how much of it.
            List(diff.files) { file in
                HStack(spacing: 8) {
                    Text(file.path)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer(minLength: 6)
                    if file.isBinary {
                        Text("binary")
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("+\(file.added ?? 0)").foregroundStyle(.green)
                        Text("−\(file.removed ?? 0)").foregroundStyle(.red)
                    }
                }
                .font(.caption2)
            }
            .frame(width: 240)
            .listStyle(.plain)

            Divider()

            // And the whole of it, for reading.
            ScrollView([.horizontal, .vertical]) {
                Text(diff.patch)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(diff.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Nothing has been merged.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
