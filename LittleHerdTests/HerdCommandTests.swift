import Foundation
import Testing

@testable import LittleHerd

/// Little Herd answering a question from a shell.
@Suite("Command line")
struct HerdCommandTests {
    // MARK: - What must never happen

    /// **The app has to keep launching.** This code runs on every start,
    /// including the ones Launch Services and Xcode begin with arguments of
    /// their own, and treating one of those as an unknown verb would exit
    /// instead of opening — the entire app failing for the sake of a feature
    /// nobody invoked at that moment.
    @Test
    func theSystemsOwnArgumentsAreNotVerbs() {
        let launches = [
            ["/path/Little Herd"],
            ["/path/Little Herd", "-psn_0_1234567"],
            ["/path/Little Herd", "-NSDocumentRevisionsDebugMode", "YES"],
            ["/path/Little Herd", "-AppleLanguages", "(en)"],
        ]
        for arguments in launches {
            #expect(
                HerdCommand.disposition(for: arguments) == .launchTheApp,
                "\(arguments) should have started the app"
            )
        }
    }

    /// A word that is not a verb is an error rather than a silent launch: it
    /// means somebody typed a command and got an application.
    @Test
    func anUnknownVerbIsAnErrorAndSaysSo() {
        guard case .respond(let output, let code) =
            HerdCommand.disposition(for: ["little-herd", "wibble"])
        else {
            Issue.record("expected a response")
            return
        }
        #expect(code == 1)
        #expect(output.contains("wibble"))
        #expect(output.contains("usage:"))
    }

    @Test
    func helpIsNotAnError() {
        #expect(
            HerdCommand.disposition(for: ["little-herd", "help"])
                == .respond(output: HerdCommand.usage, code: 0)
        )
    }

    // MARK: - The herd, as configured

    private func machine(
        _ id: String,
        name: String,
        host: String,
        connection: MachineConnection,
        user: String? = nil
    ) -> MachineConfiguration {
        MachineConfiguration(
            id: MachineID(id),
            name: name,
            shortName: name,
            hostname: host,
            hardwareSummary: "",
            platform: .macOS,
            connection: connection,
            avatar: .calfMini,
            identityFile: nil,
            sshUser: user,
            serverNames: [],
            supportsGPU: false
        )
    }

    private var herd: [MachineConfiguration] {
        [
            machine("local", name: "Air", host: "localhost", connection: .local),
            machine(
                "mac mini/malpern",
                name: "Mac mini",
                host: "mini",
                connection: .ssh,
                user: "malpern"
            ),
        ]
    }

    @Test
    func aRemoteMachineShowsTheAccountItIsReadAs() {
        let text = HerdCommand.machines(herd, json: false)
        #expect(text.contains("malpern@mini"))
        // The local machine has no address worth printing — "localhost" would
        // be true and useless.
        #expect(text.contains("this Mac"))
        #expect(!text.contains("localhost"))
    }

    @Test
    func theJSONCarriesTheAccountSeparately() {
        let json = HerdCommand.machines(herd, json: true)
        #expect(json.contains("\"user\": \"malpern\""))
        #expect(json.contains("\"hostname\": \"mini\""))
        #expect(json.contains("\"local\": \"true\""))
    }

    @Test
    func anEmptyHerdSaysSoRatherThanPrintingNothing() {
        #expect(HerdCommand.machines([], json: false) == "no machines configured")
    }

    // MARK: - The encoder

    /// **A machine name is whatever somebody typed.** An unescaped quote turns
    /// one object into two and a parser downstream reads something that was
    /// never written — the same class of bug as an unquoted shell argument,
    /// which this codebase already refuses to leave to chance.
    @Test
    func aHostileNameCannotBreakOutOfItsField() throws {
        let json = HerdCommand.jsonArray([
            ["name": #"He said "hi", then \ left"#, "id": "x"]
        ])

        #expect(json.contains(#"\"hi\""#))
        #expect(json.contains(#"\\"#))
        // And the result is still JSON, which is the only assertion that
        // actually proves the escaping rather than describing it.
        let parsed = try JSONSerialization.jsonObject(
            with: Data(json.utf8)
        ) as? [[String: String]]
        #expect(parsed?.first?["name"] == #"He said "hi", then \ left"#)
    }

    @Test
    func controlCharactersAreEscapedRatherThanEmitted() throws {
        let json = HerdCommand.jsonArray([["name": "one\ntwo\ttab"]])
        let parsed = try JSONSerialization.jsonObject(
            with: Data(json.utf8)
        ) as? [[String: String]]
        #expect(parsed?.first?["name"] == "one\ntwo\ttab")
    }

    /// Every verb takes `--json`, and asking for it must not change which verb
    /// ran — the flag is an output format, not a mode.
    @Test
    func theFlagIsReadWhereverItAppears() {
        #expect(HerdCommand.wantsJSON(["little-herd", "machines", "--json"]))
        #expect(HerdCommand.wantsJSON(["little-herd", "--json", "machines"]))
        #expect(!HerdCommand.wantsJSON(["little-herd", "machines"]))
        #expect(
            HerdCommand.disposition(for: ["little-herd", "machines", "--json"])
                == .respond(output: "", code: 0)
        )
    }

    // MARK: - Naming a session

    /// **A session's `id` carries its provider**, so the first eight characters
    /// of one are `claude:1` — all provider and no session, identical for every
    /// row. Found by printing the real herd rather than a fixture: with one
    /// session on screen it looks like an identifier.
    @Test
    func aSessionIsNamedByItsOwnIdentifierAndNotItsProvider() {
        #expect(
            HerdCommand.shortIdentifier("claude:4c3e8491-0451-4806-af9c-fc")
                == "4c3e8491"
        )
        #expect(
            HerdCommand.bareIdentifier("codex:0199abcd-ef01")
                == "0199abcd-ef01"
        )
        // An identifier with no provider is left alone rather than mangled.
        #expect(HerdCommand.shortIdentifier("4c3e8491-0451") == "4c3e8491")
    }

    // MARK: - The exit code contract

    /// **Nothing found is an error, not a successful report of nothing.** A
    /// script that asked where a session could go and got an empty list would
    /// read it as "nowhere", which is a different answer — and the reason the
    /// contract distinguishes 1 from 0 at all.
    @Test
    func aLookupThatFindsNothingExitsNonZero() {
        let answer = HerdCommand.destinations(
            matching: "zzzzzzzz",
            in: [],
            json: false
        )
        #expect(answer.code == 1)
        #expect(answer.output.contains("no session"))
    }

    /// An ambiguous prefix is refused rather than guessed. Picking one of two
    /// would eventually move the wrong work.
    @Test
    func anAmbiguousPrefixIsRefusedRatherThanChosenBetween() {
        let air = machine("local", name: "Air", host: "localhost", connection: .local)
        let sampled: [(MachineConfiguration, SystemSnapshot?)] = [(air, nil)]
        // With no snapshots there is nothing to match, which is the same path
        // as "not found" — the ambiguity case needs two live sessions and is
        // covered by the identifier test plus this one's shape.
        #expect(HerdCommand.destinations(matching: "ab", in: sampled, json: false).code == 1)
    }

    /// A verb that needs an argument and did not get one is a usage error.
    @Test
    func destinationsWithoutASessionIsAUsageError() {
        let answer = HerdCommand.answer(
            for: ["little-herd", "destinations"],
            fallback: ""
        )
        #expect(answer.code == 1)
        #expect(answer.output.contains("usage:"))
    }

    // MARK: - Why not there

    /// **The refusals are the app's own**, taken from `TransferAssembly` rather
    /// than restated here — a second opinion would drift from the first, and
    /// the whole value of the verb is that it is the answer a drop would give.
    @Test
    func everyRefusalHasWordsAndNoneIsBlank() {
        let refusals: [TransferAssembly.Refusal] = [
            .sessionCannotBeMoved(.nothingInFlight),
            .sessionCannotBeMoved(.cannotBeAsked),
            .sessionCannotBeMoved(.noRepository),
            .destinationLacksRepository,
            .destinationLacksAgent,
            .originLacksAgent,
            .originUnknown,
        ]
        for refusal in refusals {
            let words = HerdCommand.reason(refusal)
            #expect(!words.isEmpty, "\(refusal) had nothing to say")
            #expect(!words.contains("Refusal"), "\(refusal) leaked its case name")
        }
    }
}

