import Foundation
import Testing

@testable import LittleHerd

/// A real transfer, air → mini, driven by hand. **Not part of the suite.**
///
/// This is the run item 3 has been asking for since August: the machinery has
/// been exercised piece by piece and by a scripted spike, and has never gone
/// source → destination → branch from the app's own code paths. It is a test
/// only because that is the cheapest way to call internal API with real
/// runners; it talks to real machines, spends real tokens, and pushes a real
/// branch, so it is filtered out of every ordinary run by living in its own
/// suite and being invoked explicitly.
///
/// The gesture is not covered here — `endDrag` reporting an accepted drop has
/// its own tests. Everything after it is.
/// **Gated on an environment variable, not `.disabled`,** so it can still be
/// asked for by name. Without the gate an ordinary `xcodebuild test` — CI's
/// included — would ssh to somebody's mini and spend tokens.
///
/// Run it with:
///     LITTLE_HERD_LIVE=1 xcodebuild test -scheme LittleHerd \
///       -destination 'platform=macOS' -only-testing:LittleHerdTests/LiveTransferHarness
@Suite(
    "Live transfer",
    .enabled(if: ProcessInfo.processInfo.environment["LITTLE_HERD_LIVE"] == "1")
)
struct LiveTransferHarness {
    static let worktree =
        "/Users/malpern/local-code/little-herd/.claude/worktrees/destination-eligibility-18b608"
    static let checkout = "/Users/malpern/local-code/little-herd"
    static let sessionID = "c6df5704-0451-4806-af9c-fc4cd9e79121"

    private func account(
        _ id: String,
        checkout: String,
        agent: String
    ) -> DestinationAccount {
        DestinationAccount(
            machine: MachineID(id),
            name: id,
            symbolName: "desktopcomputer",
            report: DestinationReport(
                installations: [
                    AgentInstallation(provider: .claude, version: "live", path: agent)
                ],
                checkouts: ["little-herd": checkout]
            ),
            mayHostSessions: true,
            auth: .unverified,
            isVerifying: false
        )
    }

    @Test
    func moveASessionFromThisMacToTheMini() async throws {
        let session = AgentSession(
            id: Self.sessionID,
            provider: .claude,
            projectName: "Little Herd",
            state: .waiting,
            updatedAt: .now,
            progress: nil,
            title: "Live transfer probe",
            workingDirectory: Self.worktree
        )

        let herd = [
            account("local", checkout: Self.checkout,
                    agent: "\(NSHomeDirectory())/.local/bin/claude"),
            account("mac mini/malpern", checkout: Self.checkout,
                    agent: "/Users/malpern/.local/bin/claude"),
        ]

        let assembled = TransferAssembly.request(
            session: session,
            from: MachineID("local"),
            to: MachineID("mac mini/malpern"),
            in: herd,
            check: TransferAssembly.check
        )
        guard case .success(let request) = assembled else {
            Issue.record("assembly refused: \(assembled)")
            return
        }
        print("=== BRANCH \(request.transfer.branch)")
        print("=== REPOSITORY \(request.transfer.repository)")

        // The source's half, on this Mac, through the runner built today.
        // Wrapped so every step is visible: a departure that fails in three
        // seconds has failed before the agent, and which command it was is the
        // whole question.
        let inner = SuccessorLocal.departureRunner()
        let departed = await TransferPilot.depart(
            steps: request.departure,
            run: { step in
                print("=== DEPART \(step.purpose) :: \(step.command.prefix(220))")
                let out = await inner(step)
                print("===   -> ok=\(out.succeeded) :: \(out.text.prefix(400))")
                return out
            }
        )
        guard case .success(let commit) = departed else {
            print("=== DEPARTURE FAILED \(departed)")
            Issue.record("departure failed")
            return
        }
        print("=== DEPARTED \(commit)")

        let arrival = TransferPilot.arrival(
            commit: commit,
            briefPath: request.briefPath,
            briefText: "",
            branch: request.transfer.branch,
            repository: request.destinationRepository,
            scratchRoot: "/Users/malpern/.little-herd/transfers",
            provider: request.provider,
            reportedAgentPath: request.destinationAgentPath,
            check: request.check,
            commitMessage: "Successor work on \(request.transfer.branch)"
        )
        guard case .success(let steps) = arrival else {
            Issue.record("arrival refused: \(arrival)")
            return
        }

        let remote = SuccessorSSH.runner(host: "malpern@mini")
        let outcome = await SuccessorExecutor.execute(
            steps: steps,
            run: { step in
                print("=== ARRIVE \(step.purpose) :: \(step.command.prefix(200))")
                let out = await remote(step)
                print("===   -> ok=\(out.succeeded) :: \(out.text.suffix(600))")
                return out
            },
            progress: { purpose in print("=== STEP \(purpose)") }
        )

        print("=== RESULT \(outcome.result)")
        print("=== FAILING STEP \(String(describing: outcome.failingStep))")
        print("=== REMNANT \(outcome.remnant)")
        print("=== OUTPUT ---------------------------------------")
        print(outcome.output.suffix(3000))
        print("=== END ------------------------------------------")
    }
}
