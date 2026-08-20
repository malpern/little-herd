import Foundation
import Testing
@testable import LittleHerd

/// Whether a machine could host a session, measured rather than assumed.
struct AgentDestinationTests {
    private func line(_ provider: String, _ version: String, _ path: String) -> String {
        let v = Data(version.utf8).base64EncodedString()
        let p = Data(path.utf8).base64EncodedString()
        return "agent_install=\(provider)\t\(v)\t\(p)"
    }

    /// The lines the linux box produced, after the shim's banner was stripped.
    @Test
    func theLinesTheLinuxBoxProducedAreRead() throws {
        let installs = AgentInstallOutputParser.parse(
            [
                line("claude", "2.1.234", "/home/malpern/.local/bin/claude"),
                line("codex", "0.147.0", "/home/malpern/.local/bin/codex"),
            ].joined(separator: "\n")
        )
        #expect(installs.count == 2)
        let claude = try #require(installs.first { $0.provider == .claude })
        #expect(claude.version == "2.1.234")
        #expect(claude.path == "/home/malpern/.local/bin/claude")
    }

    /// The mini carries two copies of Claude — 2.1.234 in ~/.local/bin and
    /// 2.1.221 inside an application bundle. The newer is the one to report.
    @Test
    func theNewestCopyOnAMachineWins() throws {
        let installs = AgentInstallOutputParser.parse(
            [
                line("claude", "2.1.221", "/Users/clawd/Library/…/claude"),
                line("claude", "2.1.234", "/Users/clawd/.local/bin/claude"),
            ].joined(separator: "\n")
        )
        #expect(installs.count == 1)
        #expect(try #require(installs.first).version == "2.1.234")
    }