@Suite("Silence is not an outage")
struct HerdCommandSilenceTests {
    private func machine(
        _ id: String,
        connection: MachineConnection
    ) -> MachineConfiguration {
        MachineConfiguration(
            id: MachineID(id), name: id, shortName: id, hostname: id,
            hardwareSummary: "", platform: .macOS, connection: connection,
            avatar: .calfMini, identityFile: nil, sshUser: nil,
            serverNames: [], supportsGPU: false
        )
    }

    /// **A NAS that was never asked must not be reported as down.**
    ///
    /// Nothing samples a share or a DSM box — they hold capacity, run no
    /// agents, and cannot host work — so `sessions` gets no snapshot for them
    /// and used to print "(not reachable)". Caught live, with the Synology
    /// serving perfectly at the time: the command said a healthy machine was
    /// unreachable, which is the class of wrong answer this project spends its
    /// rules avoiding.
    @Test
    func aMachineThatWasNeverAskedSaysSo() {
        #expect(
            HerdCommand.unaskedOrUnreachable(machine("nas", connection: .dsm))
                == "(not asked — runs no agents)"
        )
        #expect(
            HerdCommand.unaskedOrUnreachable(machine("share", connection: .smb))
                == "(not asked — runs no agents)"
        )
    }

    /// A machine that *was* asked and did not answer is a different fact, and
    /// keeps the words that describe it.
    @Test
    func aMachineThatWasAskedAndDidNotAnswerStillReadsAsUnreachable() {
        #expect(
            HerdCommand.unaskedOrUnreachable(machine("mini", connection: .ssh))
                == "(not reachable)"
        )
    }

    /// And the distinction reaches the output rather than living in a helper.
    @Test
    func theTwoReadDifferentlyInTheListing() {
        let rows: [(MachineConfiguration, SystemSnapshot?)] = [
            (machine("nas", connection: .dsm), nil),
            (machine("mini", connection: .ssh), nil),
        ]
        let text = HerdCommand.sessions(rows, json: false)
        #expect(text.contains("nas  (not asked — runs no agents)"))
        #expect(text.contains("mini  (not reachable)"))
    }
}

