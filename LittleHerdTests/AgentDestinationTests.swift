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

    /// What `claude --version` actually answers on this herd's machines:
    /// `2.1.234 (Claude Code)`. Found in the running app, where the whole line
    /// reached the panel and wrapped a row onto two lines. Every fixture until
    /// then had used a bare number.
    @Test
    func theVersionIsTheNumberAndNotTheRestOfTheLine() throws {
        let installs = AgentInstallOutputParser.parse(
            line("claude", "2.1.234 (Claude Code)", "/Users/clawd/.local/bin/claude")
        )
        #expect(try #require(installs.first).version == "2.1.234")
        // Codex puts its name first, which is the opposite of Claude, and a
        // first-token rule gave a version column reading "codex-cli".
        #expect(
            AgentInstallOutputParser.versionNumber(in: "codex-cli 0.148.0-alpha.15")
                == "0.148.0-alpha.15"
        )
        // Nothing recognisable is passed through rather than dropped.
        #expect(AgentInstallOutputParser.versionNumber(in: "unknown") == "unknown")
        // A pre-release number is one token and survives whole.
        #expect(
            AgentInstallOutputParser.versionNumber(in: "0.148.0-alpha.15")
                == "0.148.0-alpha.15"
        )
        // Two copies that differ only in their suffix are still one install.
        let both = AgentInstallOutputParser.parse(
            [
                line("claude", "2.1.221 (Claude Code)", "/old"),
                line("claude", "2.1.234 (Claude Code)", "/new"),
            ].joined(separator: "\n")
        )
        #expect(both.count == 1)
        #expect(try #require(both.first).path == "/new")
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
            ) == .eligible(claude, .unverified)
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
        // It used to say "Can host a session" on the strength of a binary
        // being present. That was the overclaim: linux had binaries for both
        // agents and could sign in with neither. Naming the agent is still
        // the job of this row; promising it works is not.
        #expect(eligibility.detail == "Claude 2.1.234 here — sign-in not checked")
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
        #expect(candidates[0].eligibility == .eligible(claude, .unverified))
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

/// What each account has installed, set against the newest copy in the herd.
struct AgentVersionReaderTests {
    private func account(
        _ id: String,
        _ name: String,
        _ installations: [AgentInstallation]?
    ) -> DestinationAccount {
        DestinationAccount(
            machine: MachineID(id),
            name: name,
            symbolName: "macmini",
            report: installations.map {
                DestinationReport(installations: $0, checkouts: [:])
            },
            mayHostSessions: false
        )
    }

    private func install(
        _ provider: AgentTaskProvider,
        _ version: String,
        _ path: String = "/x"
    ) -> AgentInstallation {
        AgentInstallation(provider: provider, version: version, path: path)
    }

    /// The herd as measured on 19 August: Claude is the same everywhere and
    /// Codex is three different builds. Only the copies that are behind get
    /// marked — this is the standing condition, not an incident, so a herd-wide
    /// announcement would be read once and never again.
    private var herd: [DestinationAccount] {
        [
            account("air", "Air", [
                install(.claude, "2.1.234"),
                install(.codex, "0.148.0-alpha.15"),
            ]),
            account("mini", "Mini", [
                install(.claude, "2.1.234"),
                install(.codex, "0.148.0-alpha.9"),
            ]),
            account("linux", "Linux", [
                install(.claude, "2.1.234"),
                install(.codex, "0.147.0"),
            ]),
        ]
    }

    @Test
    func acopyBehindTheHerdNamesWhatIsNewerAndWhere() throws {
        let linux = AgentVersionReader.reports(
            for: MachineID("linux"),
            among: herd
        )
        #expect(linux.map(\.installation.provider) == [.claude, .codex])

        let claude = try #require(linux.first { $0.id == "claude" })
        #expect(claude.newer == nil, "the same version everywhere is not behind")

        let codex = try #require(linux.first { $0.id == "codex" })
        #expect(codex.newer?.version == "0.148.0-alpha.15")
        #expect(codex.newer?.accountName == "Air")
    }

