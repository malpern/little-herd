import Foundation
import Testing
@testable import LittleHerd

/// Runs the embedded shell probes for real.
///
/// These scripts are the app's largest untested surface: a few hundred lines of
/// zsh living in Swift string literals, every `jq` and `sqlite3` call ending in
/// `2>/dev/null`, and the whole result discarded on a non-zero exit. A syntax
/// error or a bad filter shows up as an empty AI view rather than as anything
/// diagnosable, and the Swift parsers cannot catch it because they are fed
/// hand-written fixtures rather than the scripts' real output.
///
/// The agent probe is pointed at a fixture home so the assertions are exact.
struct AgentProbeShellTests {
    @Test
    func probeReadsPlanProgressFromATranscript() async throws {
        let home = try FixtureHome()
        try home.writeClaudeSession(
            projectPath: "/Users/tester/code/little-herd",
            sessionID: "session-abc",
            tasks: [
                ("Review the diff", "Reviewing the diff", "completed"),
                ("Fix the parser", "Fixing the parser", "in_progress"),
                ("Ship it", "Shipping", "pending"),
            ]
        )

        let snapshot = await AgentTaskProbe.readSnapshot(homeDirectory: home.path)
        let session = try #require(snapshot.sessions.first { $0.provider == .claude })

        #expect(session.projectName == "Little Herd")
        let progress = try #require(session.progress)
        #expect(progress.completedStepCount == 1)
        #expect(progress.totalStepCount == 3)
        #expect(progress.currentStepIndex == 2)
        #expect(progress.currentStep == "Fixing the parser")
    }


    /// The regression 0.1.40 shipped, and the reason it mattered.
    ///
    /// `end_turn` means the agent finished its turn, not that the session is
    /// over — between your messages it is waiting for the next one. The probe
    /// called that "completed" regardless of age, which was survivable while
    /// the panel had a Finished group to put it in. Once that group went, a
    /// session vanished the moment it answered you, which is the exact moment
    /// somebody looks at the panel.
    @Test
    func aturnThatJustEndedIsWaitingRatherThanFinished() async throws {
        let home = try FixtureHome()
        try home.writeFinishedTurn(
            projectPath: "/Users/tester/code/little-herd",
            sessionID: "session-fresh",
            endedSecondsAgo: 5 * 60
        )

        let snapshot = await AgentTaskProbe.readSnapshot(homeDirectory: home.path)
        let session = try #require(snapshot.sessions.first { $0.provider == .claude })

        #expect(session.state == .waiting)
    }

    /// And it still becomes history eventually, or the waiting group would
    /// only ever grow.
    ///
    /// Eight hours: past the six the recent-turn window allows, and inside the
    /// twelve beyond which the probe stops reporting a transcript at all. That
    /// band is the whole of what "finished" now means — known to the app,
    /// counted as tracked, and deliberately not listed. A first attempt at
    /// this test used thirty hours and got no session back at all, which is
    /// the outer window doing its job and proving nothing about this one.
    @Test
    func aturnThatEndedThisMorningIsFinished() async throws {
        let home = try FixtureHome()
        try home.writeFinishedTurn(
            projectPath: "/Users/tester/code/little-herd",
            sessionID: "session-stale",
            endedSecondsAgo: 8 * 60 * 60
        )

        let snapshot = await AgentTaskProbe.readSnapshot(homeDirectory: home.path)
        let session = try #require(snapshot.sessions.first { $0.provider == .claude })

        #expect(session.state == .completed)
    }


    /// A run that stopped inside a tool call is not holding for a person.
    ///
    /// Measured on this herd: of twenty-eight runs of one scheduled job,
    /// fourteen ended mid-tool, and every one sat in Waiting for twelve hours
    /// claiming to need something nobody could give it.
    @Test
    func arunThatStoppedMidToolIsStalledRatherThanWaiting() async throws {
        let home = try FixtureHome()
        try home.writeStalledSession(
            projectPath: "/Users/tester/code/little-herd",
            sessionID: "session-stalled",
            stoppedSecondsAgo: 3 * 60 * 60
        )

        let snapshot = await AgentTaskProbe.readSnapshot(homeDirectory: home.path)
        let session = try #require(snapshot.sessions.first { $0.provider == .claude })

        #expect(session.state == .stalled)
    }