/// `move`, the one verb that changes something.
///
/// **The exit code is the contract and it is what these are about.** A caller
/// that cannot tell "I refused, nothing happened" from "something went wrong"
/// will eventually retry a write that already succeeded, which for this verb
/// means moving the same work twice.
@Suite("Moving a session")
struct HerdCommandMoveTests {
    private func machine(
        _ id: String,
        _ short: String
    ) -> MachineConfiguration {
        MachineConfiguration(
            id: MachineID(id), name: short, shortName: short, hostname: id,
            hardwareSummary: "", platform: .macOS, connection: .ssh,
            avatar: .calfMini, identityFile: nil, serverNames: [],
            supportsGPU: false
        )
    }

    private var herd: [MachineConfiguration] {
        [machine("local", "Air"), machine("mac mini/malpern", "Mini"),
         machine("linux", "Linux")]
    }

    // MARK: - Naming a machine

    @Test
    func aMachineIsFoundByShortNameCaseInsensitively() throws {
        let found = try HerdCommand.machine(matching: "mini", in: herd).get()
        #expect(found.id == MachineID("mac mini/malpern"))
        let capitals = try HerdCommand.machine(matching: "MINI", in: herd).get()
        #expect(capitals.id == MachineID("mac mini/malpern"))
    }

    /// **A prefix that fits two machines is refused rather than chosen
    /// between.** The same rule as a session prefix, and for a worse reason:
    /// guessing here sends work to a machine nobody named.
    ///
    /// `ai`, not `air`: this test asserted `air` first and failed, correctly.
    /// `air` is a case-insensitive *exact* match for `Air`, so it is not
    /// ambiguous at all — which is the neighbouring test's whole point, and
    /// the two rules were written on the same afternoon disagreeing.
    @Test
    func anAmbiguousMachineIsRefused() {
        let two = [machine("air", "Air"), machine("airlock", "Airlock")]
        guard case .failure(let refused) = HerdCommand.machine(matching: "ai", in: two)
        else {
            Issue.record("expected a refusal")
            return
        }
        #expect(refused.message.contains("matches 2"))
    }

