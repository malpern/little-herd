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
                arguments: ["-c", RemoteMetricsSampler.macOSCommand]
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

    private func toolUse(name: String, input: String) -> String {
        #"{"type":"assistant","message":{"stop_reason":null,"content":[{"type":"tool_use","name":"\#(name)","input":\#(input)}]}}"#
    }
}
