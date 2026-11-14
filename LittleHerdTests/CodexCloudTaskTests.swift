import Foundation
import Testing

@testable import LittleHerd

/// The current JSON and the text fallback for older Codex installs.
///
/// The fixtures are the real command's shape, taken from `codex cloud list` on 0.153.4
/// on 7 September — including the two things a made-up fixture would have missed: an
/// `[ERROR]` task among the ready ones, and the fact that most finished tasks report
/// "no diff" rather than a diff of zero.
@Suite("Codex cloud tasks")
struct CodexCloudTaskTests {
    private let json = """
        {
          "tasks": [
            {
              "id": "task_e_1", "url": "https://chatgpt.com/codex/tasks/task_e_1",
              "title": "Update the Mac app", "status": "Ready",
              "updated_at": "2026-11-14T19:00:00.138Z",
              "environment_label": "malpern/KeyPath", "environment_id": "env_1",
              "summary": {"files_changed": 1, "lines_added": 94, "lines_removed": 0},
              "is_review": false, "attempt_total": null
            },
            {
              "id": "task_e_2", "url": "https://chatgpt.com/codex/tasks/task_e_2",
              "title": "Review", "status": "NewStatus",
              "updated_at": "2026-11-14T19:10:00Z",
              "environment_label": null, "environment_id": "env_2",
              "summary": {"files_changed": 0, "lines_added": 0, "lines_removed": 0}
            }
          ],
          "cursor": "another-page"
        }
        """

    @Test
    func jsonKeepsFieldsNeededForDisplayAndPlacement() throws {
        let tasks = try #require(CodexCloudListParser.parseJSON(json))
        #expect(tasks.map(\.id) == ["task_e_1", "task_e_2"])
        let first = try #require(tasks.first)
        #expect(first.url == "https://chatgpt.com/codex/tasks/task_e_1")
        #expect(first.title == "Update the Mac app")
        #expect(first.status == .ready)
        #expect(first.repository == "malpern/KeyPath")
        #expect(first.repositorySlug == "KeyPath")
        #expect(first.when != "2026-11-14T19:00:00.138Z")
        #expect(first.diff == .changes(added: 94, removed: 0, files: 1))
        let last = try #require(tasks.last)
        #expect(last.status == .unknown)
        #expect(last.repository == "env_2")
        #expect(last.diff == .none)
    }

    @Test
    func readerPrefersJSONAndFallsBackOnlyWhenTheFlagIsUnsupported() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex fixture \(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let binary = directory.appendingPathComponent("codex")
        let legacyOutput = RemoteShell.quoted(real)

        func install(_ script: String) throws {
            try ("#!/bin/sh\n" + script).write(to: binary, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        }
        try install("""
            [ "$*" = 'cloud list --limit 20 --json' ] || exit 1
            printf '%s\\n' '{"tasks":[],"cursor":null}'
            """)
        #expect(CodexCloudReader.list(binary: binary.path) == [])

        try install("""
            if [ "$5" = --json ]; then
              echo "error: unexpected argument '--json' found" >&2
              exit 2
            fi
            printf '%s\\n' \(legacyOutput)
            """)
        #expect(CodexCloudReader.list(binary: binary.path) == CodexCloudListParser.parse(real))

        try install("""
            if [ "$5" = --json ]; then
              echo "network unavailable" >&2
              exit 1
            fi
            printf '%s\\n' \(legacyOutput)
            """)
        #expect(CodexCloudReader.list(binary: binary.path) == nil)
    }

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
        let tasks = try #require(CodexCloudReader.list(
            limit: 10, binary: ProcessInfo.processInfo.environment["LITTLE_HERD_CODEX"]
        ))
        print("  parsed \(tasks.count) task(s)")
        for t in tasks.prefix(3) {
            print("   \(t.status.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0)) \(t.repository)  \(t.diff)")
        }
        // Every field the placement decision needs must actually arrive.
        #expect(tasks.allSatisfy { !$0.id.isEmpty }, "a task without an id cannot be applied")
        #expect(tasks.allSatisfy { $0.repository.contains("/") }, "a task must name owner/repo")
        #expect(tasks.allSatisfy { !$0.title.isEmpty })
    }
}
