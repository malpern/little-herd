import AppKit
import SwiftUI
import Testing
@testable import LittleHerd

/// Renders panels to PNGs so someone can look at them.
///
/// This project has had no way to see a view without launching the app, opening
/// the menu bar, and clicking through to the right screen — which is why every
/// visual defect in its history (a folder named `Library` rendered as "L", a
/// missing disclosure triangle, a spinner that never moved, a tooltip stuck
/// over a header) shipped past a green suite. Tests run inside the app bundle,
/// so `ImageRenderer` can do here what a preview does in Xcode, and the result
/// is a file anyone or anything can open.
///
/// These deliberately assert almost nothing. A pixel comparison against a
/// checked-in reference would fail on every OS update and teach people to
/// regenerate it without looking, which is worse than no test. What this
/// guarantees is that each panel *builds and renders at its real width* — a
/// view that crashes or renders empty fails here — and that a human has
/// something to look at.
@MainActor
struct PanelRenderHarness {
    /// The dashboard is 300 points wide on the overview, and the panel's
    /// content area is what is left under the header. Rendering at any other
    /// size would answer a question nobody asked.
    private static let panelSize = CGSize(width: 300, height: 228)
    /// Taller than the real panel, for reading the whole list at once. The
    /// real one scrolls; this is for judging the layout, not the fit.
    private static let reviewSize = CGSize(width: 300, height: 320)