    /// The newest copy is not behind anything, and the middle one names the
    /// newest rather than merely something newer than itself.
    @Test
    func theNewestNamesNobodyAndTheMiddleNamesTheNewest() throws {
        let air = AgentVersionReader.reports(for: MachineID("air"), among: herd)
        #expect(air.allSatisfy { $0.newer == nil })

        let mini = AgentVersionReader.reports(for: MachineID("mini"), among: herd)
        let codex = try #require(mini.first { $0.id == "codex" })
        #expect(codex.newer?.accountName == "Air")
    }

    /// An account that has not reported has nothing to show, which is not the
    /// same as having no agents — the pane says "not measured" rather than
    /// listing an empty herd's worth of versions.
    @Test
    func anunmeasuredAccountReportsNothing() {
        let accounts = [account("nas", "NAS", nil)] + herd
        #expect(
            AgentVersionReader.reports(
                for: MachineID("nas"),
                among: accounts
            ).isEmpty
        )
        #expect(
            AgentVersionReader.reports(
                for: MachineID("unknown"),
                among: accounts
            ).isEmpty
        )
    }

    /// An agent nobody else has is not behind anything.
    @Test
    func asoleInstallIsNotBehind() throws {
        let alone = [
            account("air", "Air", [install(.codex, "0.147.0")]),
            account("mini", "Mini", [install(.claude, "2.1.234")]),
        ]
        let air = AgentVersionReader.reports(for: MachineID("air"), among: alone)
        #expect(try #require(air.first).newer == nil)
    }

    /// The path says which copy answered, which matters here: no machine in
    /// this herd has an agent on the PATH ssh sees, so where it was found is
    /// the whole story. Folded back to ~ because the Mac one is five levels
    /// inside "Application Support".
    @Test
    func thepathIsShownRelativeToHome() {
        let report = AgentVersionReport(
            installation: install(
                .claude,
                "2.1.234",
                "/Users/clawd/.local/bin/claude"
            ),
            newer: nil
        )
        #expect(report.shortPath(home: "/Users/clawd") == "~/.local/bin/claude")
        // A path outside the home directory is left exactly as measured.
        #expect(
            report.shortPath(home: "/Users/someone-else")
                == "/Users/clawd/.local/bin/claude"
        )
    }
}

/// Whether an agent can actually sign in, which the install probe cannot say.
///
/// Every fixture below is a real output captured on 25 August from this herd,
/// one probe per agent per machine. They are quoted rather than invented
/// because the wording is the whole of what the parser has to work with, and
/// three of the four refusals say different things about different problems.
@MainActor
struct AgentAuthProbeTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// The Air and the mini, Codex, the second of those over plain ssh.
    @Test
    func aProviderThatAnswersIsVerified() {
        let output = """
            hook: Stop Failed
            tokens used
            34,333
            AUTH_OK
            """

        #expect(AgentAuthProbe.outcome(from: output, at: now) == .verified(at: now))
    }

    /// Both Macs, Claude. The Air's ran from a shell inside the GUI login
    /// session and still got this, which is why being in that session is not
    /// on its own the fix.
    @Test
    func aMacThatCannotReachItsKeychainSaysNotSignedIn() {
        let state = AgentAuthProbe.outcome(
            from: "Not logged in · Please run /login",
            at: now
        )

        #expect(state == .refused(reason: "Not signed in on this account."))
    }

    /// The linux box, both agents, worded differently by each. Credentials
    /// present at mode 600 in both cases — the file existing proves nothing.
    @Test
    func anExpiredTokenIsToldApartFromNeverHavingSignedIn() {
        let claude = AgentAuthProbe.outcome(
            from: "Failed to authenticate: OAuth session expired and could not be refreshed",
            at: now
        )
        let codex = AgentAuthProbe.outcome(
            from: "ERROR: Your access token could not be refreshed. Please log out and sign in again.",
            at: now
        )

        #expect(claude == .refused(reason: "The sign-in here has expired."))
        #expect(codex == claude)
    }

    /// A mise shim announces itself before running anything. It is the first
    /// line of the linux output and it is not a refusal.
    @Test
    func amiseBannerIsNotMistakenForARefusal() {
        let output = """
            mise ~/.config/mise/config.toml tools: codex@0.149.1
            AUTH_OK
            """

        #expect(AgentAuthProbe.outcome(from: output, at: now) == .verified(at: now))
    }

    /// Being out of budget is not being signed out, and the fixes are
    /// opposite: one is to wait, the other is to re-authenticate.
    @Test
    func runningOutOfBudgetIsNotBeingSignedOut() {
        let state = AgentAuthProbe.outcome(
            from: "You've hit your usage limit. Try again later.",
            at: now
        )

        #expect(state == .refused(reason: "Signed in, but out of budget."))
    }

    /// A refusal nobody has seen before is the one most worth reading, so it
    /// is passed through rather than flattened into "something went wrong".
    @Test
    func anUnfamiliarRefusalIsQuotedRatherThanTranslated() {
        let state = AgentAuthProbe.outcome(from: "ERROR: region not supported", at: now)

        #expect(state == .refused(reason: "ERROR: region not supported"))
    }

    /// The trap this whole probe exists to avoid. `codex login status` printed
    /// exactly this on the linux box, exit 0, in 78 milliseconds — ten minutes
    /// after a real request there had failed to refresh its token. Anything
    /// that treats it as proof of life reintroduces the bug.
    @Test
    func theCheapStatusCommandWouldHaveLied() {
        let state = AgentAuthProbe.outcome(
            from: "Logged in using ChatGPT",
            at: now
        )

        #expect(state != .verified(at: now))
    }

    /// The challenge asks for nothing but an answer: no repository, no tools.
    @Test
    func theChallengeIsTheSmallestRequestThatProvesAnything() {
        let codex = AgentAuthProbe.command(
            for: AgentInstallation(provider: .codex, version: "0.148.0", path: "/opt/codex")
        )
        let claude = AgentAuthProbe.command(
            for: AgentInstallation(provider: .claude, version: "2.1.237", path: "/opt/claude")
        )

        #expect(codex.contains("--skip-git-repo-check"))
        #expect(codex.contains("'/opt/codex'"))
        #expect(claude.contains("-p "))
        #expect(claude.contains("'/opt/claude'"))
    }
}

