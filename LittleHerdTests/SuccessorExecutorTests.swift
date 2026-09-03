import Foundation
import Testing

@testable import LittleHerd

@Suite("Successor executor")
struct SuccessorExecutorTests {
    private func steps() -> [SuccessorRun.Step] {
        SuccessorRun.steps(
            plan: SuccessorLaunch.Plan(
                expectedCommit: String(repeating: "a", count: 40),
                workingDirectory: "/tmp/herd/work",
                executable: "/Users/malpern/.local/bin/claude",
                arguments: ["-p"],
                prompt: "do the thing"
            ),
            repository: "/repo",
            branch: "transfer/x",
            promptFile: "/tmp/herd/prompt",
            check: .xcode(scheme: "LittleHerd"),
            commitMessage: "m"
        )
    }

    /// Records what actually ran, which is the whole question.
    nonisolated private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [SuccessorRun.Step.Purpose] = []

        func note(_ purpose: SuccessorRun.Step.Purpose) {
            lock.lock()
            storage.append(purpose)
            lock.unlock()
        }

        var ran: [SuccessorRun.Step.Purpose] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    @Test
    func aCleanRunLands() async {
        let outcome = await SuccessorExecutor.execute(steps: steps()) { _ in
            .init(text: "", succeeded: true)
        }
        #expect(outcome.result == .landed)
        #expect(outcome.failingStep == nil)
    }

    /// **A failed check must not be followed by a push, and must still be
    /// tidied up.** Both halves matter: stopping early is the safety property,
    /// and cleaning up anyway is the one that keeps other people's machines
    /// free of abandoned worktrees.
    @Test
    func aFailedCheckStopsTheRunButNotTheCleanup() async {
        let recorder = Recorder()
        let outcome = await SuccessorExecutor.execute(steps: steps()) { step in
            recorder.note(step.purpose)
            return .init(
                text: step.purpose == .verification ? "2 tests failed" : "",
                succeeded: step.purpose != .verification
            )
        }

        #expect(outcome.result == .checkFailed)
        #expect(outcome.failingStep == .verification)
        #expect(outcome.output.contains("2 tests failed"))
        #expect(!recorder.ran.contains(.delivery))
        #expect(recorder.ran.contains(.cleanup))
    }

    /// An agent that gives up is different news from a red suite, and the
    /// interface needs to be able to tell them apart.
    @Test
    func anAgentFailureIsNotACheckFailure() async {
        let recorder = Recorder()
        let outcome = await SuccessorExecutor.execute(steps: steps()) { step in
            recorder.note(step.purpose)
            return .init(text: "", succeeded: step.purpose != .agent)
        }

        #expect(outcome.result == .agentFailed)
        #expect(!recorder.ran.contains(.verification))
        #expect(recorder.ran.contains(.cleanup))
    }

    /// Nothing to work on is its own answer, and it never reaches the agent.
    @Test
    func aMissingWorktreeNeverStartsTheAgent() async {
        let recorder = Recorder()
        let outcome = await SuccessorExecutor.execute(steps: steps()) { step in
            recorder.note(step.purpose)
            return .init(
                text: "fatal: couldn't find remote ref",
                succeeded: step.purpose != .worktree
            )
        }

        #expect(outcome.result == .couldNotStart)
        #expect(!recorder.ran.contains(.agent))
        #expect(recorder.ran.contains(.cleanup))
    }

    /// Calling one off must not leave the worktree behind either.
    @Test
    func cancellationStillCleansUp() async {
        let recorder = Recorder()
        let task = Task {
            await SuccessorExecutor.execute(steps: steps()) { step in
                recorder.note(step.purpose)
                return .init(text: "", succeeded: true)
            }
        }
        task.cancel()
        let outcome = await task.value

        #expect(outcome.result == .cancelled)
        #expect(recorder.ran.contains(.cleanup))
        #expect(!recorder.ran.contains(.delivery))
    }
}
