import Foundation
import Testing

@testable import LittleHerd

/// Reading `codex cloud list`, which has no `--json` and so must be read as prose.
///
/// The fixtures are the real command's shape, taken from `codex cloud list` on 0.153.4
/// on 7 September — including the two things a made-up fixture would have missed: an
/// `[ERROR]` task among the ready ones, and the fact that most finished tasks report
/// "no diff" rather than a diff of zero.
@Suite("Codex cloud tasks")
struct CodexCloudTaskTests {
    private let real = """
        https://chatgpt.com/codex/tasks/task_e_69c94ad48ca8832c8ec611b493037432
          [READY] Check readiness for new release version
          malpern/KeyPath  •  Mar 29 08:55
          no diff

        https://chatgpt.com/codex/tasks/task_e_69b5840c60d4832ca6a0897d83e13e5f
          [READY] Evaluate integration with macOS Swift app
          malpern/KeyPath  •  Mar 14 08:53
          +94/-0 • 1 file

        https://chatgpt.com/codex/tasks/task_e_69ac476c05dc832cb3803c79dc6cceb8
          [ERROR] Find keypad support for zippy cords
          malpern/KeyPath  •  Mar 10 08:10
          +14/-2 • 1 file
        """

    @Test
    func itreadsEveryFieldOfArealRecord() throws {
        let tasks = CodexCloudListParser.parse(real)
        #expect(tasks.count == 3)
        let first = try #require(tasks.first)
        #expect(first.id == "task_e_69c94ad48ca8832c8ec611b493037432")
        #expect(first.status == .ready)
        #expect(first.title == "Check readiness for new release version")
        #expect(first.repository == "malpern/KeyPath")
        #expect(first.when == "Mar 29 08:55")
        #expect(first.diff == .none)
    }

    /// **The repository is the point.** It is what lets the placement decision ask
    /// whether a machine has that checkout — the same question a session transfer asks,
    /// approached from the other side.
    @Test
    func everyTaskNamesItsRepository() {
        #expect(CodexCloudListParser.parse(real).allSatisfy { $0.repository == "malpern/KeyPath" })
    }

    @Test
    func afailedTaskIsNotHidden() throws {
        let failed = try #require(CodexCloudListParser.parse(real).last)
        #expect(failed.status == .error)
        #expect(failed.title == "Find keypad support for zippy cords")
    }

    /// **"no diff" is an answer, not an absence.** Most finished tasks say it, and
    /// showing them as unknown would make the common case look broken.
    @Test
    func diffsAreReadOrHonestlyNotRead() {
        #expect(CodexCloudListParser.diff(from: "no diff") == .none)
        #expect(CodexCloudListParser.diff(from: "+94/-0 • 1 file")
                == .changes(added: 94, removed: 0, files: 1))
        #expect(CodexCloudListParser.diff(from: "+14/-2 • 3 files")
                == .changes(added: 14, removed: 2, files: 3))
        // Something new from the vendor is kept verbatim rather than guessed at.
        #expect(CodexCloudListParser.diff(from: "partially applied") == .unreadable("partially applied"))
    }

    /// A status this build has never seen is still a task. Dropping it would hide work.
    @Test
    func anunknownStatusIsKeptRatherThanDropped() throws {
        let task = try #require(CodexCloudListParser.parse("""
            https://chatgpt.com/codex/tasks/task_e_1
              [QUEUEING] Something new
              a/b  •  Apr 1 09:00
              no diff
            """).first)
        #expect(task.status == .unknown)
        #expect(task.title == "Something new")
    }

    /// **Anchored on the URL, not on line counts.** A vendor adding a fifth line should
    /// cost one field, not every record after it.
    @Test
    func anextraLineDoesNotDerailTheFollowingRecords() {
        let tasks = CodexCloudListParser.parse("""
            https://chatgpt.com/codex/tasks/task_e_1
              [READY] First
              a/b  •  Apr 1 09:00
              no diff
              something the vendor added later

            https://chatgpt.com/codex/tasks/task_e_2
              [READY] Second
              a/b  •  Apr 2 09:00
              no diff
            """)
        #expect(tasks.count == 2)
        #expect(tasks.last?.title == "Second")
        #expect(tasks.last?.id == "task_e_2")
    }

    @Test
    func noiseWithoutAurlIsNotArecord() {
        #expect(CodexCloudListParser.parse("").isEmpty)
        #expect(CodexCloudListParser.parse("Not signed in.\nRun codex login.").isEmpty)
    }
}

/// The parser against the real command, which is the only thing that proves the shape
/// has not moved under us. `codex cloud list` is experimental and the vendor is free to
/// reformat it; a fixture cannot notice that and this can.
@Suite(
    "Live: codex cloud list",
    .enabled(if: ProcessInfo.processInfo.environment["LITTLE_HERD_LIVE"] == "1")
)
struct LiveCodexCloudHarness {
    @Test
    func therealCommandStillParses() throws {
        let binary = ProcessInfo.processInfo.environment["LITTLE_HERD_CODEX"]
            ?? "/Applications/ChatGPT.app/Contents/Resources/codex"
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            Issue.record("no codex at \(binary)")
            return
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["cloud", "list", "--limit", "10"]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let tasks = CodexCloudListParser.parse(String(decoding: data, as: UTF8.self))
        print("  parsed \(tasks.count) task(s)")
        for t in tasks.prefix(3) {
            print("   \(t.status.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(t.repository)  \(t.diff)")
        }
        #expect(!tasks.isEmpty, "the real command returned nothing this parser understood")
        // Every field the placement decision needs must actually arrive.
        #expect(tasks.allSatisfy { !$0.id.isEmpty }, "a task without an id cannot be applied")
        #expect(tasks.allSatisfy { $0.repository.contains("/") }, "a task must name owner/repo")
        #expect(tasks.allSatisfy { !$0.title.isEmpty })
    }
}