    /// And it stays out of the panel, which is the whole point of telling it
    /// apart from waiting.
    @Test
    func astalledRunIsNotOfferedAsSomethingToAttendTo() async throws {
        let home = try FixtureHome()
        try home.writeStalledSession(
            projectPath: "/Users/tester/code/little-herd",
            sessionID: "session-stalled",
            stoppedSecondsAgo: 3 * 60 * 60
        )

        let snapshot = await AgentTaskProbe.readSnapshot(homeDirectory: home.path)
        let sessions = snapshot.sessions.map {
            MachineAgentSession(
                machine: MachineID("air"), session: $0,
                machineName: "Air", machineSymbolName: "laptopcomputer"
            )
        }
        let layout = AgentPanelLayout.make(from: sessions, showingFinished: false)

        #expect(layout.waiting.isEmpty)
        #expect(layout.active.isEmpty)
    }

    /// A session started in a home directory has no project, and the account
    /// name is not a substitute — every session under `/Users/clawd` used to
    /// arrive titled "Clawd".
    @Test
    func ahomeDirectoryIsNotAProject() async throws {
        let home = try FixtureHome()
        try home.writeFinishedTurn(
            projectPath: "/Users/clawd",
            sessionID: "session-home",
            endedSecondsAgo: 60
        )

        let snapshot = await AgentTaskProbe.readSnapshot(homeDirectory: home.path)
        let session = try #require(snapshot.sessions.first { $0.provider == .claude })

        #expect(session.projectName == "No project")
        #expect(session.projectName != "Clawd")
    }

    /// A real checkout still gets its name, or the rule above would have eaten
    /// every project on the machine.
    @Test
    func adirectoryinsideAHomeStillNamesItsProject() async throws {
        let home = try FixtureHome()
        try home.writeFinishedTurn(
            projectPath: "/Users/clawd/local-code/little-herd",
            sessionID: "session-real",
            endedSecondsAgo: 60
        )

        let snapshot = await AgentTaskProbe.readSnapshot(homeDirectory: home.path)
        let session = try #require(snapshot.sessions.first { $0.provider == .claude })

        #expect(session.projectName == "Little Herd")
    }

    /// The regression that shipped: the probe used to read only the tail of a
    /// transcript, so on a long session the TaskCreate entries fell outside the
    /// window while their updates survived. Every id then pointed past the end
    /// of the list and was discarded — a session seven of eight steps done
    /// reported "0/3".
    @Test
    func probeReadsProgressWhenCreatesAreFarFromTheEnd() async throws {
        let home = try FixtureHome()
        try home.writeClaudeSession(
            projectPath: "/Users/tester/code/little-herd",
            sessionID: "session-long",
            tasks: [
                ("First", "Doing first", "completed"),
                ("Second", "Doing second", "completed"),
                ("Third", "Doing third", "in_progress"),
            ],
            fillerLinesBetweenCreatesAndUpdates: 1_400
        )

        let snapshot = await AgentTaskProbe.readSnapshot(homeDirectory: home.path)
        let session = try #require(snapshot.sessions.first { $0.provider == .claude })

        let progress = try #require(session.progress)
        #expect(progress.completedStepCount == 2)
        #expect(progress.totalStepCount == 3)
        #expect(progress.currentStepIndex == 3)
        #expect(progress.currentStep == "Doing third")
    }

    @Test
    func probeReportsNothingForAnEmptyHome() async throws {
        let home = try FixtureHome()

        let snapshot = await AgentTaskProbe.readSnapshot(homeDirectory: home.path)

        #expect(snapshot.sessions.isEmpty)
        #expect(snapshot.tasksByProvider.isEmpty)
    }