    /// Compared as numbers. As strings "2.1.9" sorts above "2.1.221", and that
    /// is the exact pair the mini has.
    @Test
    func versionsAreComparedAsNumbersNotText() {
        #expect(AgentInstallOutputParser.isNewer("2.1.234", than: "2.1.221"))
        #expect(!AgentInstallOutputParser.isNewer("2.1.9", than: "2.1.221"))
        #expect(AgentInstallOutputParser.isNewer("2.2.0", than: "2.1.999"))
        #expect(!AgentInstallOutputParser.isNewer("2.1.0", than: "2.1.0"))
        // Codex numbers its pre-releases; the numeric parts still order.
        #expect(
            AgentInstallOutputParser.isNewer(
                "0.148.0-alpha.15",
                than: "0.148.0-alpha.9"
            )
        )
    }

    private func report(
        _ installations: [AgentInstallation] = [],
        checkouts: [String: String] = [:]
    ) -> DestinationReport {
        DestinationReport(installations: installations, checkouts: checkouts)
    }

    private var claude: AgentInstallation {
        AgentInstallation(provider: .claude, version: "2.1.234", path: "/x")
    }

    /// A machine you have said no to reads as excluded, not as a list of what
    /// it lacks. Both may be true; only one is the reason, and the other would
    /// invite someone to fix a machine they had already decided about.
    @Test
    func intentIsReportedBeforeCapability() {
        #expect(
            DestinationEligibility.resolve(
                report: report(),
                repository: "little-herd",
                isAllowed: false
            ) == .excluded
        )
    }

    /// Off unless chosen, and chosen is a thing the herd remembers.
    @Test
    func hostingIsOffUntilItIsTurnedOn() {
        var machine = MachineConfiguration.local()
        #expect(!machine.mayHostSessions)
        machine.mayHostSessions = true
        #expect(machine.mayHostSessions)
        #expect(machine.mayHostSessionsPreference == true)
    }

    /// A machine saved before this setting existed still decodes.
    ///
    /// The store reads the herd entry by entry and keeps out whatever it
    /// cannot decode, so a required key here would have emptied a saved herd
    /// on the first launch after an update. Swift's synthesised decoder does
    /// not consult a property's default value, so this is not free.
    @Test
    func amachineSavedBeforeTheSettingExistedStillDecodes() throws {
        let saved = try JSONEncoder().encode(MachineConfiguration.local())
        var fields = try #require(
            try JSONSerialization.jsonObject(with: saved) as? [String: Any]
        )
        fields.removeValue(forKey: "mayHostSessionsPreference")
        let older = try JSONSerialization.data(withJSONObject: fields)

        let decoded = try JSONDecoder().decode(
            MachineConfiguration.self,
            from: older
        )
        #expect(!decoded.mayHostSessions)
    }

    /// Each missing piece is named, because they have different fixes — the
    /// same reason RemoteUnavailability distinguishes a name that will not
    /// resolve from a key that was refused.
    @Test
    func eachMissingPieceIsNamedSeparately() {
        #expect(
            DestinationEligibility.resolve(
                report: report(checkouts: ["little-herd": "/w"]),
                repository: "little-herd",
                isAllowed: true
            ) == .noAgent
        )
        #expect(
            DestinationEligibility.resolve(
                report: report([claude], checkouts: ["add-secret": "/a"]),
                repository: "little-herd",
                isAllowed: true
            ) == .noCheckout(repository: "little-herd")
        )
    }

    /// The measurement the checkout probe exists for: on 19 August the mini
    /// had seven repositories and Little Herd was not one of them, so it could
    /// run the agent and still not take this work. An eligibility check that
    /// stopped at the agent would have offered it.
    @Test
    func anagentIsNotEnoughWithoutTheRepository() {
        let mini = report(
            [claude],
            checkouts: [
                "add-secret": "/Users/clawd/local-code/add-secret",
                "imsg": "/Users/clawd/local-code/imsg",
            ]
        )
        #expect(
            !DestinationEligibility.resolve(
                report: mini,
                repository: "little-herd",
                isAllowed: true
            ).isEligible
        )
        #expect(
            DestinationEligibility.resolve(
                report: mini,
                repository: "add-secret",
                isAllowed: true
            ).isEligible
        )
    }

    /// Never asked is not the same as answered no. A machine that has not
    /// reported yet must not read as ineligible — and an account that *was*
    /// asked and has nothing is a real measurement, not an absent one.
    @Test
    func anunmeasuredMachineIsNotCalledIneligible() {
        let unmeasured = DestinationEligibility.resolve(
            report: nil,
            repository: "little-herd",
            isAllowed: true
        )
        #expect(unmeasured == .unknown)
        #expect(!unmeasured.isEligible)
        #expect(unmeasured.detail == "Not measured yet.")

        #expect(
            DestinationEligibility.resolve(
                report: report(),
                repository: "little-herd",
                isAllowed: true
            ) == .noAgent
        )
    }

    /// Settings has no session in front of it, so it asks about the account
    /// alone — and must not manufacture a repository complaint out of that.
    @Test
    func noRepositoryMeansTheCheckoutQuestionIsNotAsked() {
        #expect(
            DestinationEligibility.resolve(
                report: report([claude]),
                repository: nil,
                isAllowed: true
            ) == .eligible(claude)
        )
    }

    @Test
    func acapableAllowedMachineNamesWhatItWouldRun() {
        let eligibility = DestinationEligibility.resolve(
            report: report([claude], checkouts: ["little-herd": "/w"]),
            repository: "little-herd",
            isAllowed: true
        )
        #expect(eligibility.isEligible)
        #expect(eligibility.detail == "Can host a session — Claude 2.1.234")
    }

    /// The newest agent is the one a transfer would start, so it is the one
    /// the row names.
    @Test
    func theReportNamesItsNewestAgent() throws {
        let report = report([
            AgentInstallation(provider: .claude, version: "2.1.221", path: "/old"),
            AgentInstallation(provider: .claude, version: "2.1.234", path: "/new"),
        ])
        #expect(try #require(report.bestInstallation).path == "/new")
    }
}

/// Where a parked session could go, and why the rest of the herd could not.
struct DestinationRosterTests {
    private func account(
        _ id: String,
        allowed: Bool,
        report: DestinationReport?
    ) -> DestinationAccount {
        DestinationAccount(
            machine: MachineID(id),
            name: id,
            symbolName: "macmini",
            report: report,
            mayHostSessions: allowed
        )
    }

    private var claude: AgentInstallation {
        AgentInstallation(provider: .claude, version: "2.1.234", path: "/x")
    }

    /// The account the work is already on is not a destination for itself.
    @Test
    func theOriginIsNotOfferedAsItsOwnDestination() {
        let candidates = DestinationRoster.candidates(
            among: [
                account("air", allowed: true, report: DestinationReport(
                    installations: [claude],
                    checkouts: ["little-herd": "/l"]
                )),
                account("mini", allowed: true, report: DestinationReport(
                    installations: [claude],
                    checkouts: [:]
                )),
            ],
            forRepository: "little-herd",
            excluding: MachineID("air")
        )
        #expect(candidates.map(\.id) == [MachineID("mini")])
    }

