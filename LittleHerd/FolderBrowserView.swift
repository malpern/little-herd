import AppKit
import SwiftUI

/// What is taking up a volume, laid out the way the Finder lays it out.
///
/// Column headings that sort, disclosure triangles that open in place, and
/// sizes written the way a person would write them. The one thing it does that
/// the Finder does not is admit how long it is taking: folder sizes are
/// expensive, and a progress bar with a count is more honest than a spinner
/// that could mean anything.
struct FolderBrowserView: View {
    @Environment(\.isRenderingStillImage) private var isRenderingStillImage
    @Bindable var model: FolderBrowserModel
    let path: String
    /// Passed down to the rows so a right-click can offer the Finder only when
    /// the Finder could actually find it. See `FolderRowView.isLocal`.
    var isLocal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch model.scanAvailability {
            case .needsFullDiskAccess:
                permissionRequest
            case .unsupported:
                Text("This machine can\u{2019}t report folder sizes.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            case .available:
                if let scan = model.scan(for: path) {
                    status(for: scan)
                }
                rows
            }
        }
    }

    /// Asked once, in one place, with the remedy attached.
    ///
    /// The alternative is what this replaced: walking the disk and letting
    /// macOS raise a dialog for Photos, then iCloud Drive, then Documents,
    /// then Downloads — a permission interview conducted one folder at a time,
    /// in the middle of answering a different question.
    private var permissionRequest: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Little Herd needs Full Disk Access to measure this Mac.")
                .font(.caption)
            Text("Reading what fills a disk means reading all of it, including Photos, iCloud Drive and Documents. Other machines are measured over SSH and need nothing.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Open Settings\u{2026}") { FullDiskAccess.openSettings() }
                    .buttonStyle(.link)
                Text("then reopen this volume")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2)
        }
        .padding(.vertical, 6)
        .padding(.trailing, 8)
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
                // **A `.link` button is one of the styles `ImageRenderer`
                // cannot flatten**, and it paints a yellow square with a red
                // no-entry sign in its place — the same placeholder that had
                // the whole herd rendering yellow until the menus were taught
                // to stand aside. The flag's own note says anything else with
                // a representable underneath has to read it too; this is the
                // second thing that does.
                if isRenderingStillImage {
                    Text("Refresh")
                } else {
                    Button("Refresh") { model.refresh(path) }
                        .buttonStyle(.link)
                }
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
                FolderRowView(row: row, model: model, isLocal: isLocal)
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
    /// Whether these paths are on the Mac this app is running on.
    ///
    /// **The Finder can only open what is here.** Every other machine in the
    /// herd is measured over SSH, and a path from the mini either does not
    /// exist on this Mac or — worse — exists and is something else entirely.
    /// Revealing the wrong folder with the right name is the kind of wrong
    /// answer that gets believed, so the item is absent rather than broken.
    let isLocal: Bool

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

            // **Truncating at the end, not the middle.** Middle truncation is
            // right when both ends identify a thing — a path does — and wrong
            // for a single name, where the front is what you read: with the
            // date column gone these fit anyway, and when one does not,
            // "Application Sup…" beats "Ap…ort".
            Text(row.entry.name)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            // .byteCount renders nothing as "Zero kB", which reads as a fault
            // rather than an empty folder.
            Text(
                row.entry.sizeBytes < 1
                    ? "—"
                    : HerdByteCount.storage(Int64(row.entry.sizeBytes))
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
        // **SwiftUI's own `.contextMenu`, deliberately, and not this project's
        // `AppKitContextMenu`.** That one exists because `NSMenuItem` can draw
        // an image where SwiftUI drops it — and it is hosted in an overlay,
        // which has twice now swallowed the events of whatever it covers: the
        // herd lost its click that way, and an agent card its tooltip. These
        // items carry no icons, so none of that is worth paying for, and the
        // row underneath keeps the tap that opens it.
        .contextMenu {
            if isLocal {
                Button("Open in Finder") {
                    // Selecting rather than opening: for a folder this reveals
                    // it inside its parent with the folder highlighted, which
                    // is what "where is this?" means, and for a file it is the
                    // only sensible answer.
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: row.entry.path)]
                    )
                }
            }
            Button("Copy Path") {
                // Always offered, because it is the one thing that is useful
                // whichever machine this is: a path from the mini is what you
                // paste after `ssh mini`.
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.entry.path, forType: .string)
            }
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
