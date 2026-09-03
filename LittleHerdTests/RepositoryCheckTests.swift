import Foundation
import Testing

@testable import LittleHerd

/// What a repository is allowed to say about how its work is checked.
@Suite("Repository check")
struct RepositoryCheckTests {
    /// **The property this type exists to preserve.** `SuccessorRun` has said
    /// from the start that the check is the app's command and a repository may
    /// name only which one — and making the check per-repository is precisely
    /// the change that would quietly undo it. A `check = "..."` string in a
    /// repository file would give anyone who can push a branch a command line
    /// on every machine that ever takes work from it.
    ///
    /// The enum is a closed set, so there is no representation for "run this
    /// command". This test is a statement of intent as much as an assertion:
    /// if a case ever appears that carries an executable, it fails.
    @Test
    func aRepositoryCanNameACheckAndNeverACommand() {
        let everyKind: [RepositoryCheck] = [
            .xcode(scheme: "S"), .swiftPackage, .cargo,
            .npm(script: "test"), .make(target: "test"), .none,
        ]

        let executables = Set(everyKind.compactMap(\.requiredExecutable))
        #expect(executables == ["xcodebuild", "swift", "cargo", "npm", "make"])
    }

    /// Punctuation in a parameter is an argument, not syntax. The closed set
    /// above is the first defence; this is the second, and it matters because
    /// a scheme name is the one part a repository fills in.
    @Test
    func aHostileParameterStaysAnArgument() {
        let check = RepositoryCheck.xcode(scheme: "S; rm -rf ~")
        let command = try! #require(check.commands.first)

        // It survives as one argument rather than becoming two commands...
        #expect(command.contains("S; rm -rf ~"))
        // ...and quoting is what carries it across the ssh boundary intact.
        let quoted = RemoteShell.quoted(command)
        #expect(!quoted.contains("; rm -rf ~;"))
        #expect(quoted.contains("'S; rm -rf ~'"))
    }

    /// The pre-flight is the check's own first word. A second list of the same
    /// fact drifts, which is how the fan and the resting deck came to disagree.
    @Test
    func thePreflightIsTakenFromTheCheckRatherThanDeclared() {
        #expect(RepositoryCheck.xcode(scheme: "S").requiredExecutable == "xcodebuild")
        #expect(RepositoryCheck.cargo.requiredExecutable == "cargo")
        #expect(RepositoryCheck.none.requiredExecutable == nil)
    }

    /// A check that runs nothing verifies nothing, and the difference has to be
    /// visible: delivering unverified work is a choice, not a default.
    @Test
    func nothingToRunIsNotTheSameAsPassing() {
        #expect(!RepositoryCheck.none.verifiesAnything)
        #expect(RepositoryCheck.none.commands.isEmpty)
        #expect(RepositoryCheck.swiftPackage.verifiesAnything)
    }

    /// Today's constant, unchanged. The command this app has always run is
    /// still the command it runs, which is what makes the refactor behind this
    /// type a refactor.
    @Test
    func theXcodeCommandIsWhatItAlwaysWas() {
        #expect(
            RepositoryCheck.xcode(scheme: "LittleHerd").commands == [
                ["xcodebuild", "test", "-scheme", "LittleHerd",
                 "-destination", "platform=macOS"]
            ]
        )
    }
}

@Suite("Repository check detection")
struct RepositoryCheckDetectorTests {
    /// This project, from its own root listing.
    @Test
    func anXcodeProjectIsDetectedWithItsSchemeGuessed() {
        let check = RepositoryCheckDetector.check(forEntries: [
            "LittleHerd", "LittleHerdTests", "LittleHerd.xcodeproj",
            "project.yml", "README.md",
        ])
        #expect(check == .xcode(scheme: "LittleHerd"))
    }

    /// A workspace wins over a project, because that is what its authors open.
    @Test
    func aWorkspaceBeatsAProjectBesideIt() {
        let check = RepositoryCheckDetector.check(forEntries: [
            "App.xcodeproj", "App.xcworkspace", "Podfile",
        ])
        #expect(check == .xcode(scheme: "App"))
    }

    /// **A Swift package with an Xcode project is an Xcode project.** Order is
    /// the whole of the design here: several of these markers coexist in real
    /// repositories, and the answer has to be the one the authors would give.
    @Test
    func theMostSpecificMarkerWins() {
        #expect(
            RepositoryCheckDetector.check(forEntries: ["Package.swift", "App.xcodeproj"])
                == .xcode(scheme: "App")
        )
        #expect(
            RepositoryCheckDetector.check(forEntries: ["package.json", "Makefile"])
                == .npm(script: "test")
        )
    }

    @Test
    func theOrdinaryEcosystemsAreRecognised() {
        #expect(RepositoryCheckDetector.check(forEntries: ["Package.swift"]) == .swiftPackage)
        #expect(RepositoryCheckDetector.check(forEntries: ["Cargo.toml", "src"]) == .cargo)
        #expect(
            RepositoryCheckDetector.check(forEntries: ["package.json"])
                == .npm(script: "test")
        )
        #expect(
            RepositoryCheckDetector.check(forEntries: ["Makefile"]) == .make(target: "test")
        )
    }

    /// **Recognising nothing is an answer, not a failure.** It has to be
    /// `.none` rather than a guess, because guessing here would mean running
    /// some plausible command on somebody else's machine and treating whatever
    /// it printed as a verdict on their work.
    @Test
    func anUnrecognisedRepositoryChecksNothing() {
        #expect(RepositoryCheckDetector.check(forEntries: ["main.c", "README"]) == .none)
        #expect(RepositoryCheckDetector.check(forEntries: []) == .none)
    }
}