    /// Somewhere the work could go leads; the reasons the others could not are
    /// the answer to a second question. Ties keep the herd's order, so the
    /// list does not rearrange itself between samples.
    @Test
    func somewhereItCouldGoComesFirst() {
        let candidates = DestinationRoster.candidates(
            among: [
                account("mini", allowed: false, report: nil),
                account("linux", allowed: true, report: DestinationReport(
                    installations: [claude],
                    checkouts: [:]
                )),
                account("studio", allowed: true, report: DestinationReport(
                    installations: [claude],
                    checkouts: ["little-herd": "/l"]
                )),
            ],
            forRepository: "little-herd",
            excluding: nil
        )
        #expect(
            candidates.map(\.id) == [
                MachineID("studio"), MachineID("mini"), MachineID("linux"),
            ]
        )
        #expect(candidates[0].eligibility == .eligible(claude))
        #expect(candidates[1].eligibility == .excluded)
        #expect(
            candidates[2].eligibility == .noCheckout(repository: "little-herd")
        )
    }

    /// Before anyone has chosen a destination every row says the same
    /// sentence, and a column that repeats itself is a column people stop
    /// reading. Caught in a render, not by a test — the rule is here so it
    /// stays caught.
    @Test
    func alistThatWouldRepeatItselfIsSaidOnce() {
        let untouched = DestinationRoster.candidates(
            among: [
                account("mini", allowed: false, report: nil),
                account("linux", allowed: false, report: nil),
                account("nas", allowed: false, report: nil),
            ],
            forRepository: "little-herd",
            excluding: nil
        )
        #expect(DestinationRoster.isEntirelyUnchosen(untouched))

        // One machine turned on is enough to make the rows differ, and then
        // every reason is worth its own line again.
        let mixed = DestinationRoster.candidates(
            among: [
                account("mini", allowed: false, report: nil),
                account("linux", allowed: true, report: DestinationReport(
                    installations: [claude],
                    checkouts: [:]
                )),
            ],
            forRepository: "little-herd",
            excluding: nil
        )
        #expect(!DestinationRoster.isEntirelyUnchosen(mixed))
        #expect(!DestinationRoster.isEntirelyUnchosen([]))
    }

    /// A herd of one has nothing to say, and says nothing.
    @Test
    func aherdOfOneOffersNothing() {
        #expect(
            DestinationRoster.candidates(
                among: [account("air", allowed: true, report: nil)],
                forRepository: "little-herd",
                excluding: MachineID("air")
            ).isEmpty
        )
    }
}

/// Which accounts have a checkout of the repository a session is in.
struct CheckoutTests {
    private func line(_ slug: String, _ path: String) -> String {
        "checkout=\(slug)\t\(Data(path.utf8).base64EncodedString())"
    }

    /// Keyed by the remote's slug, not the directory. This herd has
    /// `keyboard-newswire` checked out in a folder called `keyboard-wire`, and
    /// matching on the folder would have missed it — measured on the mini.
    @Test
    func checkoutsAreKeyedByRemoteNotByFolder() throws {
        let checkouts = CheckoutOutputParser.parse(
            line("keyboard-newswire", "/Users/clawd/local-code/keyboard-wire")
        )
        #expect(checkouts["keyboard-newswire"] == "/Users/clawd/local-code/keyboard-wire")
        #expect(checkouts["keyboard-wire"] == nil)
    }

    /// The measurement that made this feature worth building: the mini has
    /// seven repositories and Little Herd is not among them, so today the Air
    /// is the only machine that could take a Little Herd session. A destination
    /// probe that did not ask would have offered the mini.
    @Test
    func amachineWithoutTheRepositoryDoesNotHaveIt() {
        let checkouts = CheckoutOutputParser.parse(
            [
                line("add-secret", "/Users/clawd/local-code/add-secret"),
                line("imsg", "/Users/clawd/local-code/imsg"),
                line("meeting-memory", "/Users/clawd/local-code/meeting-memory"),
            ].joined(separator: "\n")
        )
        #expect(checkouts["little-herd"] == nil)
        #expect(checkouts["add-secret"] != nil)
    }

    @Test
    func malformedLinesAreSkippedRatherThanGuessed() {
        #expect(CheckoutOutputParser.parse("checkout=\tnotbase64").isEmpty)
        #expect(CheckoutOutputParser.parse("something else").isEmpty)
        #expect(CheckoutOutputParser.parse("").isEmpty)
    }
}
