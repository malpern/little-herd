import Foundation

/// Asking a machine what the work needs, and whether it can do it.
///
/// **The last mile of item 14, and the only part that was missing.**
/// `RepositoryCheckDetector` has been able to name a repository's check from a
/// listing of its root since 3 September, and `requiredExecutable` has been
/// able to derive the pre-flight from that check. Nothing ever took the
/// listing. So every transfer ran `TransferAssembly.check` — a constant reading
/// `xcodebuild test -scheme LittleHerd` — which is true of this project and of
/// nothing else, and would have run Xcode's tests against a Rust repository
/// without noticing.
///
/// Both questions are asked **of the destination**, because both are about the
/// destination: what is in its checkout, and what it has installed. The source
/// is not consulted about either.
nonisolated enum RepositoryCheckProbe {
    /// The names directly inside a repository root.
    ///
    /// `-1` because names are what the detector wants and a long listing would
    /// have to be unpicked; `-a` is deliberately absent, since nothing detected
    /// is a dotfile and asking for them would drag `.git` and its neighbours
    /// into a list that gets parsed. One level, not a walk: this runs on
    /// somebody else's machine and has to stay cheap.
    static func listing(of repository: String) -> String {
        "ls -1 \(RemoteShell.quoted(repository))"
    }

    /// The names, from whatever the shell printed.
    ///
    /// Blank lines and whitespace go, because a listing that ends in a newline
    /// would otherwise contribute an empty name, and an empty name matches no
    /// rule but is still a name in the list.
    static func entries(fromListing output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Reads the repository's declaration file, if it has one.
    ///
    /// A single `cat` that fails quietly when the file is absent, because
    /// absent is the ordinary case: most repositories declare nothing and are
    /// detected. `2>/dev/null` and a trailing `|| true` so a missing file is an
    /// empty answer rather than a failed step.
    static func declarationCommand(of repository: String) -> String {
        let path = "\(repository)/\(RepositoryCheck.declarationFile)"
        return "cat \(RemoteShell.quoted(path)) 2>/dev/null || true"
    }

    /// Whether the destination has the one tool this check needs.
    ///
    /// `command -v`, not `which`: `which` is a separate binary that may not
    /// exist and whose exit status is not portable, while `command` is a shell
    /// builtin that is always there and says what it found.
    static func preflight(for check: RepositoryCheck) -> String? {
        guard let tool = check.requiredExecutable else { return nil }
        return "command -v \(RemoteShell.quoted(tool))"
    }

    /// What to say when the destination has the repository but not the tool.
    ///
    /// **Names the gap and stops, and offers nothing.** The rule item 14
    /// settles: offer only what can be completed non-interactively over SSH.
    /// Xcode is fifteen gigabytes and an Apple Account, so there is no version
    /// of this that ends in an install — and saying so is more useful than a
    /// button that cannot work. It also means Little Herd never has to decide
    /// whether a machine *could* run something, only report that it does not.
    static func missingToolReason(
        _ check: RepositoryCheck,
        on machine: String
    ) -> String {
        let tool = check.requiredExecutable ?? "the tool it needs"
        return "\(machine) has the repository but not \(tool), which is what "
            + "this project's tests are run with. Nothing was moved."
    }
}
