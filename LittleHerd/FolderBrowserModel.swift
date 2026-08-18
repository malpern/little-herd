import Foundation
import Observation

/// What the folder view is showing, and what it is still finding out.
///
/// Rows are kept flat rather than as a tree of nested views. The list is a
/// single scrolling column either way, and flattening means expanding a folder
/// deep in the list does not rebuild every view above it — which is what makes
/// opening a row feel instant rather than merely fast.
@MainActor
@Observable
final class FolderBrowserModel {
    /// One line of the list: an entry, and how deep it sits.
    nonisolated struct Row: Identifiable, Equatable, Sendable {
        let entry: FolderEntry
        let depth: Int

        var id: String { entry.path }
    }

    private(set) var scans: [String: FolderScan] = [:]
    private(set) var expanded: Set<String> = []
    var sort = FolderSort() {
        didSet { rebuildRows() }
    }
    private(set) var rows: [Row] = []

    @ObservationIgnored
    private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored
    private let store: FolderSizeStore
    @ObservationIgnored
    private let machine: MachineID
    @ObservationIgnored
    private let scanner: FolderSizeScanner?
    @ObservationIgnored
    private var root: String?

    init(machine: MachineID, scanner: FolderSizeScanner?, store: FolderSizeStore) {
        self.machine = machine
        self.scanner = scanner
        self.store = store
    }

    /// Whether this machine can answer at all. A NAS reached through DSM
    /// cannot — see `FolderSizeScanner` — and saying so plainly beats offering
    /// a control that does nothing.
    var canMeasure: Bool { scanner != nil }

    func isExpanded(_ path: String) -> Bool { expanded.contains(path) }

    func scan(for path: String) -> FolderScan? { scans[path] }

    // MARK: - Opening and closing

    func toggle(_ path: String, isRoot: Bool = false) {
        if isRoot { root = path }
        if expanded.contains(path) {
            collapse(path)
        } else {
            expand(path)
        }
    }

    private func expand(_ path: String) {
        expanded.insert(path)

        // A folder measured before — this session or a previous one — opens
        // with its numbers already there. The whole point of writing them down.
        if scans[path] == nil, let remembered = store.scan(machine: machine, path: path) {
            scans[path] = FolderScan(
                path: path,
                entries: remembered.entries,
                state: .done(measuredAt: remembered.measuredAt)
            )
        }
        if scans[path] == nil {
            measure(path)
        }
        rebuildRows()
    }

    private func collapse(_ path: String) {
        expanded.remove(path)
        // Closing a folder abandons the work: the answer was wanted for
        // something now out of sight, and a scan nobody is watching is just
        // load on a machine.
        if scans[path]?.state.isRunning == true {
            tasks[path]?.cancel()
            tasks[path] = nil
            scans[path] = nil
        }
        // Anything nested inside closes with it, so reopening does not reveal
        // a tree someone left open three levels down.
        expanded = expanded.filter { !$0.hasPrefix(path + "/") }
        rebuildRows()
    }

    func refresh(_ path: String) {
        tasks[path]?.cancel()
        scans[path] = nil
        measure(path)
        rebuildRows()
    }

    // MARK: - Measuring

    private func measure(_ path: String) {
        guard let scanner else {
            scans[path] = FolderScan(path: path, state: .failed(
                FolderScanError.unsupported.localizedDescription
            ))
            return
        }

        scans[path] = FolderScan(path: path, state: .listing)
        tasks[path] = Task { [weak self, machine, store] in
            let selfRef = self
            do {
                // The progress callback arrives off the main actor, so it hops
                // back rather than touching the model where it lands.
                let entries = try await scanner.scan(path: path) { partial, progress in
                    Task { @MainActor in
                        guard let model = selfRef, model.expanded.contains(path) else { return }
                        model.scans[path] = FolderScan(
                            path: path,
                            entries: partial,
                            state: .measuring(progress)
                        )
                        model.rebuildRows()
                    }
                }
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    let measuredAt = Date()
                    self.scans[path] = FolderScan(
                        path: path,
                        entries: entries,
                        state: .done(measuredAt: measuredAt)
                    )
                    store.record(entries, machine: machine, path: path, measuredAt: measuredAt)
                    self.tasks[path] = nil
                    self.rebuildRows()
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    self?.scans[path]?.state = .cancelled
                    self?.rebuildRows()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.scans[path] = FolderScan(
                        path: path,
                        state: .failed(error.localizedDescription)
                    )
                    self?.rebuildRows()
                }
            }
        }
    }

    // MARK: - Rows

    private func rebuildRows() {
        guard let root else {
            rows = []
            return
        }
        rows = flattened(path: root, depth: 0)
    }

    private func flattened(path: String, depth: Int) -> [Row] {
        guard expanded.contains(path), let scan = scans[path] else { return [] }
        return sort.sorted(scan.entries).flatMap { entry -> [Row] in
            [Row(entry: entry, depth: depth)]
                + (entry.isDirectory ? flattened(path: entry.path, depth: depth + 1) : [])
        }
    }
}
