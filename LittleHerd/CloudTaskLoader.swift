import Foundation
import Observation

/// Reads Codex cloud tasks, occasionally.
///
/// **Deliberately not on the sampler's cadence.** Everything else the herd shows is
/// measured every ten to thirty seconds because it changes that fast; cloud tasks are
/// submitted by hand and finish minutes or hours later, so asking that often would spend
/// a subprocess and a network round trip to redraw the same four rows. Five minutes is
/// still far faster than the thing being watched changes.
///
/// It also fails quietly on purpose. A machine with no Codex, or an account not signed
/// in to the cloud, returns nothing — and nothing is the correct display, because an
/// error row for a feature you do not use is worse than an absent section.
@MainActor
@Observable
final class CloudTaskLoader {
    private(set) var tasks: [CodexCloudTask] = []
    private(set) var lastRead: Date?
    private var task: Task<Void, Never>?

    /// How stale a reading may be before another is worth taking.
    private let interval: TimeInterval = 5 * 60

    /// Reads if the last reading is old enough, and otherwise does nothing.
    ///
    /// Called when the panel appears rather than on a timer, so a herd nobody is looking
    /// at spends nothing at all.
    func refreshIfStale() {
        if let lastRead, Date().timeIntervalSince(lastRead) < interval { return }
        guard task == nil else { return }
        task = Task { [weak self] in
            let output = await Task.detached(priority: .utility) {
                CodexCloudReader.list()
            }.value
            guard let self else { return }
            self.tasks = CodexCloudListParser.parse(output)
            self.lastRead = Date()
            self.task = nil
        }
    }

    /// Sets the tasks directly, for tests and for anything that has already read them.
    /// Reading is a subprocess, which a test should not have to spawn to check placement.
    func adopt(_ tasks: [CodexCloudTask]) {
        self.tasks = tasks
        lastRead = Date()
    }

    /// Each task with the machines that could apply it — the placement decision, which
    /// is the only thing this app contributes to cloud work.
    func placed(
        in herd: [DestinationAccount]
    ) -> [(task: CodexCloudTask, landsOn: [CodexCloudPlacement.Candidate])] {
        tasks.map { task in
            // Candidates rather than names: the row needs to reach the machine and its
            // checkout directory to apply anything, not merely to say its name.
            (task, CodexCloudPlacement.candidates(for: task, in: herd).filter(\.canTake))
        }
    }
}
