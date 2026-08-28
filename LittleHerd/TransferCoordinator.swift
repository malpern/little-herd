import Foundation
import Observation

/// Owns the transfers in flight, and outlives the drag that started them.
///
/// On the main actor because the interface reads it continuously, and because
/// a transfer's whole job is to be *visible* — a machine quietly doing work
/// you cannot see is the thing this app exists not to be.
@MainActor
@Observable
final class TransferCoordinator {
    /// In flight and recently finished, newest first. Finished ones stay until
    /// they are dismissed: a transfer that ended while the panel was closed
    /// must still be there when it is opened, or a red run is lost silently.
    private(set) var transfers: [Transfer: TransferPhase] = [:]
    private(set) var order: [Transfer] = []

    /// Injected so tests can drive a whole transfer without a second Mac, and
    /// so the executor stays the only thing that knows about ordering.
    private let makeRunner: @MainActor (Transfer) -> SuccessorExecutor.Run
    private var tasks: [Transfer: Task<Void, Never>] = [:]

    init(
        makeRunner: @escaping @MainActor (Transfer) -> SuccessorExecutor.Run
    ) {
        self.makeRunner = makeRunner
    }

    func phase(for transfer: Transfer) -> TransferPhase? { transfers[transfer] }

    /// - Parameter steps: what to run, already decided. The coordinator does
    ///   not build these: `SuccessorLaunch` decides whether there is a plan at
    ///   all and `SuccessorRun` turns it into commands, both of them pure, and
    ///   folding either in here would put the refusals somewhere they cannot
    ///   be tested without a machine.
    func begin(_ transfer: Transfer, steps: [SuccessorRun.Step]) {
        guard tasks[transfer] == nil else { return }

        transfers[transfer] = .preparing
        order.removeAll { $0 == transfer }
        order.insert(transfer, at: 0)

        let run = makeRunner(transfer)
        tasks[transfer] = Task { [weak self] in
            let outcome = await SuccessorExecutor.execute(
                steps: steps,
                run: run,
                progress: { purpose in
                    await MainActor.run {
                        // A finished transfer must not be walked backwards by
                        // the cleanup step reporting itself afterwards.
                        guard self?.transfers[transfer]?.isCancellable == true
                        else { return }
                        self?.transfers[transfer] = .running(purpose)
                    }
                }
            )
            self?.transfers[transfer] = .finished(outcome)
            self?.tasks[transfer] = nil
        }
    }

    /// Calling one off stops the agent on the other machine too — see
    /// `SSHCommandRunner.runReportingStatus`, where that is measured rather
    /// than assumed. The cleanup steps still run.
    func cancel(_ transfer: Transfer) {
        tasks[transfer]?.cancel()
    }

    /// Only once somebody has seen it.
    func dismiss(_ transfer: Transfer) {
        guard transfers[transfer]?.isCancellable == false else { return }
        transfers[transfer] = nil
        order.removeAll { $0 == transfer }
    }

    /// Anything a person has not looked at yet, for the badge.
    var needingAttention: [Transfer] {
        order.filter { transfers[$0]?.wantsAttention == true }
    }
}