    private static var outputDirectory: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("little-herd-panels", isDirectory: true)
    }

    @discardableResult
    func render(
        _ view: some View,
        size: CGSize = PanelRenderHarness.panelSize,
        named name: String
    ) throws -> URL {
        let renderer = ImageRenderer(
            content: view
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        renderer.scale = 2

        let image = try #require(renderer.nsImage, "\(name) rendered nothing")
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))

        try FileManager.default.createDirectory(
            at: Self.outputDirectory,
            withIntermediateDirectories: true
        )
        let url = Self.outputDirectory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("RENDERED \(url.path)")
        return url
    }

    // MARK: - Fixtures

    /// Modelled on the panel as it was actually read on 18 August: seven
    /// sessions, mostly finished, project names repeating, one session with a
    /// plan and the rest without.
    func busyHerd() -> [MachineAgentSession] {
        let now = Date.now
        func make(
            _ id: String,
            _ project: String,
            _ state: AgentSessionState,
            _ machine: MachineID,
            _ name: String,
            minutesAgo: Double,
            provider: AgentTaskProvider = .claude,
            progress: AgentSessionProgress? = nil,
            context: Int? = nil,
            model: String? = "claude-opus-5",
            title: String? = nil,
            activity: AgentActivity? = nil,
            repo: AgentRepoState? = nil
        ) -> MachineAgentSession {
            MachineAgentSession(
                machine: machine,
                session: AgentSession(
                    id: id,
                    provider: provider,
                    projectName: project,
                    state: state,
                    updatedAt: now.addingTimeInterval(-minutesAgo * 60),
                    progress: progress,
                    contextTokens: context,
                    title: title,
                    activity: activity,
                    model: model,
                    repo: repo
                ),
                machineName: name,
                machineSymbolName: "laptopcomputer"
            )
        }

        return [
            make(
                "claude:aa11bb22", "Little Herd", .active, .macBookAir, "Air",
                minutesAgo: 0,
                context: 943_000,
                title: "Little Herd Synology TLS sign-in",
                activity: AgentActivity(tool: "Bash", detail: "Running the full test suite")
            ),
            make(
                "claude:1234abcd", "Little Herd", .active, .macBookAir, "Air",
                minutesAgo: 2,
                title: "AI panel rail redesign",
                activity: AgentActivity(tool: "Edit", detail: "AIAgentsView.swift")
            ),
            make(
                "claude:cc33dd44", "Clawd", .waiting, .macBookAir, "Air",
                minutesAgo: 14,
                context: 187_400,
                title: "iOS secrets manager private app",
                activity: AgentActivity(tool: "AskUserQuestion", detail: ""),
                repo: AgentRepoState(branch: "claude/ios-secrets", slug: "add-secret", uncommittedFileCount: 4, unpushedCommitCount: 0)
            ),
            make(
                "claude:ee55ff66", "Clawd", .waiting, .macBookAir, "Air",
                minutesAgo: 68,
                title: "Tailscale mobile app testing",
                activity: AgentActivity(tool: "Read", detail: "NetworkExtension.swift")
            ),
            make(
                "claude:99887766", "Clawd", .completed, .macBookAir, "Air",
                minutesAgo: 4_320,
                title: "Smirk daily snapshot"
            ),
            make(
                "claude:55443322", "Little Herd", .completed, .macBookAir, "Air",
                minutesAgo: 51,
                title: "iseeyouseeme Mac app launch"
            ),
            make(
                "codex:aabbccdd", "dotfiles", .completed, .macBookAir, "Air",
                minutesAgo: 63,
                provider: .codex
            ),
        ]
    }

    /// Renders `AIAgentPanelContent` rather than `AIAgentsView`, because
    /// `ImageRenderer` lays out neither a `ScrollView` nor a lazy stack — the
    /// first version of this harness wrapped both, produced a blank image, and
    /// reported success.
    func panel(
        sessions: [MachineAgentSession],
        workload: HerdWorkloadFinding? = nil,
        showingFinished: Bool = false,
        collapsed: Set<AgentPanelSection>? = nil
    ) -> some View {
        AIAgentPanelContent(
            layout: AgentPanelLayout.make(from: sessions, showingFinished: showingFinished),
            workload: workload,
            machineName: "Air",
            compactionThresholds: AgentCompactionThresholds(observed: ["claude-opus-5": 1_000_000]),
            // Shares of the machine, not of a core. 62% is a session with a
            // parallel build under it — the case the meter exists for — and 4%
            // is one holding about half a core, which is what "working" looks
            // like most of the time. The low end is in the fixture on purpose:
            // it is where nearly every real session lives, and it is the end
            // that has now been got wrong twice.
            agentCPU: ["claude:aa11bb22": 62, "claude:1234abcd": 4],
            collapsed: .constant(
                collapsed ?? (showingFinished ? [] : [.finished])
            ),
            onSelectMachine: nil
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Hovered header fixtures

    @Test
    func renderAgentPanel() throws {
        try render(panel(sessions: busyHerd()), named: "ai-panel")
    }

    @Test
    func renderAgentPanelWithWorkloadFinding() throws {
        try render(
            panel(
                sessions: busyHerd(),
                workload: HerdWorkloadFinding(
                    busyMachine: .macBookAir,
                    busyName: "Air",
                    busyPercent: 94,
                    sessionCount: 3,
                    idleMachine: .macMini,
                    idleName: "Mini",
                    idlePercent: 8
                )
            ),
            named: "ai-panel-workload"
        )
    }

    @Test
    func renderAgentPanelFullList() throws {
        try render(
            panel(sessions: busyHerd()),
            size: Self.reviewSize,
            named: "ai-panel-full"
        )
    }

    @Test
    func renderAgentPanelWithFinishedExpanded() throws {
        try render(
            panel(sessions: busyHerd(), showingFinished: true),
            named: "ai-panel-expanded"
        )
    }

    /// A machine's own AI page, with what it has installed under what it is
    /// doing. Rendered at the width the pane gets beside the identity column.
    @Test
    func renderMachineAgentPane() throws {
        func machine(
            _ id: String,
            _ name: String,
            installations: [AgentInstallation],
            sessions: [AgentSession]
        ) -> MachineMonitorModel {
            let model = MachineMonitorModel(
                configuration: MachineConfiguration(
                    id: MachineID(id),
                    name: name,
                    shortName: name,
                    hostname: id,
                    hardwareSummary: "",
                    platform: .linux,
                    connection: .ssh,
                    avatar: .rabbitNUC,
                    identityFile: nil,
                    serverNames: [],
                    supportsGPU: false
                )
            )
            model.apply(
                SystemSnapshot(
                    timestamp: .now,
                    readings: [:],
                    agentSessions: sessions,
                    destination: DestinationReport(
                        installations: installations,
                        checkouts: [:]
                    )
                )
            )
            return model
        }

        func install(
            _ provider: AgentTaskProvider,
            _ version: String,
            _ path: String
        ) -> AgentInstallation {
            AgentInstallation(provider: provider, version: version, path: path)
        }

        let linux = machine(
            "linux",
            "Linux",
            installations: [
                install(.claude, "2.1.234", "\(NSHomeDirectory())/.local/bin/claude"),
                install(.codex, "0.147.0", "\(NSHomeDirectory())/.local/bin/codex"),
            ],
            sessions: [
                AgentSession(
                    id: "claude:aa11",
                    provider: .claude,
                    projectName: "dotfiles",
                    state: .active,
                    updatedAt: .now.addingTimeInterval(-120),
                    progress: nil,
                    title: "Clevis TPM auto-unlock"
                ),
            ]
        )

        let herd: [DestinationAccount] = [
            DestinationAccount(
                machine: MachineID("air"),
                name: "Air",
                symbolName: "laptopcomputer",
                report: DestinationReport(
                    installations: [
                        install(.claude, "2.1.234", "/a"),
                        install(.codex, "0.148.0-alpha.15", "/a"),
                    ],
                    checkouts: [:]
                ),
                mayHostSessions: false
            ),
            linux.destinationAccount,
        ]

        let reports = AgentVersionReader.reports(
            for: linux.machine,
            among: herd
        )

        // The pane's rows at the width they get beside the identity column.
        try render(
            VStack(alignment: .leading, spacing: 6) {
                MachineAgentRows(
                    machine: linux,
                    sessions: linux.agentSessions,
                    versions: reports
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12),
            size: CGSize(width: 324, height: 190),
            named: "machine-agent-pane"
        )

        // A machine with no sessions at all is the one whose versions you came
        // to read, and it still shows them: the pane's empty message is keyed
        // on the sessions alone, and an earlier version hid everything.
        try render(
            VStack(alignment: .leading, spacing: 6) {
                MachineAgentRows(machine: linux, sessions: [], versions: reports)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12),
            size: CGSize(width: 324, height: 190),
            named: "machine-agent-pane-idle"
        )
    }

    @Test
    func renderAgentPanelEmpty() throws {
        try render(
            AIAgentsView(
                sessions: [],
                    onSelectMachine: nil
            ),
            named: "ai-panel-empty"
        )
    }
}

/// The sign-in sheet, in the states that only appear when something is wrong.
///
/// It has a fixed 460×360 frame with a comment above it recording that it once
/// clipped the password field, and its failure area has since gained a second
/// line — and until now nobody had looked at it, because reaching these states
/// means typing a wrong password at a real NAS.
@MainActor
struct CredentialsSheetRenderHarness {
    private static let sheetSize = CGSize(width: 460, height: 360)

    private var machine: MachineConfiguration {
        MachineConfiguration(
            id: MachineID("alpernserver"),
            name: "Synology",
            shortName: "Synology",
            hostname: "nas.tail9d0bb8.ts.net",
            hardwareSummary: "Network storage",
            platform: .storage,
            connection: .dsm,
            avatar: .pigletNAS,
            identityFile: nil,
            serverNames: ["nas.tail9d0bb8.ts.net"],
            supportsGPU: false,
            dsmUsername: "malpern",
            dsmPort: 5001
        )
    }

    @discardableResult
    private func render(
        _ status: SynologyCredentialsView.Status,
        named name: String
    ) throws -> URL {
        let renderer = ImageRenderer(
            content: SynologyCredentialsView(
                machine: machine,
                onSave: { _ in },
                initialStatus: status
            )
            .frame(width: Self.sheetSize.width, height: Self.sheetSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
        )
        renderer.scale = 2
        let image = try #require(renderer.nsImage, "\(name) rendered nothing")
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("little-herd-panels", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("\(name).png")
        try png.write(to: url)
        print("RENDERED \(url.path)")
        return url
    }

    /// The longest thing this sheet can say, which is the one that would push
    /// the buttons off the bottom if anything were going to.
    @Test
    func renderTheLongestFailure() throws {
        try render(
            .failed(
                SynologyDSMError
                    .transport("The Internet connection appears to be offline.")
                    .explanation(host: "nas.tail9d0bb8.ts.net")
            ),
            named: "credentials-longest-failure"
        )
    }

    /// Two 64-character fingerprints on one line, which is the widest evidence
    /// it will ever carry.
    @Test
    func renderACertificateMismatch() throws {
        try render(
            .failed(
                SynologyDSMError.certificateChanged(
                    expected: String(repeating: "a", count: 64),
                    received: String(repeating: "b", count: 64)
                ).explanation(host: "nas.tail9d0bb8.ts.net")
            ),
            named: "credentials-certificate"
        )
    }

    @Test
    func renderSuccess() throws {
        try render(.succeeded(volumes: 1, drives: 4), named: "credentials-success")
    }
}

// MARK: - The panel on a realistic herd

extension PanelRenderHarness {
    /// Deliberately realistic in shape: two sessions working — one publishing
    /// a plan and one not — one blocked on a person, and two finished.
    ///
    /// The finished pair are in the fixture on purpose even though no group
    /// draws them any more. They are most of what a real probe returns, and a
    /// fixture without them would stop proving that they stay out of the
    /// panel.
    func comparisonHerd() -> [MachineAgentSession] {
        let now = Date.now
        func make(
            _ id: String,
            _ provider: AgentTaskProvider,
            _ project: String,
            _ title: String,
            _ tool: String,
            _ detail: String,
            _ state: AgentSessionState,
            minutesAgo: Double,
            progress: AgentSessionProgress? = nil
        ) -> MachineAgentSession {
            MachineAgentSession(
                machine: .macBookAir,
                session: AgentSession(
                    id: id,
                    provider: provider,
                    projectName: project,
                    state: state,
                    updatedAt: now.addingTimeInterval(-minutesAgo * 60),
                    progress: progress,
                    title: title,
                    activity: AgentActivity(tool: tool, detail: detail),
                    model: "claude-opus-5"
                ),
                machineName: "Air",
                machineSymbolName: "laptopcomputer"
            )
        }

        return [
            make(
                "claude:aa11bb22", .claude, "little-herd", "Synology TLS sign-in",
                "Bash", "Running the full test suite", .active, minutesAgo: 0,
                progress: AgentSessionProgress(
                    completedStepCount: 4, totalStepCount: 7,
                    currentStepIndex: 5, currentStep: "Verify the published feed"
                )
            ),
            make(
                "codex:cc33dd44", .codex, "monorepo", "MQ tester query state",
                "Edit", "AIAgentsView.swift", .active, minutesAgo: 2
            ),
            make(
                "claude:ee55ff66", .claude, "add-secret", "Crosspoint PDF check",
                "Read", "AddSecret.swift", .waiting, minutesAgo: 14
            ),
            make(
                "claude:1234abcd", .claude, "dotfiles", "Multi-machine update",
                "Bash", "Committing both fixes", .completed, minutesAgo: 61
            ),
            make(
                "codex:5678efab", .codex, "little-herd", "HANDOFF.md review",
                "Read", "Documentation/HANDOFF.md", .completed, minutesAgo: 190
            ),
        ]
    }

    private static let comparisonSize = CGSize(width: 300, height: 300)

    @Test
    func renderPanelOnARealisticHerd() throws {
        try render(
            panel(sessions: comparisonHerd()),
            size: Self.comparisonSize,
            named: "ai-panel-realistic"
        )
    }

    /// The same herd at the taller size, for reading the whole list at once.
    @Test
    func renderPanelOnARealisticHerdInFull() throws {
        try render(
            panel(sessions: comparisonHerd(), collapsed: []),
            size: Self.reviewSize,
            named: "ai-panel-realistic-full"
        )
    }
}

// MARK: - Rows that cannot be told apart

extension PanelRenderHarness {
    /// Six sessions started in one home directory, which is what the herd
    /// actually produces on the mini.
    ///
    /// A session with no title of its own falls back to the project name, the
    /// project name comes from the working directory, and `/Users/clawd` is
    /// "Clawd". Every row then reads the same. `AgentPanelRow.disambiguator`
    /// exists for exactly this and was invented the first time it happened;
    /// redrawing the row around a larger icon dropped it, and the panel went
    /// straight back to six identical lines.
    ///
    /// Every other fixture here gives its sessions distinct titles, which is
    /// why nothing caught it.
    @Test
    func renderRowsThatShareATitle() throws {
        let now = Date.now
        // Spelled out rather than built in one expression. Two ternaries and a
        // string interpolation inside an initialiser call defeated the type
        // checker outright — and it does not fail fast, it spent ten minutes
        // before saying so, which read exactly like a hung test run.
        func session(_ index: Int) -> MachineAgentSession {
            let provider: AgentTaskProvider = index == 3 ? .codex : .claude
            let state: AgentSessionState = index == 0 ? .active : .waiting
            let updatedAt = now.addingTimeInterval(-Double(index) * 900)
            let activity = AgentActivity(
                tool: "Bash",
                detail: "Running the nightly triage"
            )
            let identifier = "claude:aabbcc0" + String(index)
            let agent = AgentSession(
                id: identifier,
                provider: provider,
                projectName: "Clawd",
                state: state,
                updatedAt: updatedAt,
                progress: nil,
                title: nil,
                activity: activity,
                model: "claude-opus-5"
            )
            return MachineAgentSession(
                machine: .macMini,
                session: agent,
                machineName: "Mini",
                machineSymbolName: "macmini"
            )
        }
        let sessions = (0 ..< 4).map(session)

        try render(
            panel(sessions: sessions),
            size: CGSize(width: 300, height: 230),
            named: "ai-panel-same-title"
        )
    }
}

// MARK: - The CPU screen as a dashboard

extension PanelRenderHarness {
    /// The overview with agent badges under the machines that are working.
    ///
    /// The whole point of the mark is that it is absent most of the time, so
    /// the fixture has both: two machines running something and two not.
    @Test
    func renderOverviewWithAgentBadges() throws {
        func machine(
            _ id: String,
            _ name: String,
            _ avatar: HerdwareAvatar,
            cpu: Double,
            sessions: [AgentSession]
        ) -> MachineMonitorModel {
            let model = MachineMonitorModel(
                configuration: MachineConfiguration(
                    id: MachineID(id),
                    name: name,
                    shortName: name,
                    hostname: "\(id).local",
                    hardwareSummary: name,
                    platform: .macOS,
                    connection: .ssh,
                    avatar: avatar,
                    identityFile: nil,
                    serverNames: [],
                    supportsGPU: false
                )
            )
            model.apply(
                SystemSnapshot(
                    timestamp: .now,
                    readings: [.cpu: MetricReading(value: cpu)],
                    agentSessions: sessions
                )
            )
            return model
        }

        func session(
            _ id: String,
            _ provider: AgentTaskProvider,
            _ title: String,
            _ state: AgentSessionState
        ) -> AgentSession {
            AgentSession(
                id: id,
                provider: provider,
                projectName: "little-herd",
                state: state,
                updatedAt: .now,
                progress: nil,
                title: title,
                activity: nil,
                model: "claude-opus-5",
                workingDirectory: "/Users/x/code/little-herd"
            )
        }

        let machines = [
            machine("air", "Air", .chickLaptop, cpu: 51, sessions: [
                session("a", .claude, "Synology TLS sign-in", .active),
                session("b", .claude, "Panel redesign", .active),
            ]),
            machine("mini", "Mini", .calfMini, cpu: 22, sessions: [
                session("c", .codex, "Daily snapshot", .active),
            ]),
            machine("linux", "Linux", .ponyTower, cpu: 3, sessions: [
                session("d", .claude, "Finished earlier", .completed),
            ]),
            machine("nas", "Synology", .pigletNAS, cpu: 6, sessions: []),
        ]

        try render(
            CPUOverviewView(
                machines: machines,
                metric: .cpu,
                agentCPU: ["a": 61, "b": 4, "c": 38]
            ),
            size: CGSize(width: 324, height: 222),
            named: "overview-agent-badges"
        )

        // The whole dashboard as the design has it: a header that says one
        // thing, the herd, and the metric row along the bottom. None of these
        // three scroll, so `ImageRenderer` can lay the composition out and
        // somebody can judge the proportions without launching anything.
        try render(
            VStack(spacing: 0) {
                CPUOverviewHeaderArea(
                    machines: machines,
                    agentSessions: [],
                    aiUsageLimits: AIUsageLimitsModel(),
                    metric: .cpu
                )
                Divider().padding(.horizontal, 14)
                CPUOverviewView(machines: machines, metric: .cpu)
                OverviewMetricTabs(selection: .cpu, onSelect: { _ in })
            }
            // The real window loses this much to the traffic lights, and
            // `ImageRenderer` has no safe area to lose it to. Without this the
            // picture fits and the window clips — which is exactly how the tab
            // row shipped cut in half.
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: DashboardMetrics.titlebarInset)
            },
            size: DashboardMetrics.overviewContent,
            named: "overview-with-tabs"
        )

        // The metric row, with a machine in the red behind one of the tabs.
        try render(
            VStack(spacing: 18) {
                OverviewMetricTabs(selection: .cpu, onSelect: { _ in })
                OverviewMetricTabs(
                    selection: .cpu,
                    alarms: [.disk, .memory],
                    onSelect: { _ in }
                )
                OverviewMetricTabs(
                    selection: .disk,
                    alarms: [.disk],
                    onSelect: { _ in }
                )
            },
            size: CGSize(width: 324, height: 160),
            named: "metric-tabs-alarms"
        )

        // What the pointer gets, which used to be a `.help` string. Three
        // sessions, deliberately unlike each other: one reporting a long tool
        // call that has to wrap, one reporting nothing at all and falling back
        // to what it costs, and one with a name long enough to truncate.
        func detailed(
            _ id: String,
            _ title: String,
            _ activity: AgentActivity?
        ) -> AgentSession {
            AgentSession(
                id: id,
                provider: .claude,
                projectName: "little-herd",
                state: .active,
                updatedAt: .now,
                progress: nil,
                title: title,
                activity: activity,
                model: "claude-opus-5"
            )
        }

        try render(
            MachineAgentCard(
                activity: MachineAgentActivity(
                    provider: .claude,
                    sessions: [
                        detailed(
                            "a",
                            "Synology TLS sign-in",
                            AgentActivity(
                                tool: "Bash",
                                detail: "Running the full test suite against a "
                                    + "clean derived data directory"
                            )
                        ),
                        detailed("b", "Panel redesign", nil),
                        detailed(
                            "c",
                            "Destination eligibility and the transfer spike",
                            AgentActivity(tool: "Read", detail: "CPUOverviewView.swift")
                        ),
                    ]
                ),
                machineName: "Air",
                agentCPU: ["a": 61, "b": 4, "c": 12]
            ),
            size: CGSize(width: 268, height: 260),
            named: "agent-hover-card"
        )

        // The same card as an announcement: the session that just started is
        // moved to the top, and the header says why the card appeared without
        // being asked.
        try render(
            MachineAgentCard(
                activity: MachineAgentActivity(
                    provider: .claude,
                    sessions: [
                        detailed(
                            "a",
                            "Synology TLS sign-in",
                            AgentActivity(
                                tool: "Bash",
                                detail: "Running the full test suite against a "
                                    + "clean derived data directory"
                            )
                        ),
                        detailed("b", "Panel redesign", nil),
                        detailed(
                            "c",
                            "Destination eligibility and the transfer spike",
                            AgentActivity(tool: "Read", detail: "CPUOverviewView.swift")
                        ),
                    ]
                ),
                machineName: "Air",
                agentCPU: ["a": 61, "b": 4, "c": 12],
                leading: "c"
            ),
            size: CGSize(width: 268, height: 260),
            named: "agent-arrival-card"
        )

        // Every frame of the drag, which is the part that cannot be judged by
        // reading it. A gesture is four or five pictures, and the ones in the
        // middle — a herd offering itself, one machine refusing — are the ones
        // that decide whether the thing feels like it works.
        let carrying = AgentDragSession(
            origin: MachineID("air"),
            activity: try #require(
                MachineAgentActivityReader.activity(
                    for: machines[0].agentSessions,
                    cpuBySession: ["a": 61, "b": 4]
                )
            ),
            over: nil
        )

        // A herd with one real destination in it: the mini has the agent and
        // a checkout, the linux box has the agent and a lapsed credential, and
        // the NAS has never been asked. That is the mix the refusal states
        // were drawn for, and until eligibility was wired in none of them
        // could be reached from the running app.
        let claude = AgentInstallation(
            provider: .claude,
            version: "2.1.234",
            path: "/Users/x/.local/bin/claude"
        )
        func account(
            _ id: String,
            report: DestinationReport?,
            auth: AgentAuthState = .unverified
        ) -> DestinationAccount {
            DestinationAccount(
                machine: MachineID(id),
                name: id,
                symbolName: "laptopcomputer",
                report: report,
                mayHostSessions: false,
                auth: auth,
                isVerifying: false
            )
        }
        let herd = [
            account("air", report: DestinationReport(
                installations: [claude],
                checkouts: ["malpern/little-herd": "/Users/x/code/little-herd"]
            )),
            account("mini", report: DestinationReport(
                installations: [claude],
                checkouts: ["malpern/little-herd": "/Users/y/little-herd"]
            )),
            account("linux", report: DestinationReport(
                installations: [claude],
                checkouts: ["malpern/little-herd": "/home/x/little-herd"]
            ), auth: .refused(reason: "credentials expired")),
            account("nas", report: nil),
        ]

        func frame(_ drag: AgentDragSession, named name: String) throws {
            try render(
                CPUOverviewView(
                    machines: machines,
                    metric: .cpu,
                    agentCPU: ["a": 61, "b": 4, "c": 38],
                    herd: herd,
                    previewDrag: drag
                ),
                size: CGSize(width: 324, height: 222),
                named: name
            )
        }

        // Lifted, nothing chosen: every other machine says whether it could
        // take this.
        try frame(carrying, named: "overview-drag-lifted")

        // Over a machine that will take it.
        var overMini = carrying
        overMini.over = MachineID("mini")
        try frame(overMini, named: "overview-drag-over-target")

        // Over the machine it came from, which is a no-op rather than a
        // refusal — the pad stays quiet and the token has somewhere to fall
        // back to.
        var overHome = carrying
        overHome.over = MachineID("air")
        try frame(overHome, named: "overview-drag-over-origin")
    }
}

// MARK: - The drag vocabulary

extension PanelRenderHarness {
    /// Every pad state and every token lift, side by side.
    ///
    /// The overview frames show these in context, which is where they have to
    /// work — but in context each frame contains at most two of them, and the
    /// question "do these four read as four different answers" can only be
    /// asked with all four in one picture.
    @Test
    func renderTheDragVocabulary() throws {
        let activity = MachineAgentActivity(
            provider: .claude,
            sessions: [
                AgentSession(
                    id: "a",
                    provider: .claude,
                    projectName: "little-herd",
                    state: .active,
                    updatedAt: .now,
                    progress: nil,
                    title: "Panel redesign",
                    activity: nil,
                    model: "claude-opus-5"
                ),
            ]
        )

        func pad(_ state: AgentPadState, token: Bool, lift: MachineAgentToken.TokenLift) -> some View {
            MachineAgentPad(state: state, height: 32) {
                if token {
                    MachineAgentToken(
                        activity: activity,
                        machineName: "Air",
                        size: 22,
                        lift: lift
                    )
                }
            }
            .frame(width: 62)
        }

        try render(
            VStack(spacing: 14) {
                // Occupied: what a machine that is working looks like, and how
                // the token answers being pointed at and picked up.
                HStack(spacing: 8) {
                    pad(.idle, token: true, lift: .resting)
                    pad(.idle, token: true, lift: .ready)
                    pad(.idle, token: true, lift: .carried)
                    pad(.idle, token: false, lift: .resting)
                }
                // Empty, mid-drag: the three answers a machine can give.
                HStack(spacing: 8) {
                    pad(.available, token: false, lift: .resting)
                    pad(.targeted, token: false, lift: .resting)
                    pad(.refused, token: false, lift: .resting)
                    pad(.idle, token: false, lift: .resting)
                }
            },
            size: CGSize(width: 300, height: 120),
            named: "drag-vocabulary"
        )
    }
}
