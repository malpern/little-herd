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
    /// What the session was called, for the interface to say.
    let title: String
    /// Where the work came from, so its result can be read back there. The
    /// source machine has the repository and is where somebody is sitting;
    /// reading the diff there means the destination may be asleep by the time
    /// anybody looks.
    let repository: String
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

    /// How far along, from nought to one.
    ///
    /// **Weighted by how long each step actually takes, not by how many there
    /// are.** Six equal segments would put the bar at a third while the agent
    /// works — which is most of the transfer, sometimes half an hour of it —
    /// and then run through the last four in a couple of seconds. A bar that
    /// stands still for thirty minutes and then leaps is worse than no bar:
    /// it looks stuck at exactly the moment the thing is working hardest.
    ///
    /// The weights are rough on purpose. What has to be right is the shape —
    /// most of the width belongs to the agent and the tests, and the
    /// bookkeeping either side is a sliver.
    var progress: Double {
        switch self {
        case .preparing: 0.04
        case .running(let purpose):
            switch purpose {
            case .worktree: 0.10
            case .prompt: 0.14
            case .agent: 0.60
            case .verification: 0.88
            case .delivery: 0.96
            case .cleanup: 0.99
            }
        case .finished: 1
        }
    }

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
            // **Short enough for one line.** These sat beside two machine
            // names in a 324-point window and the useful half — "edits are on
            // the branch" — was the half that got truncated away. What
            // happened to the work belongs where there is room to say it.
            case .landed: "Done"
            case .checkFailed: "Tests failed"
            case .agentFailed: "Agent stopped"
            case .couldNotStart: "Couldn’t start"
            case .cancelled: "Stopped"
            }
        }
    }

    /// The longer version, for somewhere with room for it — what actually
    /// became of the work, which is the part a person needs and the strip has
    /// no space for.
    var detail: String {
        switch self {
        case .preparing:
            "Asking the session to write down where it got to."
        case .running(let purpose):
            switch purpose {
            case .worktree: "Fetching the branch on the destination."
            case .prompt: "Handing over the brief."
            case .agent: "The agent is working on it."
            case .verification: "Running the tests on the destination."
            case .delivery: "Pushing the result to the branch."
            case .cleanup: "Tidying up the destination."
            }
        case .finished(let outcome):
            switch outcome.result {
            case .landed:
                "The work is on the branch, tested, and not merged."
            case .checkFailed:
                // `checkFailed` covers a failed push as well as a failed
                // check — deliberately, rather than inventing a fifth result
                // for a state that leaves you in the same place. But the
                // sentence has to be true of whichever it was: saying "the
                // tests did not pass" after they passed and the push failed is
                // the same confident wrong answer `couldNotStart` used to give,
                // and it was seen on a real transfer.
                outcome.failingStep == .delivery
                    ? "The tests passed, but the result could not be pushed. "
                        + "The work is on the destination and not on the branch."
                    : "The tests did not pass. The edits are still on the branch, "
                        + "unchanged, for you to read."
            case .agentFailed:
                // It used to end "Nothing was pushed", which is false: the
                // departure pushed the branch before the agent was asked for
                // anything. What is true is that the agent added nothing to
                // it, and a person reading the first version would not have
                // gone looking for the branch that is sitting right there.
                "The agent stopped before finishing. The branch holds what "
                    + "was sent to it and nothing the agent wrote."
            case .couldNotStart:
                // Three different states wore one sentence, and it was the
                // sentence for the rarest of them. The other two leave work
                // on a branch, and the diff window prints this line directly
                // above that branch's name.
                switch outcome.remnant {
                case .nothing:
                    "It never started, so nothing was changed anywhere."
                case .localBranch:
                    "It never started. Your work was gathered onto the branch "
                        + "on the machine it came from, and not sent anywhere."
                case .pushedBranch:
                    "It never reached the other machine. Your work is on the "
                        + "branch, exactly as it left."
                }
            case .cancelled:
                "You called it off. Anything already written is on the branch."
            }
        }
    }

    /// Whether there is a branch to go and look at.
    ///
    /// The session you started with is untouched in every one of these cases —
    /// nothing in a transfer retires the source — so this is the only part of
    /// "where you were left" that varies, and the only part worth drawing.
    ///
    /// `preparing` is the departure itself, which is what builds the branch,
    /// so during it there may not be one. **Every `running` phase has one**:
    /// the run does not begin until a commit has been pushed, which is the
    /// same fact that lets `SuccessorOutcome.remnant` default to
    /// `.pushedBranch`.
    var leftABranch: Bool {
        switch self {
        case .preparing: false
        case .running: true
        case .finished(let outcome): outcome.remnant != .nothing
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
