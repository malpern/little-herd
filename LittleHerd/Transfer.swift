import Foundation

/// One transfer, from the moment it is asked for to the moment it is over.
///
/// A drag is a gesture; this is the thing the gesture asks for, and it is a
/// value so that the interface has something to show when nobody is dragging
/// any more. The window a transfer runs in is longer than the gesture that
/// starts it by a factor of thousands.
nonisolated struct Transfer: Hashable, Sendable {
    let origin: MachineID
    let destination: MachineID
    /// The branch carrying the brief and any work in progress.
    let branch: String
    /// What the source pushed, which the destination must find. See
    /// `SuccessorLaunch.plan`.
    let commit: String
    /// What the session was called, for the interface to say.
    let title: String
}

/// Where a transfer has got to.
///
/// Named for what a person would ask — "has it started", "what is it doing",
/// "did it work" — rather than for the step index, because the interface shows
/// this and the steps are an implementation detail that changes.
nonisolated enum TransferPhase: Equatable, Sendable {
    /// Asked for, nothing sent yet: the source is still quiescing the session
    /// and writing down what it was doing.
    case preparing
    /// Running on the destination, at this step.
    case running(SuccessorRun.Step.Purpose)
    /// Over, one way or another.
    case finished(SuccessorOutcome)

    /// Whether calling it off is still meaningful.
    var isCancellable: Bool {
        switch self {
        case .preparing, .running: true
        case .finished: false
        }
    }

    /// What to say about it in one line.
    var summary: String {
        switch self {
        case .preparing: "Writing down where it got to"
        case .running(.worktree): "Fetching the branch"
        case .running(.prompt): "Handing over the brief"
        case .running(.agent): "Working"
        case .running(.verification): "Running the tests"
        case .running(.delivery): "Pushing the result"
        case .running(.cleanup): "Tidying up"
        case .finished(let outcome):
            switch outcome.result {
            case .landed: "Done — on the branch"
            case .checkFailed: "Tests failed — edits are on the branch"
            case .agentFailed: "The agent stopped"
            case .couldNotStart: "Couldn’t start"
            case .cancelled: "Called off"
            }
        }
    }

    /// Whether this needs a person to look at it. A red run is not an error
    /// message to be dismissed — it is work waiting to be read.
    var wantsAttention: Bool {
        switch self {
        case .preparing, .running: false
        case .finished(let outcome):
            switch outcome.result {
            case .landed, .checkFailed, .agentFailed, .couldNotStart: true
            case .cancelled: false
            }
        }
    }
}