    /// The same script runs on every remote Mac. If it stops emitting one of
    /// these keys the sampler throws `invalidOutput` and the machine silently
    /// reads as unavailable, so run it here and check the parser's contract.
    /// The local Mac and a remote Mac must answer "how much space is left" the
    /// same way. They used different APIs, and the generous one credited
    /// purgeable space, so the same machine read ~39 GB emptier when it was the
    /// local one.
    /// The bug this test exists for: **an empty checkout root used to abort the
    /// entire probe.**
    ///
    /// The scan globbed `"$root"/*`, and zsh treats a pattern that matches
    /// nothing as a fatal error rather than passing it through as `sh` does. So
    /// one empty `~/code` on a Mac cost every session in the AI panel and every
    /// agent version — and over ssh it cost the machine's whole metrics sample,
    /// because a non-zero exit makes `SSHCommandRunner` throw and the reading
    /// is discarded. The machine read as down because a directory was empty.
    ///
    /// The assertion is that the *rest of the script still runs*, which is why
    /// it looks for a session rather than for a checkout: a checkout scan that
    /// silently found nothing would pass a test that only counted checkouts.
    @Test
    func anEmptyCheckoutRootDoesNotTakeTheProbeWithIt() async throws {
        let home = try FixtureHome()
        try home.makeCheckoutRoot()
        try home.writeClaudeSession(
            projectPath: "/Users/tester/code/little-herd",
            sessionID: "session-empty-root",
            tasks: [("Keep going", "Keeping going", "in_progress")]
        )

        let snapshot = await AgentTaskProbe.readSnapshot(homeDirectory: home.path)
        #expect(
            snapshot.sessions.contains { $0.provider == .claude },
            "an empty checkout root aborted the probe before it read any sessions"
        )
    }

    /// And the scan still finds what it is for, keyed by the origin remote
    /// rather than by the folder — this herd has `keyboard-newswire` checked
    /// out in a directory called `keyboard-wire`.
    @Test
    func theCheckoutScanReportsRepositoriesByTheirRemoteSlug() async throws {
        let home = try FixtureHome()
        try home.writeCheckout(directory: "keyboard-wire", originSlug: "keyboard-newswire")
        try home.writeCheckout(directory: "little-herd", originSlug: "little-herd")
        // A directory that is not a checkout at all sits alongside them.
        try FileManager.default.createDirectory(
            atPath: "\(home.path)/local-code/scratch",
            withIntermediateDirectories: true
        )

        let snapshot = await AgentTaskProbe.readSnapshot(homeDirectory: home.path)
        let checkouts = try #require(snapshot.destination?.checkouts)
        #expect(checkouts["keyboard-newswire"] != nil)
        #expect(checkouts["little-herd"] != nil)
        #expect(checkouts["keyboard-wire"] == nil)
        #expect(checkouts["scratch"] == nil)
    }

    @Test
    func localAndRemoteAgreeOnFreeSpace() async throws {
        let sampler = MetricsSampler()
        let snapshot = await sampler.sample()
        let local = try #require(
            snapshot.storageVolumes.first { $0.mountPath == "/" }
        )

        let df = try #require(
            await LocalProcessRunner.run(
                executablePath: "/bin/df",
                arguments: ["-Pk", "/"]
            )
        )
        let available = try #require(
            df.split(whereSeparator: \.isNewline)
                .dropFirst()
                .first?
                .split(whereSeparator: \.isWhitespace)
                .dropFirst(3)
                .first
                .flatMap { Double($0) }
        ) * 1_024

        // Both read the same volume moments apart, so allow small drift.
        #expect(abs(local.availableBytes - available) < 2_000_000_000)
    }

    @Test
    func macOSMetricsCommandEmitsTheKeysTheParserNeeds() async throws {
        let output = try #require(
            await LocalProcessRunner.run(
                executablePath: "/bin/zsh",
                arguments: [
                    "-c",
                    // One second, so the shell check does not sit through a
                    // full sampling interval.
                    RemoteMetricsSampler.macOSCommand(cpuWindowSeconds: 1),
                ]
            )
        )
        let values = RemoteOutputParser.parse(output)

        let memory = try #require(values["mem"])
        #expect(memory.count == 2)
        #expect(memory[0] > 0)

        let disk = try #require(values["disk"])
        #expect(disk.count == 2)
        #expect(disk[0] > 0)

        #expect(values["network"]?.count == 2)
        #expect(values["cpu_percent"]?.first != nil)
        #expect(!RemoteOutputParser.parseMemoryConsumers(output).isEmpty)

        // The startup volume is read-only on a sealed system, so the read-only
        // filter has to keep it. Dropping "/" would empty the disk view on
        // every Mac, which is the expensive way to get this wrong.
        let volumes = RemoteOutputParser.parseStorageVolumes(output)
        #expect(volumes.contains { $0.mountPath.split(separator: ",").contains("/") })

        // Mounted disk images — leftover installer .dmgs — are read-only and
        // must not be reported as storage.
        let readOnly = try #require(
            await LocalProcessRunner.run(
                executablePath: "/sbin/mount",
                arguments: []
            )
        )
        .split(whereSeparator: \.isNewline)
        .filter { $0.contains("read-only") }
        .compactMap { line -> String? in
            guard let onRange = line.range(of: " on "),
                  let parenRange = line.range(of: " (", range: onRange.upperBound ..< line.endIndex)
            else {
                return nil
            }
            return String(line[onRange.upperBound ..< parenRange.lowerBound])
        }
        .filter { $0.hasPrefix("/Volumes/") }

        for volume in volumes {
            for mountPath in volume.mountPath.components(separatedBy: ", ") {
                #expect(
                    !readOnly.contains(mountPath),
                    "\(mountPath) is read-only and should not be reported as storage"
                )
            }
        }
    }
}

/// A throwaway home directory the probe can be pointed at.
private struct FixtureHome {
    let path: String