/// What eligibility says once authentication is part of it.
@MainActor
struct DestinationAuthEligibilityTests {
    private let install = AgentInstallation(
        provider: .codex, version: "0.148.0", path: "/opt/codex"
    )
    private var report: DestinationReport {
        DestinationReport(installations: [install], checkouts: ["malpern/little-herd": "/repo"])
    }

    /// The finding that started this: an account with a binary was called
    /// eligible, and linux had binaries for both agents and could sign in with
    /// neither.
    @Test
    func aninstalledAgentNoLongerClaimsToBeSignedIn() {
        let eligibility = DestinationEligibility.resolve(
            report: report, repository: nil, isAllowed: true
        )

        #expect(eligibility.isEligible)
        #expect(eligibility.authState == .unverified)
        #expect(eligibility.detail.contains("sign-in not checked"))
        #expect(!eligibility.detail.contains("Can host a session"))
    }

    /// Once the provider has answered, it says so plainly.
    @Test
    func averifiedAccountSaysItCanHostASession() {
        let eligibility = DestinationEligibility.resolve(
            report: report, repository: nil, isAllowed: true,
            auth: .verified(at: Date(timeIntervalSince1970: 1_700_000_000))
        )

        #expect(eligibility.detail.contains("Can host a session"))
        #expect(eligibility.detail.contains("signed in"))
        #expect(eligibility.symbolName == "checkmark.circle")
    }

    /// A refusal takes the machine out of the running, and reads as something
    /// to sign in to rather than something to install onto.
    @Test
    func arefusedAccountIsNotOfferedAndSaysWhy() {
        let eligibility = DestinationEligibility.resolve(
            report: report, repository: nil, isAllowed: true,
            auth: .refused(reason: "The sign-in here has expired.")
        )

        #expect(!eligibility.isEligible)
        #expect(eligibility.detail.contains("cannot sign in"))
        #expect(eligibility.detail.contains("expired"))
        #expect(eligibility != .noAgent)
    }

    /// Intent still comes first. A machine you said no to reads as excluded,
    /// not as a list of things wrong with it.
    @Test
    func achoiceStillOutranksAMeasurement() {
        let eligibility = DestinationEligibility.resolve(
            report: report, repository: nil, isAllowed: false,
            auth: .refused(reason: "The sign-in here has expired.")
        )

        #expect(eligibility == .excluded)
    }
}
