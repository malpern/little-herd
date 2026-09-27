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
        // **Run it, don't just find it.** A version manager's shim is on the
        // PATH whether or not it can run anything: on linux, mise's `npm` shim
        // answered `command -v` and then failed with "No version is set for
        // shim" — a preflight that passes and a check that cannot. Asking for
        // the version runs the real binary through the shim.
        let flag = tool == "xcodebuild" ? "-version" : "--version"
        return "\(toolPath) && command -v \(RemoteShell.quoted(tool)) >/dev/null && \(RemoteShell.quoted(tool)) \(flag) >/dev/null 2>&1"
    }

    /// Where a person's own toolchains live, in front of the PATH a
    /// non-interactive ssh command gets.
    ///
    /// **That PATH is `/usr/local/bin:/usr/bin:/bin` and nothing else.** A
    /// login shell adds mise, asdf and Homebrew; `ssh host 'cmd'` does not. So a
    /// linux box whose Node comes from mise — which runs its own dev servers on
    /// it — was refused a transfer for "not having npm", measured on the first
    /// real move from a phone. Agents already avoid this with absolute paths
    /// (see `AgentDestination`); a check cannot, because the check names a
    /// tool, not a location. Prepended, not replaced, and used by both the
    /// preflight and the check itself, so what approved the move is what runs.
    /// Not a login shell: that would run whatever the profile runs.
    static let toolPath = "export PATH=\"$HOME/.local/share/mise/shims:$HOME/.asdf/shims:"
        + "$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH\""


    /// What to say when the destination has the repository but not the tool.
    ///
    /// **Names the gap and stops; it installs nothing.** Where a safe line
    /// exists, `ToolRemedy` hands it to the person to run themselves — Little
    /// Herd still never decides what a machine should have. Xcode is fifteen
    /// gigabytes and an Apple Account, so there is no line for it, and saying
    /// so is more useful than a button that cannot work.
    static func missingToolReason(
        _ check: RepositoryCheck,
        on machine: String
    ) -> String {
        let tool = check.requiredExecutable ?? "the tool it needs"
        return "\(machine) has the repository but not \(tool), which is what "
            + "this project's tests are run with. Nothing was moved."
    }
}

/// What a destination has for installing a missing tool, read in one probe.
nonisolated struct ToolchainDiagnosis: Equatable, Sendable {
    var os = ""
    var hasMise = false
    /// Versions of the tool's mise plugin already installed, newest last.
    var miseVersions: [String] = []
    var hasBrew = false
    var hasPacman = false
    var hasApt = false

    /// One shell line that reports all of it as `key=value` lines. Read-only:
    /// `command -v` and `mise ls` change nothing.
    static func command(for tool: String) -> String? {
        guard let plugin = ToolRemedy.misePlugin(for: tool) else {
            return "\(RepositoryCheckProbe.toolPath); echo os=$(uname -s); "
                + "command -v brew >/dev/null && echo brew=1; "
                + "command -v pacman >/dev/null && echo pacman=1; "
                + "command -v apt-get >/dev/null && echo apt=1; true"
        }
        return "\(RepositoryCheckProbe.toolPath); echo os=$(uname -s); "
            + "command -v mise >/dev/null && { echo mise=1; "
            + "echo \"mise_versions=$(mise ls --installed \(plugin) 2>/dev/null | awk '{print $2}' | tr '\\n' ' ')\"; }; "
            + "command -v brew >/dev/null && echo brew=1; "
            + "command -v pacman >/dev/null && echo pacman=1; "
            + "command -v apt-get >/dev/null && echo apt=1; true"
    }

    static func parse(_ output: String) -> ToolchainDiagnosis {
        var diagnosis = ToolchainDiagnosis()
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "os": diagnosis.os = parts[1]
            case "mise": diagnosis.hasMise = true
            case "mise_versions":
                diagnosis.miseVersions = parts[1].split(separator: " ").map(String.init)
                    .filter { $0.first?.isNumber == true }
            case "brew": diagnosis.hasBrew = true
            case "pacman": diagnosis.hasPacman = true
            case "apt": diagnosis.hasApt = true
            default: break
            }
        }
        return diagnosis
    }
}

/// A command a person can paste to give a destination the tool a check needs.
///
/// **Offered, never run.** Little Herd still does not install anything on a
/// machine: that would be deciding what a person's computer should have. It
/// hands over the one line that would, when there is a line that is safe to
/// hand over, and says so plainly when there is not (Xcode is an App Store
/// download and an Apple Account, and no command honestly installs it).
///
/// Safest first. A version mise has *already installed* is only switched on —
/// nothing is downloaded, nothing else changes. Then the machine's own package
/// manager, for the ordinary package. The line is wrapped in `ssh` for a remote
/// machine so it can be pasted on any Mac, with `-t` when it will ask for a
/// password.
nonisolated enum ToolRemedy {
    static func misePlugin(for tool: String) -> String? {
        switch tool {
        case "npm", "node": "node"
        case "cargo": "rust"
        default: nil
        }
    }

    private static func packages(for tool: String) -> (brew: String?, pacman: String?, apt: String?) {
        switch tool {
        case "npm", "node": ("node", "nodejs npm", "nodejs npm")
        case "cargo": ("rust", "rust", "cargo")
        case "make": ("make", "make", "make")
        default: (nil, nil, nil)
        }
    }

    /// The command, or nil when nothing safe can be offered.
    /// - Parameter sshHost: the name this Mac reaches the machine by; nil for
    ///   this Mac itself.
    static func command(
        for tool: String,
        diagnosis: ToolchainDiagnosis,
        sshHost: String?
    ) -> String? {
        var line: String?
        var asksPassword = false
        let packages = packages(for: tool)
        if let plugin = misePlugin(for: tool), diagnosis.hasMise,
           let newest = diagnosis.miseVersions.last {
            line = "mise use -g \(plugin)@\(newest)"
        } else if let plugin = misePlugin(for: tool), diagnosis.hasMise {
            line = "mise use -g \(plugin)@\(plugin == "node" ? "lts" : "latest")"
        } else if diagnosis.hasBrew, let package = packages.brew {
            line = "brew install \(package)"
        } else if diagnosis.hasPacman, let package = packages.pacman {
            line = "sudo pacman -S --needed \(package)"
            asksPassword = true
        } else if diagnosis.hasApt, let package = packages.apt {
            line = "sudo apt-get install -y \(package)"
            asksPassword = true
        } else if diagnosis.os == "Darwin", tool == "make" || tool == "swift" {
            line = "xcode-select --install"
        }
        guard let line else { return nil }
        guard let sshHost, !sshHost.isEmpty else { return line }
        return "ssh \(asksPassword ? "-t " : "")\(RemoteShell.quoted(sshHost)) \(RemoteShell.quoted(line))"
    }
}
