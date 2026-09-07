import Foundation
import Testing

@testable import LittleHerd

/// What Little Herd offers to do about a machine that cannot take work.
///
/// **The line these guard is offer-versus-explain**: a gap that finishes on
/// its own over a pipe may be offered; a gap that needs a browser or fifteen
/// gigabytes is named and stopped at. The type carries the line — an `explain`
/// has no command — so the tests are mostly proving which side each gap lands
/// on, and that nothing lands on the wrong one.
@Suite("Remedies")
struct TransferRemedyTests {
    private func install(_ p: AgentTaskProvider) -> AgentInstallation {
        AgentInstallation(provider: p, version: "1", path: "/x/\(p.rawValue)")
    }

    // MARK: - What can be closed from here

    /// A missing checkout with a URL to clone from is an offer, and the command
    /// clones into the first place the probe looks.
    @Test
    func amissingCheckoutIsClonedWhereItWillBeFound() {
        let remedy = TransferRemedy.remedy(
            for: .noCheckout(repository: "little-herd"),
            machine: "Mini", provider: .claude,
            originURL: "git@github.com:malpern/little-herd.git",
            slug: "little-herd"
        )
        guard case .offer(let summary, let command) = remedy else {
            Issue.record("expected an offer, got \(remedy)")
            return
        }
        #expect(summary.contains("Mini"))
        #expect(command.contains("git clone"))
        #expect(command.contains("git@github.com:malpern/little-herd.git"))
        #expect(command.contains("$HOME/local-code/little-herd"))
    }

    /// A missing Claude agent is an offer, because its installer is one pipe.
    @Test
    func amissingClaudeIsOfferedItsOneInstaller() {
        let remedy = TransferRemedy.remedy(
            for: .noAgent, machine: "Linux", provider: .claude,
            originURL: nil, slug: nil
        )
        guard case .offer(_, let command) = remedy else {
            Issue.record("expected an offer, got \(remedy)")
            return
        }
        #expect(command == "curl -fsSL https://claude.ai/install.sh | bash")
    }

    // MARK: - What only a person can close, and must never become a command

    /// **Sign-in is an explanation, never an offer.** It needs a browser, and
    /// there is no command that finishes it over SSH. If this ever returns an
    /// `offer`, the boundary the whole design rests on has moved.
    @Test
    func signedOutIsExplainedAndCarriesNoCommand() {
        let remedy = TransferRemedy.remedy(
            for: .signedOut(install(.claude), reason: "token expired"),
            machine: "Mini", provider: .claude,
            originURL: "x", slug: "y"
        )
        guard case .explain(let text) = remedy else {
            Issue.record("sign-in must be explained, not offered — got \(remedy)")
            return
        }
        #expect(text.contains("token expired"))
        #expect(text.lowercased().contains("browser"))
    }

    /// **Codex has no one-command install, so a missing Codex is explained.**
    /// Offering a command that is not really one installer would be worse than
    /// saying so.
    @Test
    func amissingCodexIsExplainedNotOffered() {
        let remedy = TransferRemedy.remedy(
            for: .noAgent, machine: "Mini", provider: .codex,
            originURL: nil, slug: nil
        )
        guard case .explain = remedy else {
            Issue.record("a missing codex must be explained — got \(remedy)")
            return
        }
    }

    /// A checkout with no remote to clone from cannot be an offer: there is
    /// nowhere to clone it from, so it is explained.
    @Test
    func acheckoutWithNoRemoteIsExplained() {
        for url in [nil, ""] as [String?] {
            let remedy = TransferRemedy.remedy(
                for: .noCheckout(repository: "r"), machine: "Mini", provider: .claude,
                originURL: url, slug: "r"
            )
            guard case .explain = remedy else {
                Issue.record("no remote must be explained — got \(remedy) for url \(String(describing: url))")
                return
            }
        }
    }

    /// An excluded machine is a setting, explained.
    @Test
    func excludedIsExplained() {
        guard case .explain(let text) = TransferRemedy.remedy(
            for: .excluded, machine: "Mini", provider: .claude,
            originURL: nil, slug: nil
        ) else {
            Issue.record("excluded must be explained")
            return
        }
        #expect(text.contains("Mini"))
    }

    // MARK: - Nothing to do

    @Test
    func aneligibleOrUnknownMachineHasNoRemedy() {
        #expect(
            TransferRemedy.remedy(
                for: .eligible(install(.claude), .verified(at: .now)),
                machine: "Mini", provider: .claude, originURL: "x", slug: "y"
            ) == TransferRemedy.none
        )
        #expect(
            TransferRemedy.remedy(
                for: .unknown, machine: "Mini", provider: .claude,
                originURL: "x", slug: "y"
            ) == TransferRemedy.none
        )
    }

    /// **The invariant, stated once: only two eligibility cases ever offer, and
    /// both are non-interactive over SSH.** Everything else explains or does
    /// nothing. This is the test that a new eligibility case cannot quietly
    /// become an offer without someone deciding it should.
    @Test
    func onlyTwoGapsAreEverOffered() {
        let cases: [DestinationEligibility] = [
            .eligible(install(.claude), .unverified),
            .signedOut(install(.claude), reason: "x"),
            .excluded,
            .noAgent,
            .noCheckout(repository: "r"),
            .unknown,
        ]
        var offered: Set<String> = []
        for c in cases {
            if case .offer = TransferRemedy.remedy(
                for: c, machine: "M", provider: .claude,
                originURL: "git@h:r.git", slug: "r"
            ) {
                offered.insert(c.detail)
            }
        }
        #expect(offered.count == 2, "exactly noAgent and noCheckout may offer; got \(offered)")
    }
}
