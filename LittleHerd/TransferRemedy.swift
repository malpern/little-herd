import Foundation

/// What to do about a machine that cannot take a transfer, when there is
/// something to do.
///
/// **The type is the safety rule.** Item 14 draws one line through the
/// remedies: offer only what can be completed non-interactively over SSH, and
/// otherwise name the gap and stop. That line is `offer` versus `explain`, and
/// making it a type rather than a convention means a caller cannot run an
/// `explain` by mistake — there is no command on it to run.
///
/// The costs decide which side a gap falls on. A missing checkout is a clone
/// and a missing agent is one installer: both finish on their own over a pipe,
/// so both are offers. A sign-in needs a browser and an Xcode is fifteen
/// gigabytes behind an Apple Account: neither can be finished from here, so
/// both are explanations. Little Herd never has to decide whether a machine
/// *could* run something — only whether it can close the gap without a person
/// at the far keyboard.
nonisolated enum TransferRemedy: Equatable {
    /// A gap Little Herd can close over SSH. The command is exact and the
    /// summary is what a person reads before allowing it — because an offer is
    /// still an action on another machine, and one confirmed once, never taken
    /// as a side effect of asking.
    case offer(summary: String, command: String)

    /// A gap only the person can close, and why. No command, on purpose.
    case explain(String)

    /// Nothing to remedy: the machine is eligible, or the gap is not one this
    /// knows how to name.
    case none

    /// The one-liner that installs an agent, or nil for a provider whose
    /// install is not a single non-interactive command.
    ///
    /// **Only Claude.** Its installer is one documented pipe. Codex arrives
    /// inside the ChatGPT app or through a package manager that is a larger
    /// story, and offering a command that is not really one installer would be
    /// worse than explaining. A provider whose install cannot be completed over
    /// SSH is an `explain`, which is the same rule the type already keeps.
    static func installCommand(for provider: AgentTaskProvider) -> String? {
        switch provider {
        case .claude: "curl -fsSL https://claude.ai/install.sh | bash"
        case .codex: nil
        }
    }

    /// The remedy for one machine's eligibility.
    ///
    /// - Parameters:
    ///   - machine: what to call it in a sentence.
    ///   - originURL: the repository's remote, read from the *source* — the
    ///     machine that has the checkout. Nil when the source has no remote,
    ///     in which case a checkout cannot be cloned and the gap becomes an
    ///     explanation: there is nowhere to clone it from.
    ///   - slug: the repository's short name, which is also the folder it
    ///     clones into under `~/local-code`, the first place the probe looks.
    static func remedy(
        for eligibility: DestinationEligibility,
        machine: String,
        provider: AgentTaskProvider,
        originURL: String?,
        slug: String?
    ) -> TransferRemedy {
        switch eligibility {
        case .eligible, .unknown:
            return .none

        case .excluded:
            return .explain(
                "\(machine) is turned off for hosting work. Turn it on for that "
                    + "machine on its AI page."
            )

        case .signedOut(let install, let reason):
            // A browser, so it is the person's to do. Named, not attempted.
            return .explain(
                "\(install.providerName) is installed on \(machine) but not signed "
                    + "in (\(reason)). Sign in there — it needs a browser, which "
                    + "cannot be done from here."
            )

        case .noAgent:
            guard let command = installCommand(for: provider) else {
                return .explain(
                    "\(machine) has no \(provider.rawValue) to run, and installing "
                        + "it there is not a single command Little Herd can run over "
                        + "SSH. Install it on that machine."
                )
            }
            return .offer(
                summary: "Install \(provider.rawValue) on \(machine).",
                command: command
            )

        case .noCheckout(let repository):
            guard let originURL, let slug, !originURL.isEmpty else {
                return .explain(
                    "\(machine) has no checkout of \(repository), and the source "
                        + "has no remote to clone it from. Put a checkout on that "
                        + "machine under ~/local-code."
                )
            }
            return .offer(
                summary: "Clone \(slug) onto \(machine), at ~/local-code/\(slug).",
                // `$HOME`, not a home this cannot know: it expands on the
                // machine that runs it. `--` so a URL beginning with a dash is
                // not read as a flag; the URL is quoted, and the path is a
                // double-quoted string so `$HOME` survives while the rest is
                // literal — the slug is ours, not user text, so it needs no
                // more than that.
                command: "git clone -- \(RemoteShell.quoted(originURL)) "
                    + "\"$HOME/local-code/\(slug)\""
            )
        }
    }
}
