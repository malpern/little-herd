import Foundation
import Testing

@testable import LittleHerd

/// Asking a machine what the work needs.
///
/// **The detector and the pre-flight both existed and neither was ever
/// called.** Every transfer ran a constant — `xcodebuild test -scheme
/// LittleHerd` — which is true of this project and of nothing else, and would
/// have run Xcode's tests against a Rust repository without noticing.
@Suite("What the work needs")
struct RepositoryCheckProbeTests {
    @Test
    func aListingBecomesNames() {
        let entries = RepositoryCheckProbe.entries(
            fromListing: "Cargo.toml\nsrc\n\n  README.md  \n"
        )
        // A trailing newline would otherwise contribute an empty name, which
        // matches no rule but is still a name in the list.
        #expect(entries == ["Cargo.toml", "src", "README.md"])
    }

    /// **The repository decides, not the constant.** Each of these is a real
    /// shape of repository and none of them is this one.
    @Test
    func theCheckComesFromWhatIsInTheRepository() {
        func check(_ names: [String]) -> RepositoryCheck {
            RepositoryCheckDetector.check(forEntries: names)
        }
        #expect(check(["Cargo.toml", "src"]) == .cargo)
        #expect(check(["package.json"]) == .npm(script: "test"))
        #expect(check(["Package.swift"]) == .swiftPackage)
        #expect(check(["LittleHerd.xcodeproj"]) == .xcode(scheme: "LittleHerd"))
        // Nothing recognised is an explicit answer, not a fallback to ours.
        #expect(check(["README.md"]) == .none)
    }

    /// The pre-flight is the check's own first word, so the two cannot drift.
    @Test
    func thePreflightIsTakenFromTheCheck() {
        #expect(RepositoryCheckProbe.preflight(for: .cargo) == "command -v 'cargo'")
        #expect(
            RepositoryCheckProbe.preflight(for: .xcode(scheme: "X"))
                == "command -v 'xcodebuild'"
        )
        // Nothing to run means nothing to have.
        #expect(RepositoryCheckProbe.preflight(for: .none) == nil)
    }

    /// A path with a space in it is one argument. This herd has one — the
    /// mini's agent lives under `Application Support` — so it is not
    /// hypothetical.
    @Test
    func aRepositoryPathIsQuoted() {
        let command = RepositoryCheckProbe.listing(of: "/Users/x/Some Folder/repo")
        #expect(command.contains("'/Users/x/Some Folder/repo'"))
    }

    /// **Named, and nothing offered.** Item 14's rule: offer only what can be
    /// completed non-interactively over SSH, and otherwise say what is missing
    /// and stop. Xcode is fifteen gigabytes and an Apple Account.
    @Test
    func aMissingToolIsNamedRatherThanOffered() {
        let reason = RepositoryCheckProbe.missingToolReason(
            .xcode(scheme: "LittleHerd"),
            on: "Linux"
        )
        #expect(reason.contains("Linux"))
        #expect(reason.contains("xcodebuild"))
        #expect(reason.contains("Nothing was moved"))
        #expect(!reason.lowercased().contains("install"))
    }
}

/// The two questions, asked in order, against a machine that answers.
@Suite("The pre-flight")
struct DiscoverCheckTests {
    /// A destination with the repository and the tool reports the repository's
    /// own check — not the one the request was built with.
    @Test
    func adestinationThatHasBothReportsTheRepositorysCheck() async {
        let discovered = await TransferDriver.discoverCheck(
            repository: "/repo",
            on: "Mini",
            run: { command in
                command.hasPrefix("ls") ? ("Cargo.toml\nsrc\n", true) : ("/usr/bin/cargo", true)
            }
        )
        guard case .check(let check) = discovered else {
            Issue.record("expected a check, got \(discovered)")
            return
        }
        #expect(check == .cargo)
    }