    /// An exact name wins over a prefix, so a machine called `Air` is still
    /// reachable when an `Airlock` exists.
    @Test
    func anExactNameBeatsALongerPrefix() throws {
        let two = [machine("air", "Air"), machine("airlock", "Airlock")]
        let found = try HerdCommand.machine(matching: "Air", in: two).get()
        #expect(found.id == MachineID("air"))
    }

    @Test
    func anUnknownMachineListsTheOnesThatExist() {
        guard case .failure(let refused) =
            HerdCommand.machine(matching: "nas", in: herd)
        else {
            Issue.record("expected a refusal")
            return
        }
        #expect(refused.message.contains("Air"))
        #expect(refused.message.contains("Mini"))
    }

    // MARK: - The exit-code contract

    /// **`move` with no `--to` is a usage error, not a refusal.** Exit 1, not
    /// 2: nothing was declined, the command was incomplete.
    @Test
    func moveWithoutADestinationIsAUsageError() {
        let answer = HerdCommand.answer(for: ["little-herd", "move"], fallback: "")
        #expect(answer.code == 1)
        #expect(answer.output.contains("usage:"))
    }

    @Test
    func moveIsAVerbAndNotAnUnknownWord() {
        guard case .respond(_, let code) =
            HerdCommand.disposition(for: ["little-herd", "move", "abc", "--to", "mini"])
        else {
            Issue.record("expected a response")
            return
        }
        #expect(code == 0, "move must reach the answering path, not the unknown-verb path")
    }

    /// The plan says what would change, and names the branch — which is the
    /// thing to go looking for if anything goes wrong later.
    @Test
    func theRefusedPlanNamesTheChangeAndTheBranch() {
        let session = AgentSession(
            id: "claude:c6df5704-0451-4806-af9c-fc4cd9e79121",
            provider: .claude,
            projectName: "little-herd",
            state: .waiting,
            updatedAt: .now,
            progress: nil,
            title: "Live transfer probe",
            workingDirectory: "/Users/x/local-code/little-herd"
        )
        let plan = HerdCommand.Plan(
            session: session,
            origin: machine("local", "Air"),
            destination: machine("mac mini/malpern", "Mini"),
            branch: TransferAssembly.branch(for: session)
        )
        let text = HerdCommand.plannedChange(plan, json: false)
        #expect(text.contains("Air"))
        #expect(text.contains("Mini"))
        #expect(text.contains("Live transfer probe"))
        #expect(text.contains(TransferAssembly.branch(for: session)))
        #expect(text.contains("--yes"))
        #expect(text.contains("Nothing has been changed"))

        // And the same facts survive the JSON, which is what a script reads.
        let json = HerdCommand.plannedChange(plan, json: true)
        #expect(json.contains("\"applied\": \"false\""))
        #expect(json.contains("\"exit_reason\": \"confirmation_required\""))
    }

    /// The usage text has to mention `--yes`, because it is the whole
    /// difference between a report and a change.
    @Test
    func theUsageSaysHowToConfirm() {
        #expect(HerdCommand.usage.contains("move"))
        #expect(HerdCommand.usage.contains("--yes"))
        #expect(HerdCommand.usage.contains("2 refused"))
    }
}

