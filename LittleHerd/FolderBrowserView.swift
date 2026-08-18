import SwiftUI

/// What is taking up a volume, laid out the way the Finder lays it out.
///
/// Column headings that sort, disclosure triangles that open in place, and
/// sizes written the way a person would write them. The one thing it does that
/// the Finder does not is admit how long it is taking: folder sizes are
/// expensive, and a progress bar with a count is more honest than a spinner
/// that could mean anything.
struct FolderBrowserView: View {
    @Bindable var model: FolderBrowserModel
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let scan = model.scan(for: path) {
                status(for: scan)
            }
            rows
        }
    }

    // MARK: - Progress, which this list owes the reader

    @ViewBuilder
    private func status(for scan: FolderScan) -> some View {
        switch scan.state {
        case .listing:
            ProgressView()
                .controlSize(.small)
                .padding(.vertical, 4)

        case .measuring(let progress):
            VStack(alignment: .leading, spacing: 3) {
                ProgressView(value: progress.fraction)
                    .progressViewStyle(.linear)
                HStack {
                    Text("\(progress.measured) of \(progress.total)")
                    if let remaining = progress.estimatedRemaining {
                        // "About", because the estimate counts folders rather
                        // than bytes and one build tree can dwarf the rest.
                        Text("· about \(Duration.seconds(remaining).formatted(.units(allowed: [.minutes, .seconds], width: .narrow))) left")
                    }
                    Spacer()
                    Button("Stop") { model.toggle(path) }
                        .buttonStyle(.link)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

        case .done(let measuredAt):
            HStack {
                Text("Measured \(FolderDateFormatter.string(for: measuredAt).lowercased())")
                Spacer()
                Button("Refresh") { model.refresh(path) }
                    .buttonStyle(.link)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.vertical, 2)

        case .failed(let message):
            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)

        case .idle, .cancelled:
            EmptyView()
        }
    }

    // MARK: - The list

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.rows.isEmpty {
                FolderColumnHeader(sort: $model.sort)
            }
            ForEach(model.rows) { row in
                FolderRowView(row: row, model: model)
            }
        }
    }
}

/// A heading that sorts, and shows which way.
private struct FolderColumnHeader: View {
    @Binding var sort: FolderSort

    var body: some View {
        HStack(spacing: 8) {
            heading(.name)
                .frame(maxWidth: .infinity, alignment: .leading)
            heading(.dateModified)
                .frame(width: 68, alignment: .trailing)
            heading(.size)
                .frame(width: 58, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 3)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func heading(_ field: FolderSortField) -> some View {
        Button {
            sort.toggle(field)
        } label: {
            HStack(spacing: 2) {
                Text(field.title)
                if sort.field == field {
                    Image(systemName: sort.ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct FolderRowView: View {
    let row: FolderBrowserModel.Row
    let model: FolderBrowserModel

    var body: some View {
        HStack(spacing: 6) {
            // Indentation is what says "inside", the way the Finder's list view
            // says it.
            Color.clear.frame(width: CGFloat(row.depth) * 14, height: 1)

            if row.entry.isDirectory {
                DisclosureChevron(isExpanded: model.isExpanded(row.entry.path))
            } else {
                Color.clear.frame(width: 10)
            }

            Image(systemName: row.entry.isDirectory ? "folder.fill" : "doc")
                .font(.system(size: 10))
                .foregroundStyle(MetricKind.disk.color)

            Text(row.entry.name)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Text(row.entry.modifiedAt.map { FolderDateFormatter.string(for: $0) } ?? "—")
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)
                .lineLimit(1)

            // .byteCount renders nothing as "Zero kB", which reads as a fault
            // rather than an empty folder.
            Text(
                row.entry.sizeBytes < 1
                    ? "—"
                    : Int64(row.entry.sizeBytes)
                        .formatted(.byteCount(style: .file))
            )
                .monospacedDigit()
                .frame(width: 58, alignment: .trailing)
        }
        .font(.caption)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard row.entry.isDirectory else { return }
            model.toggle(row.entry.path)
        }
    }
}

/// The Finder's triangle, turning rather than swapping, so opening a folder
/// reads as one movement.
private struct DisclosureChevron: View {
    let isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isExpanded)
            .frame(width: 10)
    }
}
