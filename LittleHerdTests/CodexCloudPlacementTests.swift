import Foundation
import Testing

@testable import LittleHerd

/// Which machine a cloud task could land on — the one question the vendors do not answer.
@Suite("Placing cloud work")
struct CodexCloudPlacementTests {
    private func account(_ name: String, checkouts: [String: String]) -> DestinationAccount {
        DestinationAccount(
            machine: MachineID(name), name: name, symbolName: "desktopcomputer",
            report: DestinationReport(installations: [], checkouts: checkouts),
            mayHostSessions: true, auth: .unverified, isVerifying: false
        )
    }
    private func task(repository: String) -> CodexCloudTask {
        CodexCloudTask(
            id: "t1", url: "https://chatgpt.com/codex/tasks/t1", status: .ready,
            title: "Some work", repository: repository, when: "Mar 29 08:55", diff: .none
        )
    }

    /// A task says `malpern/KeyPath`; the probe keys checkouts by the origin remote's
    /// last component. Joining them on that is the placement.
    @Test
    func atasksRepositoryJoinsToAcheckoutSlug() {
        #expect(task(repository: "malpern/KeyPath").repositorySlug == "KeyPath")
        // A bare name is already the slug.
        #expect(task(repository: "KeyPath").repositorySlug == "KeyPath")
    }

    /// **Every machine is reported, not only the ones that can take it.** "Nowhere can
    /// take this" is an answer a person needs, and a list that omits the machines is one
    /// they cannot check.
    @Test
    func machinesWithTheCheckoutCanTakeItAndTheRestAreStillListed() {
        let herd = [
            account("Air", checkouts: ["KeyPath": "/Users/a/local-code/KeyPath"]),
            account("Mini", checkouts: ["KeyPath": "/Users/m/local-code/KeyPath"]),
            account("Linux", checkouts: ["little-herd": "/home/m/local-code/little-herd"]),
        ]
        let candidates = CodexCloudPlacement.candidates(for: task(repository: "malpern/KeyPath"), in: herd)
        #expect(candidates.count == 3, "all three machines are accounted for")
        #expect(candidates.filter(\.canTake).map(\.machine) == ["Air", "Mini"])
        #expect(candidates.first?.directory == "/Users/a/local-code/KeyPath")
        #expect(candidates.last?.canTake == false)
    }

    /// The repository name comes from a URL on one machine and from the vendor on the
    /// other; a difference of case is not worth failing a placement over.
    @Test
    func thematchIgnoresCase() {
        let herd = [account("Air", checkouts: ["keypath": "/Users/a/keypath"])]
        #expect(CodexCloudPlacement.candidates(
            for: task(repository: "malpern/KeyPath"), in: herd).first?.canTake == true)
    }

    /// A machine that has not answered has no checkouts, and that is "cannot take it"
    /// rather than a crash.
    @Test
    func amachineThatNeverAnsweredSimplyCannotTakeIt() {
        let silent = DestinationAccount(
            machine: MachineID("x"), name: "Asleep", symbolName: "desktopcomputer",
            report: nil, mayHostSessions: true, auth: .unverified, isVerifying: false)
        #expect(CodexCloudPlacement.candidates(
            for: task(repository: "a/b"), in: [silent]).first?.canTake == false)
    }

    // MARK: - What the command prints

    /// **The asymmetry is stated, not hidden.** Claude cloud cannot be enumerated from
    /// here, so the output says so rather than showing an empty table that would read as
    /// "you have no Claude cloud work".
    @Test
    func theclaudeAsymmetryIsAlwaysSaid() {
        let herd = [account("Air", checkouts: [:])]
        #expect(HerdCommand.cloud(tasks: [], herd: herd, json: false).contains("cannot be listed"))
        #expect(HerdCommand.cloud(tasks: [task(repository: "a/b")], herd: herd, json: false)
            .contains("cannot be listed"))
    }

    /// When nothing can take it, the slug is named — that is the actionable half, since
    /// it says what to clone.
    @Test
    func nowhereToApplyNamesTheRepositoryToClone() {
        let herd = [account("Air", checkouts: ["other": "/x"])]
        let text = HerdCommand.cloud(tasks: [task(repository: "malpern/KeyPath")], herd: herd, json: false)
        #expect(text.contains("nowhere to apply it"))
        #expect(text.contains("KeyPath"))
    }

    @Test
    func thejsonCarriesThePlacement() throws {
        let herd = [
            account("Air", checkouts: ["KeyPath": "/x"]),
            account("Linux", checkouts: [:]),
        ]
        let json = HerdCommand.cloud(tasks: [task(repository: "malpern/KeyPath")], herd: herd, json: true)
        let rows = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: String]]
        #expect(rows?.first?["can_land_on"] == "Air")
        #expect(rows?.first?["repository"] == "malpern/KeyPath")
    }
}

