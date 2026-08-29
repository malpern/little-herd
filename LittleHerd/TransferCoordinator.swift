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
    /// The commit each transfer departed from, learned while it runs.
    ///
    /// Kept beside the transfer rather than inside it: a `Transfer` is the key
    /// this is all stored under, and a value that changes half way through is
    /// a key that changes half way through.
    private(set) var departures: [Transfer: String] = [:]
    private var rehearsalCount = 0

    init(
        makeRunner: @escaping @MainActor (Transfer) -> SuccessorExecutor.Run
    ) {
        self.makeRunner = makeRunner
    }

    func phase(for transfer: Transfer) -> TransferPhase? { transfers[transfer] }

    func record(departure commit: String, for transfer: Transfer) {
        departures[transfer] = commit
    }

    /// - Parameter steps: what to run, already decided. The coordinator does
    ///   not build these: `SuccessorLaunch` decides whether there is a plan at
    ///   all and `SuccessorRun` turns it into commands, both of them pure, and
    ///   folding either in here would put the refusals somewhere they cannot
    ///   be tested without a machine.
    /// Marks a transfer as under way before the destination has anything to
    /// do. The source's half — quiescing, writing the brief, pushing — happens
    /// first and takes real time, and a drop that shows nothing until the far
    /// machine starts looks like a drop that did nothing.
    func prepare(_ transfer: Transfer) {
        guard transfers[transfer] == nil else { return }
        transfers[transfer] = .preparing
        order.removeAll { $0 == transfer }
        order.insert(transfer, at: 0)
    }

    /// Ends one that never reached the destination.
    func fail(_ transfer: Transfer, _ outcome: SuccessorOutcome) {
        guard transfers[transfer]?.isCancellable == true else { return }
        transfers[transfer] = .finished(outcome)
    }

    func begin(_ transfer: Transfer, steps: [SuccessorRun.Step]) {
        guard tasks[transfer] == nil else { return }

        prepare(transfer)

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
            self?.clearIfNothingToSay(transfer)
        }
    }

    /// Walks a transfer through its phases without touching a machine.
    ///
    /// **Nothing here talks to anything.** No runner, no connection, no
    /// commands — a timer and the same phases the real one reports, so the row
    /// can be watched, read and stopped exactly as it would be. See
    /// `DashboardChrome.rehearsesTransfers`.
    ///
    /// Successive rehearsals end differently on purpose: landing, then a red
    /// check, then an agent that gave up. All three are states the interface
    /// has to say something sensible about, and a rehearsal that always
    /// succeeds only ever shows the easy one.
    func rehearse(_ transfer: Transfer) {
        guard tasks[transfer] == nil else { return }
        prepare(transfer)

        let ending = Self.rehearsalEndings[
            rehearsalCount % Self.rehearsalEndings.count
        ]
        rehearsalCount += 1

        tasks[transfer] = Task { [weak self] in
            for (purpose, pause) in Self.rehearsalScript {
                if Task.isCancelled { break }
                // A run that ends early does not reach its later steps.
                if ending != .landed, purpose == .delivery { continue }
                self?.transfers[transfer] = .running(purpose)
                try? await Task.sleep(for: pause)
            }

            let result: SuccessorOutcome.Result =
                Task.isCancelled ? .cancelled : ending
            self?.transfers[transfer] = .finished(
                SuccessorOutcome(
                    result: result,
                    failingStep: result == .checkFailed ? .verification : nil,
                    output: "Rehearsal — nothing ran."
                )
            )
            self?.tasks[transfer] = nil
            self?.clearIfNothingToSay(transfer)
        }
    }

    private static let rehearsalScript:
        [(SuccessorRun.Step.Purpose, Duration)] = [
            (.worktree, .milliseconds(1100)),
            (.prompt, .milliseconds(600)),
            (.agent, .seconds(5)),
            (.verification, .seconds(4)),
            (.delivery, .milliseconds(900)),
            (.cleanup, .milliseconds(600)),
        ]

    private static let rehearsalEndings: [SuccessorOutcome.Result] = [
        .landed, .checkFailed, .agentFailed,
    ]

    /// Calling one off stops the agent on the other machine too — see
    /// `SSHCommandRunner.runReportingStatus`, where that is measured rather
    /// than assumed. The cleanup steps still run.
    func cancel(_ transfer: Transfer) {
        tasks[transfer]?.cancel()
    }

    /// Takes away a row that has nothing left to tell you.
    ///
    /// **A transfer that worked says so on the card itself** — a tick, a
    /// chime, and the card standing on the machine it moved to — so the strip
    /// repeating it is a line of text asking to be dismissed for no reason.
    /// It goes on its own after a moment.
    ///
    /// A failure stays. The card comes home, which says *that* it did not
    /// work, and the strip is the only place that says *why* — a red check is
    /// a different thing from an agent that gave up, and the difference
    /// decides what you do next. Nobody has to read it, but it should not
    /// disappear before they can.
    private func clearIfNothingToSay(_ transfer: Transfer) {
        guard case .finished(let outcome) = transfers[transfer],
              outcome.result == .landed || outcome.result == .cancelled
        else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1600))
            self?.dismiss(transfer)
        }
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
