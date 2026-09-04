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

    /// A verb that is recognised and unbuilt says so. An empty list would read
    /// as "there are none", which is a different and wrong answer.
    @Test
    func anUnbuiltVerbAdmitsItRatherThanReturningNothing() {
        let text = HerdCommand.answer(
            for: ["little-herd", "destinations"],
            fallback: ""
        )
        #expect(text.contains("not built yet"))
    }
}
