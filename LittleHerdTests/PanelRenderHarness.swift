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
    private func render(
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
    private func busyHerd() -> [MachineAgentSession] {
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
                repo: AgentRepoState(branch: "claude/ios-secrets", uncommittedFileCount: 4, unpushedCommitCount: 0)
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
    private func panel(
        sessions: [MachineAgentSession],
        workload: HerdWorkloadFinding? = nil,
        showingFinished: Bool = false
    ) -> some View {
        AIAgentPanelContent(
            layout: AgentPanelLayout.make(from: sessions, showingFinished: showingFinished),
            workload: workload,
            machineName: "Air",
            compactionThresholds: AgentCompactionThresholds(observed: ["claude-opus-5": 1_000_000]),
            agentCPU: ["claude:aa11bb22": 96, "claude:1234abcd": 31],
            hoveredAgentID: .constant(nil),
            collapsed: .constant(showingFinished ? [] : [.finished]),
            onSelectMachine: nil
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Renders

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

    @Test
    func renderAgentPanelEmpty() throws {
        try render(
            AIAgentsView(
                sessions: [],
                hoveredAgentID: .constant(nil),
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
