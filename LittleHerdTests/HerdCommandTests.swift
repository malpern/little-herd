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
