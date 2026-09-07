import Foundation
import Testing

@testable import LittleHerd

/// Scrubbing a transcript before it leaves the machine.
///
/// The claim under test is deliberately narrow: the secret shapes that occur on this
/// herd are removed, and the file stays resumable. Not "no secret survives" — that is
/// not a testable claim and not a true one.
@Suite("Redacting a carried transcript")
struct TranscriptRedactionTests {
    private let M = TranscriptRedaction.marker

    /// **The case that actually occurs.** A session that ran `sops -d` has the whole
    /// secret store sitting in a tool result as `KEY=value` lines.
    @Test
    func sopsOutputLosesItsValuesAndKeepsItsNames() {
        let out = TranscriptRedaction.redact(
            "ANTHROPIC_API_KEY=sk-ant-abcdefghijklmnopqrstuv\nPUSHOVER_TOKEN=aQ83nfj2\nEDITOR=vim"
        )
        #expect(!out.contains("sk-ant-abcdefghijklmnopqrstuv"))
        #expect(!out.contains("aQ83nfj2"))
        // The name survives: knowing a key was present is often the useful half, and it
        // is not itself secret.
        #expect(out.contains("ANTHROPIC_API_KEY"))
        #expect(out.contains("PUSHOVER_TOKEN"))
        // A non-secret assignment is left completely alone.
        #expect(out.contains("EDITOR=vim"))
    }

    /// Values that announce their own shape go even without a telling name.
    @Test
    func selfAnnouncingTokensGoOnSightAlone() {
        for secret in [
            "ghp_0123456789abcdefghijklmnopqrstuvwxyz",
            "xoxb-1234567890-abcdefghij",
            "AKIA0123456789ABCDEF",
            "sk-0123456789abcdefghij",
        ] {
            let out = TranscriptRedaction.redact("the value is \(secret) ok")
            #expect(!out.contains(secret), "\(secret) survived")
            #expect(out.contains(M))
        }
    }

    /// A PEM block is multi-line and must go whole, not line by line.
    @Test
    func aprivateKeyBlockIsRemovedEntirely() {
        let pem = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXktdjEAAAAA\nAAAA\n-----END OPENSSH PRIVATE KEY-----"
        let out = TranscriptRedaction.redact("here it is:\n\(pem)\ndone")
        #expect(!out.contains("b3BlbnNzaC1rZXktdjEAAAAA"))
        #expect(out.contains("done"))
    }

    @Test
    func abearerHeaderLosesItsToken() {
        let out = TranscriptRedaction.redact("Authorization: Bearer abc123def456ghi789")
        #expect(!out.contains("abc123def456ghi789"))
    }

    /// **What must NOT be redacted.** A pattern loose enough to catch every token also
    /// catches commit shas and file paths — and a transcript whose shas were rewritten
    /// has lost the thing it was carried for.
    @Test
    func ordinaryContentIsUntouched() {
        let kept = "Fixed in commit 4e6d797a1b2c3d4e5f60718293a4b5c6d7e8f900, see LittleHerd/Transfer.swift:42"
        #expect(TranscriptRedaction.redact(kept) == kept)
        let prose = "I told him the meeting is at four and the door code is on the fridge"
        #expect(TranscriptRedaction.redact(prose) == prose)
    }

    // MARK: - The file has to stay resumable

    /// **Redaction happens on parsed JSON, so validity is structural.** A regex over raw
    /// text can truncate a string mid-escape; one malformed record makes the resumed
    /// session lose everything after it, silently.
    @Test
    func everyLineIsStillValidJSONAfterwards() throws {
        let jsonl = [
            #"{"role":"user","message":"export GITHUB_TOKEN=ghp_0123456789abcdefghijklmnopqrstuvwx"}"#,
            #"{"role":"assistant","message":"done","cwd":"/Users/a/x"}"#,
            #"{"role":"user","message":"a \"quoted\" string with a \\ backslash and API_KEY=abc123xyz"}"#,
        ].joined(separator: "\n")

        let (out, changed) = TranscriptRedaction.redactTranscript(jsonl)
        #expect(changed == 2, "two of the three records carried something; changed was \(changed)")
        for line in out.split(separator: "\n") {
            let data = Data(line.utf8)
            #expect((try? JSONSerialization.jsonObject(with: data)) != nil,
                    "line no longer parses: \(line.prefix(80))")
        }
        #expect(!out.contains("ghp_0123456789abcdefghijklmnopqrstuvwx"))
        #expect(out.contains("/Users/a/x"), "paths must survive — resume depends on the record shape")
    }

    /// A line that is not JSON is passed through rather than dropped. Losing history to
    /// tidy it up would be the worse failure.
    @Test
    func anunparseableLineSurvivesUntouched() {
        let (out, _) = TranscriptRedaction.redactTranscript("not json at all\n{\"a\":\"b\"}")
        #expect(out.contains("not json at all"))
    }

    /// The count is what the interface shows, because a number a person can weigh beats
    /// a tick they cannot check.
    @Test
    func thecountReportsHowManyRecordsChanged() {
        let clean = [#"{"m":"hello"}"#, #"{"m":"world"}"#].joined(separator: "\n")
        #expect(TranscriptRedaction.redactTranscript(clean).changedLines == 0)
    }
}