/// The loader that feeds the panel.
@Suite("Loading cloud work for the panel")
@MainActor
struct CloudTaskLoaderTests {
    /// **A herd with no cloud work draws no section**, which is the ordinary case on a
    /// machine without Codex and must not look like a failure.
    @Test
    func nothingReadMeansNothingToPlace() {
        #expect(CloudTaskLoader().placed(in: []).isEmpty)
    }

    /// Placement is computed against the herd at the moment of drawing, not stored with
    /// the task — a machine that gains the checkout should start being offered without
    /// the cloud being read again.
    @Test
    func placementFollowsTheHerdRatherThanTheReading() {
        let loader = CloudTaskLoader()
        // Reading is a subprocess, so the tasks are set the way the parser would.
        loader.adopt(CodexCloudListParser.parse("""
            https://chatgpt.com/codex/tasks/t1
              [READY] Some work
              malpern/KeyPath  •  Mar 29 08:55
              no diff
            """))

        func herd(_ checkouts: [String: String]) -> [DestinationAccount] {
            [DestinationAccount(
                machine: MachineID("a"), name: "Air", symbolName: "desktopcomputer",
                report: DestinationReport(installations: [], checkouts: checkouts),
                mayHostSessions: true, auth: .unverified, isVerifying: false)]
        }
        #expect(loader.placed(in: herd([:])).first?.landsOn.isEmpty == true)
        #expect(loader.placed(in: herd(["KeyPath": "/x"])).first?.landsOn.map(\.machine) == ["Air"])
    }
}

/// The command that actually reaches a machine.
@Suite("Applying a cloud task")
struct CodexCloudApplyTests {
    private func task(_ id: String) -> CodexCloudTask {
        CodexCloudTask(
            id: id, url: "https://chatgpt.com/codex/tasks/\(id)", status: .ready,
            title: "Some work", repository: "malpern/KeyPath", when: "Mar 29", diff: .none)
    }

    /// **The vendor's own command, in the checkout the placement chose.** Little Herd
    /// decides which machine and then gets out of the way — it never applies a diff
    /// itself, which is item 9's rule about native vehicles.
    @Test
    func itrunsCodexOwnCommandInTheChosenCheckout() {
        let command = task("task_e_123").applyCommand(in: "/Users/m/local-code/KeyPath")
        #expect(command == "cd '/Users/m/local-code/KeyPath' && codex cloud apply 'task_e_123'")
    }

    /// A directory with a space in it is one argument. This herd has such a path, so it
    /// is not hypothetical.
    @Test
    func pathsAndIdsAreQuoted() {
        let command = task("t 1").applyCommand(in: "/Users/m/Some Folder/KeyPath")
        #expect(command.contains("'/Users/m/Some Folder/KeyPath'"))
        #expect(command.contains("'t 1'"))
    }

    /// **Nothing is applied where nothing can be.** A candidate without a directory is
    /// a machine that lacks the checkout, and offering it would be offering a command
    /// with nowhere to run.
    @Test
    func acandidateWithoutAcheckoutCannotBeApplied() {
        let candidate = CodexCloudPlacement.Candidate(
            machine: "Linux", id: MachineID("linux"), directory: nil)
        #expect(!candidate.canTake)
    }
}