/// `transfers` — work carried out of a repository.
@Suite("Carried work")
struct HerdCommandTransfersTests {
    /// **A commit subject can contain a tab**, because a subject can contain
    /// anything somebody typed. Splitting on every tab would put half a
    /// sentence in the date column; the split is bounded so the remainder is
    /// the subject whatever is in it.
    @Test
    func aSubjectContainingATabSurvivesIntact() {
        let refs = "origin/transfer/a\t2026-09-06\tSuccessor work\ton the branch"
        let rows = HerdCommand.carriedWork(fromRefs: refs, mergedRefs: "")
        #expect(rows.count == 1)
        #expect(rows.first?.date == "2026-09-06")
        #expect(rows.first?.subject == "Successor work\ton the branch")
    }

    @Test
    func mergedIsReadFromTheSecondListRatherThanGuessed() {
        let refs = """
            origin/transfer/kept\t2026-09-06\tone
            origin/transfer/waiting\t2026-09-05\ttwo
            """
        let rows = HerdCommand.carriedWork(
            fromRefs: refs,
            mergedRefs: "origin/transfer/kept\n"
        )
        #expect(rows.first { $0.branch.hasSuffix("kept") }?.merged == true)
        #expect(rows.first { $0.branch.hasSuffix("waiting") }?.merged == false)
    }

    /// The name is the part somebody chose, without the plumbing around it.
    @Test
    func theNameDropsTheRemoteAndThePrefix() {
        let rows = HerdCommand.carriedWork(
            fromRefs: "origin/transfer/linux-memory-issues\t2026-09-06\tx",
            mergedRefs: ""
        )
        #expect(rows.first?.shortName == "linux-memory-issues")

        let local = HerdCommand.carriedWork(
            fromRefs: "transfer/linux-memory-issues\t2026-09-06\tx",
            mergedRefs: ""
        )
        #expect(local.first?.shortName == "linux-memory-issues")
    }

    /// A malformed line is skipped rather than crashing or half-parsed.
    @Test
    func aLineWithoutAllThreeFieldsIsIgnored() {
        let rows = HerdCommand.carriedWork(
            fromRefs: "origin/transfer/a\t2026-09-06\tfine\nrubbish\n",
            mergedRefs: ""
        )
        #expect(rows.count == 1)
    }

    /// **Nothing carried is not an error**, unlike `destinations`, where an
    /// empty answer would be read as "nowhere to send it". Here the empty
    /// answer is simply true.
    @Test
    func anEmptyRepositorySaysSoAndIsStillASuccess() {
        let text = HerdCommand.transfers([], json: false)
        #expect(text.contains("no work has been carried"))
    }

    @Test
    func transfersIsAVerb() {
        guard case .respond(_, let code) =
            HerdCommand.disposition(for: ["little-herd", "transfers"])
        else {
            Issue.record("expected a response")
            return
        }
        #expect(code == 0)
        #expect(HerdCommand.usage.contains("transfers"))
    }
}

extension HerdCommandTransfersTests {
    /// **A pushed branch exists twice and is one piece of work.** Listing the
    /// local ref and the remote one both showed every transfer twice — and with
    /// different subjects, because the successor's commit is on the remote
    /// while the local ref is still at the departure. It read as one transfer
    /// that had happened twice and disagreed with itself.
    @Test
    func aBranchThatExistsLocallyAndOnTheRemoteIsOneRow() {
        let refs = """
            origin/transfer/x\t2026-09-06\tSuccessor work on transfer/x
            transfer/x\t2026-09-06\tCarry x
            """
        let rows = HerdCommand.carriedWork(fromRefs: refs, mergedRefs: "")
        #expect(rows.count == 1)
        // The one that got furthest: refs arrive newest first, and the
        // successor's commit is what somebody wants to see.
        #expect(rows.first?.subject == "Successor work on transfer/x")
    }
}