    init() throws {
        path = NSTemporaryDirectory()
            .appending("little-herd-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            atPath: path,
            withIntermediateDirectories: true
        )
    }

    /// Writes a transcript shaped like the ones Claude Code produces: a line
    /// carrying `cwd` and `sessionId`, a TaskCreate per task, optional filler,
    /// then the TaskUpdate that sets each task's status.

    /// A transcript whose last entry is a finished turn, optionally aged.
    ///
    /// Written through the real shell rather than fed to a parser, because the
    /// classification being tested lives in the probe script and a fixture-fed
    /// parser test would agree with whatever the script did.
    func writeFinishedTurn(
        projectPath: String,
        sessionID: String,
        endedSecondsAgo: TimeInterval
    ) throws {
        let directory = "\(path)/.claude/projects/fixture"
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        let lines = [
            #"{"type":"user","cwd":"\#(projectPath)","sessionId":"\#(sessionID)","message":{"role":"user","content":"go"}}"#,
            #"{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"done"}]}}"#,
        ]
        let file = "\(directory)/\(sessionID).jsonl"
        try lines.joined(separator: "\n").appending("\n").write(
            toFile: file, atomically: true, encoding: .utf8
        )
        // The probe reads the file's mtime for age, so the fixture sets it.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-endedSecondsAgo)],
            ofItemAtPath: file
        )
    }


    /// A transcript that stops inside a tool call and never returns — a run
    /// that was killed, crashed, or slept.
    func writeStalledSession(
        projectPath: String,
        sessionID: String,
        stoppedSecondsAgo: TimeInterval
    ) throws {
        let directory = "\(path)/.claude/projects/fixture"
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        let lines = [
            #"{"type":"user","cwd":"\#(projectPath)","sessionId":"\#(sessionID)","message":{"role":"user","content":"go"}}"#,
            #"{"type":"assistant","message":{"stop_reason":null,"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"SKILL.md"}}]}}"#,
        ]
        let file = "\(directory)/\(sessionID).jsonl"
        try lines.joined(separator: "\n").appending("\n").write(
            toFile: file, atomically: true, encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-stoppedSecondsAgo)],
            ofItemAtPath: file
        )
    }

    func writeClaudeSession(
        projectPath: String,
        sessionID: String,
        tasks: [(subject: String, activeForm: String, status: String)],
        fillerLinesBetweenCreatesAndUpdates: Int = 0
    ) throws {
        let directory = "\(path)/.claude/projects/fixture"
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )

        var lines = [
            #"{"type":"user","cwd":"\#(projectPath)","sessionId":"\#(sessionID)","message":{"role":"user","content":"go"}}"#,
        ]

        for task in tasks {
            lines.append(toolUse(
                name: "TaskCreate",
                input: #"{"subject":"\#(task.subject)","activeForm":"\#(task.activeForm)"}"#
            ))
        }

        for index in 0 ..< fillerLinesBetweenCreatesAndUpdates {
            lines.append(
                #"{"type":"assistant","message":{"stop_reason":null,"content":[{"type":"text","text":"step \#(index)"}]}}"#
            )
        }

        for (offset, task) in tasks.enumerated() where task.status != "pending" {
            lines.append(toolUse(
                name: "TaskUpdate",
                input: #"{"taskId":"\#(offset + 1)","status":"\#(task.status)"}"#
            ))
        }

        try lines.joined(separator: "\n").appending("\n").write(
            toFile: "\(directory)/\(sessionID).jsonl",
            atomically: true,
            encoding: .utf8
        )
    }

    /// An empty checkout root — the one thing that used to take the whole
    /// script down under zsh.
    func makeCheckoutRoot(_ name: String = "local-code") throws {
        try FileManager.default.createDirectory(
            atPath: "\(path)/\(name)",
            withIntermediateDirectories: true
        )
    }

    /// A checkout, identified the way git identifies it: by the origin
    /// remote's slug rather than by the directory it sits in.
    func writeCheckout(
        directory: String,
        originSlug: String,
        root: String = "local-code"
    ) throws {
        let gitDirectory = "\(path)/\(root)/\(directory)/.git"
        try FileManager.default.createDirectory(
            atPath: gitDirectory,
            withIntermediateDirectories: true
        )
        try """
        [core]
        \trepositoryformatversion = 0
        [remote "origin"]
        \turl = git@github.com:malpern/\(originSlug).git
        """.write(
            toFile: "\(gitDirectory)/config",
            atomically: true,
            encoding: .utf8
        )
    }

    private func toolUse(name: String, input: String) -> String {
        #"{"type":"assistant","message":{"stop_reason":null,"content":[{"type":"tool_use","name":"\#(name)","input":\#(input)}]}}"#
    }
}
