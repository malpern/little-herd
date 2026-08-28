import Testing
@testable import LittleHerd

/// What a successor may be started with.
struct SuccessorBinaryTests {
    /// The locations we have actually seen an agent answer from.
    @Test
    func aMeasuredLocationIsAccepted() {
        #expect(
            SuccessorBinary.accept("/Users/malpern/.local/bin/claude", for: .claude)
                == "/Users/malpern/.local/bin/claude"
        )
        #expect(
            SuccessorBinary.accept("/Users/clawd/.local/bin/codex", for: .codex)
                == "/Users/clawd/.local/bin/codex"
        )
    }

    /// **The whole point.** A machine that answers with something else does not
    /// get to choose what we run on it.
    @Test
    func aPathTheDestinationInventedIsRefused() {
        #expect(SuccessorBinary.accept("/tmp/claude", for: .claude) == nil)
        #expect(SuccessorBinary.accept("/usr/bin/curl", for: .claude) == nil)
        #expect(
            SuccessorBinary.accept("/Users/x/evil/.local/bin/claude; rm -rf /", for: .claude)
                == nil
        )
    }

    /// Relative paths resolve against whatever directory the successor starts
    /// in, which is not ours to assume.
    @Test
    func aRelativePathIsRefused() {
        #expect(SuccessorBinary.accept(".local/bin/claude", for: .claude) == nil)
        #expect(SuccessorBinary.accept("claude", for: .claude) == nil)
    }

    /// And no climbing out of a permitted location.
    @Test
    func aPathThatClimbsIsRefused() {
        #expect(
            SuccessorBinary.accept("/Users/x/../../tmp/.local/bin/claude", for: .claude)
                == nil
        )
    }

    /// One provider's location is not another's.
    @Test
    func aBinaryForTheWrongProviderIsRefused() {
        #expect(SuccessorBinary.accept("/Users/x/.local/bin/claude", for: .codex) == nil)
    }

    /// **Measured, not assumed.** Homebrew's codex dies under a
    /// non-interactive shell, so it is not a place a successor may start from
    /// however plausible the path looks.
    @Test
    func homebrewsCodexIsNotAllowedBecauseItDoesNotWork() {
        #expect(SuccessorBinary.accept("/opt/homebrew/bin/codex", for: .codex) == nil)
    }
}
