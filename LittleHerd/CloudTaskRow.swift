import SwiftUI

/// One Codex cloud task, in the AI panel beside the machines.
///
/// **A row rather than an affordance, and that difference is the honest part.** A Codex
/// cloud task can be enumerated, so it can be listed with its repository, its age and
/// what applying it would change. Claude cloud cannot be listed from here at all, so it
/// gets a sentence at the foot of the section instead of an empty list that would read
/// as "you have no Claude cloud work" — a claim this app cannot make.
struct CloudTaskRow: View {
    let task: CodexCloudTask
    /// Where it could be applied. Empty is a real answer and is said out loud, because
    /// "nowhere has this checkout" is what a person needs to know before they go looking
    /// for the button that would do it.
    let landsOn: [CodexCloudPlacement.Candidate]
    /// Applying it somewhere. Nil in a render, where nothing should be runnable.
    var onApply: ((CodexCloudPlacement.Candidate) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image("owl-cloud")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 5) {
                    // The slug, not `owner/name`. Every task on this herd carries the
                    // same owner, so the prefix spends eight characters saying nothing
                    // — and at panel width it was pushing the date and the diff into
                    // an ellipsis. Seen in the render, not in a test.
                    Text(task.repositorySlug)
                    Text("·")
                    Text(task.when)
                    if let diff = diffLabel {
                        Text("·")
                        Text(diff)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                placementLine
            }
            Spacer(minLength: 0)
            statusMark
        }
        .padding(.vertical, 5)
    }

    private var diffLabel: String? {
        switch task.diff {
        case .none: nil  // Most finished tasks say this; repeating it is noise.
        case .changes(let added, let removed, _):
            // The file count went the same way as the owner prefix: useful in
            // `little-herd cloud`, too expensive for a 300-point row.
            "+\(added)/−\(removed)"
        case .unreadable(let text): text
        }
    }

    /// The machines, each one a button. The line already read "apply on Air, Mac mini";
    /// this makes the words mean it.
    @ViewBuilder
    private var placementLine: some View {
        if landsOn.isEmpty {
            // The slug is already on the line above, so naming it again was the same
            // word twice in three lines. The CLI still names it, where there is room
            // and no line above to have said it.
            Text("no machine has this checkout")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            HStack(spacing: 4) {
                // **Grey label, coloured machines.** Rendering it caught the two halves
                // arriving as two different blues — a `.plain` button tints its label
                // differently from the `Text` beside it — which read as two states
                // rather than one sentence. Making the label secondary fixes the
                // mismatch and says the truer thing anyway: the machine names are the
                // part you can click.
                Text("apply on")
                    .foregroundStyle(.secondary)
                ForEach(Array(landsOn.enumerated()), id: \.element.id) { index, candidate in
                    Button {
                        // Confirmed by `MonitorModel.applyCloudTask`, which names the
                        // machine and the directory — the same alert every other
                        // machine command goes through. Confirming here as well would
                        // ask twice for one act.
                        onApply?(candidate)
                    } label: {
                        Text(candidate.machine + (index < landsOn.count - 1 ? "," : ""))
                            .foregroundStyle(Color.accentColor)
                            .underline(isHovering == candidate.id)
                    }
                    .buttonStyle(.plain)
                    .pointerStyle(.link)
                    .onHover { inside in isHovering = inside ? candidate.id : nil }
                    .disabled(onApply == nil)
                }
            }
            .font(.caption2)
            .lineLimit(1)
        }
    }

    @State private var isHovering: MachineID?

    @ViewBuilder
    private var statusMark: some View {
        switch task.status {
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(Text("This task failed in the cloud."))
        case .running, .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
        case .ready, .applied, .unknown:
            EmptyView()
        }
    }
}

/// The sentence that stands in for a list nobody can produce.
struct ClaudeCloudNote: View {
    var body: some View {
        Text("Claude cloud sessions can’t be listed from here — pull one onto a machine by id.")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
    }
}