/// The default, which is the whole point of the feature.
@Suite("Scrubbing is the default")
struct CarryRedactionDefaultTests {
    /// **A `Carry` built without saying anything about scrubbing scrubs.** Someone adding
    /// a third call site should have to opt *out* deliberately, never forget to opt in.
    @Test
    func acarryScrubsUnlessTold() {
        let c = TransferDriver.Carry(
            localSourceHome: "/Users/a",
            sourceCommand: { _ in ("", true) },
            copy: { _, _, _ in true },
            destinationHome: "/Users/b",
            scratchRoot: "/Users/b/.little-herd/transfers"
        )
        #expect(c.redacts, "the default must be to scrub")
    }

    /// And the two preferences are distinct keys, so turning on the carry cannot
    /// accidentally turn off the scrub.
    @Test
    func thetwoPreferencesAreSeparate() {
        #expect(LittleHerdPreferences.carriesTranscriptKey
                != LittleHerdPreferences.carriesUnscrubbedTranscriptKey)
    }
}

/// The scrub, exercised through a real carry against a file on disk.
@Suite("A carry scrubs before it sends")
struct CarryScrubsOnDiskTests {
    /// **What is copied is the scrubbed file, and the original is untouched.** A
    /// transcript is a record; rewriting one in place would be falsifying it.
    @Test
    func thesentFileIsScrubbedAndTheOriginalIsNot() async throws {
        let home = NSTemporaryDirectory() + "carry-scrub-\(UUID().uuidString)"
        let project = "\(home)/.claude/projects/-Users-a-x"
        try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
        let original = #"{"role":"user","message":"GITHUB_TOKEN=ghp_0123456789abcdefghijklmnopqrstuvwx"}"#
        try original.write(toFile: "\(project)/s-1.jsonl", atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: home) }

        let sentPath = Recorder()
        let carry = TransferDriver.Carry(
            localSourceHome: home,
            sourceCommand: { _ in ("", true) },
            copy: { local, _, _ in sentPath.add(local); return true },
            destinationHome: "/Users/b",
            scratchRoot: "/Users/b/.little-herd/transfers"
        )
        #expect(carry.redacts, "default")

        let session = AgentSession(
            id: "claude:s-1", provider: .claude, projectName: "x", state: .waiting,
            updatedAt: .now, progress: nil, workingDirectory: "/Users/a/x")
        func account(_ id: String, home h: String) -> DestinationAccount {
            DestinationAccount(
                machine: MachineID(id), name: id, symbolName: "desktopcomputer",
                report: DestinationReport(
                    installations: [AgentInstallation(provider: .claude, version: "1",
                                                      path: "\(h)/.local/bin/claude")],
                    checkouts: ["x": "/Users/a/x"]),
                mayHostSessions: true, auth: .unverified, isVerifying: false)
        }
        let request = try #require(try? TransferAssembly.request(
            session: session, from: MachineID("a"), to: MachineID("b"),
            in: [account("a", home: "/Users/a"), account("b", home: "/Users/b")],
            check: .none).get())

        let outcome = await TransferDriver.carryTranscript(request, carry: carry)
        guard case .carried = outcome else {
            Issue.record("expected carried, got \(outcome)")
            return
        }
        let sent = try #require(sentPath.lines.first)
        #expect(sent != "\(project)/s-1.jsonl", "it must send a copy, not the original")
        // The original is a record and must be exactly as it was.
        #expect(try String(contentsOfFile: "\(project)/s-1.jsonl", encoding: .utf8) == original)
    }
}

/// Collects what a `@Sendable` closure saw.
private nonisolated final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String] = []
    var lines: [String] { lock.withLock { value } }
    func add(_ line: String) { lock.withLock { value.append(line) } }
}

/// The scrub against a real transcript, which is the only way to learn what it does to
/// 24 MB of actual work rather than to a fixture.
///
/// Gated: set `TEST_RUNNER_LITTLE_HERD_LIVE=1` and `LITTLE_HERD_TRANSCRIPT` to a path.
/// It reports counts only and never prints a matched value — the point is to measure the
/// scrub, not to put the things it found into a test log.
@Suite("Live: scrubbing a real transcript")
struct LiveRedactionHarness {
    @Test
    func measureAgainstARealTranscript() throws {
        let env = ProcessInfo.processInfo.environment
        try #require(env["LITTLE_HERD_LIVE"] == "1", "gated")
        let path = try #require(env["LITTLE_HERD_TRANSCRIPT"], "no transcript given")
        let raw = try String(contentsOfFile: path, encoding: .utf8)

        // **A monotonic clock, because `Date()` counts machine sleep.** The first
        // measurement of this reported 8,888 seconds inside a test run that xcodebuild
        // timed at 607 — the Air had slept mid-run, and the difference was real time
        // rather than work done.
        let clock = ContinuousClock()
        let started = clock.now
        let (out, changed) = TranscriptRedaction.redactTranscript(raw)
        let took = Double((clock.now - started).components.seconds)
        let lines = raw.split(separator: "\n").count

        print("  records:        \(lines)")
        print("  scrubbed:       \(changed)")
        print("  took:           \(String(format: "%.1f", took))s")
        print("  size:           \(raw.count) -> \(out.count) bytes")

        // Every line must still parse, or the carried session loses history.
        var broken = 0
        for line in out.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            if (try? JSONSerialization.jsonObject(with: Data(line.utf8))) == nil { broken += 1 }
        }
        print("  unparseable:    \(broken)")
        #expect(broken == 0, "the scrub broke \(broken) records")
        #expect(changed > 0, "a real transcript of this work should have had something in it")
    }
}