    /// **The gap is found before anything moves.** The whole point of asking
    /// first: the expensive place to learn a machine cannot do the work is
    /// after the branch has been pushed.
    @Test
    func adestinationWithoutTheToolIsNamedAndNothingMoves() async {
        let discovered = await TransferDriver.discoverCheck(
            repository: "/repo",
            on: "Linux",
            run: { command in
                command.hasPrefix("ls")
                    ? ("LittleHerd.xcodeproj\n", true)
                    : ("", false)   // command -v xcodebuild finds nothing
            }
        )
        guard case .missingTool(let reason) = discovered else {
            Issue.record("expected a missing tool, got \(discovered)")
            return
        }
        #expect(reason.contains("xcodebuild"))
    }

    /// **A declaration wins over what the files suggest.** The listing says
    /// cargo; the repository says, in its `.little-herd.toml`, that it is an
    /// Xcode project — a Swift package with a project beside it, the case
    /// detection cannot call. The declaration is honoured, and it came from the
    /// destination, read into the same closed set.
    @Test
    func adeclarationOverridesDetection() async {
        let discovered = await TransferDriver.discoverCheck(
            repository: "/repo",
            on: "Mini",
            run: { command in
                if command.contains(RepositoryCheck.declarationFile) {
                    return ("[transfer]\ncheck = \"xcode\"\nscheme = \"App\"\n", true)
                }
                if command.hasPrefix("ls") { return ("Cargo.toml\nApp.xcodeproj\n", true) }
                return ("/usr/bin/xcodebuild", true)  // command -v
            }
        )
        guard case .check(let check) = discovered else {
            Issue.record("expected a check, got \(discovered)")
            return
        }
        #expect(check == .xcode(scheme: "App"), "the declaration should have won")
    }

    /// A malformed declaration does not override; detection stands, so a typo
    /// weakens fidelity rather than silently running the wrong thing.
    @Test
    func amalformedDeclarationFallsBackToDetection() async {
        let discovered = await TransferDriver.discoverCheck(
            repository: "/repo",
            on: "Mini",
            run: { command in
                if command.contains(RepositoryCheck.declarationFile) {
                    return ("[transfer]\ncheck = \"nonsense\"\n", true)
                }
                if command.hasPrefix("ls") { return ("Cargo.toml\n", true) }
                return ("/usr/bin/cargo", true)
            }
        )
        guard case .check(let check) = discovered else {
            Issue.record("expected a check")
            return
        }
        #expect(check == .cargo, "a bad declaration must fall back to detection")
    }

    /// **Silence is not evidence.** A machine that cannot be listed has not
    /// said it is unsuitable, and refusing on silence would ground the herd
    /// whenever one was slow — the same rule the sign-in probe follows.
    @Test
    func amachineThatCannotAnswerClaimsNothing() async {
        let discovered = await TransferDriver.discoverCheck(
            repository: "/repo",
            on: "Mini",
            run: { _ in ("", false) }
        )
        guard case .unknown = discovered else {
            Issue.record("expected unknown, got \(discovered)")
            return
        }
    }

    /// A repository with nothing to run is not asked whether it has nothing.
    @Test
    func nothingToRunAsksForNothing() async {
        // A recorder the closure can touch: it is `@Sendable`, so a plain
        // captured var will not compile — the same lesson `Handoff` records.
        let asked = CommandLog()
        let discovered = await TransferDriver.discoverCheck(
            repository: "/repo",
            on: "Mini",
            run: { command in
                asked.add(command)
                return ("README.md\n", true)
            }
        )
        guard case .check(let check) = discovered else {
            Issue.record("expected a check")
            return
        }
        #expect(check == .none)
        // Discovery always reads the listing and the declaration; a repository
        // with nothing to run is not then asked whether it has the tool for it.
        // The point is the *absent* preflight, not a raw count.
        #expect(!asked.lines.contains { $0.contains("command -v") }, "a no-op check asked a preflight")
    }
}


/// Records the commands a `@Sendable` closure was asked to run.
private nonisolated final class CommandLog: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String] = []
    var lines: [String] { lock.withLock { value } }
    func add(_ line: String) { lock.withLock { value.append(line) } }
}
