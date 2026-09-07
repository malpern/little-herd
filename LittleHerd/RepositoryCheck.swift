import Foundation

/// How a repository proves that transferred work is good.
///
/// **Little Herd owns the command; the repository names which one and fills in
/// its blanks.** That division is the whole point of this type and it is not
/// negotiable. `SuccessorRun` says it about the old hardcoded scheme — "the
/// check and the delivery are this app's commands; a brief names which scheme
/// to build, it can never name a command line" — and making the check
/// per-repository is exactly the change that would quietly undo it. A
/// `check = "..."` string in a repository file would hand anybody who can push
/// a branch a command line on every machine that ever takes work from it,
/// which is the trust boundary the transfer design spends most of its rules
/// defending.
///
/// So this is a closed set. A repository that wants a check nobody here has
/// heard of does not get one, and that is the correct answer rather than a
/// limitation to be worked around later.
nonisolated enum RepositoryCheck: Equatable, Sendable {
    /// An Xcode scheme. The only kind that existed when this was a constant.
    case xcode(scheme: String)
    /// A Swift package — `Package.swift` and no project.
    case swiftPackage
    case cargo
    /// An npm script, which is `test` unless the repository says otherwise.
    /// The script name is a key in `package.json`, not a command.
    case npm(script: String)
    case make(target: String)
    /// Nothing to run. **Deliberately explicit**: a transfer whose check does
    /// nothing delivers unverified work, so it has to be chosen rather than
    /// arrived at by failing to detect anything.
    case none

    /// The commands to run, in order, in the successor's worktree.
    ///
    /// Argument lists rather than strings, because `RemoteShell.quoted` then
    /// quotes each element — so a scheme or script name carrying shell
    /// punctuation is passed as a literal argument rather than parsed. That is
    /// the second line of defence behind the closed set above.
    var commands: [[String]] {
        switch self {
        case .xcode(let scheme):
            [["xcodebuild", "test", "-scheme", scheme, "-destination", "platform=macOS"]]
        case .swiftPackage:
            [["swift", "test"]]
        case .cargo:
            [["cargo", "test"]]
        case .npm(let script):
            [["npm", "run", script]]
        case .make(let target):
            [["make", target]]
        case .none:
            []
        }
    }

    /// The one executable a destination must have for this check to be worth
    /// starting.
    ///
    /// **Taken from the check rather than declared beside it.** A second list
    /// of the same fact drifts — that is how the fan and the resting deck came
    /// to disagree, and how two menu implementations did — so the pre-flight
    /// is the first word of the first command and nothing else.
    var requiredExecutable: String? { commands.first?.first }

    /// Whether this is worth asking a machine about at all.
    var verifiesAnything: Bool { !commands.isEmpty }
}

nonisolated extension RepositoryCheck {
    /// The file a repository may carry to name its own check, when detection
    /// would guess wrong or cannot choose — a Swift package with an
    /// `.xcodeproj` beside it, a monorepo whose test is a make target.
    ///
    /// **The repository names a check, never a command.** This is the line the
    /// whole transfer design holds: the thing being checked must not choose its
    /// own exam. A declaration is read into the same closed set detection
    /// produces, with one blank to fill — a scheme, a script, a target — and
    /// that blank reaches an argument list already quoted, exactly as a detected
    /// one does. A repository can say "I am cargo" or "my scheme is X"; it
    /// cannot say "run curl | sh", because there is no case that carries a
    /// command line and no parser path that would build one.
    static let declarationFile = ".little-herd.toml"

    /// Parses the `[transfer]` block. Nil when the file is absent, has no such
    /// block, or names a check outside the closed set — in every one of those
    /// the caller falls back to detection, which is the safe default, so a
    /// malformed declaration weakens fidelity rather than opening a hole.
    static func declared(inTOML contents: String) -> RepositoryCheck? {
        // A hand parser, not a TOML library: this reads one table with a
        // handful of string keys, and a dependency that can do more is a
        // dependency that can be surprised into doing more.
        var inTransfer = false
        var fields: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]).trimmingCharacters(in: .whitespaces) }
            if line.isEmpty { continue }
            if line.hasPrefix("[") {
                inTransfer = (line == "[transfer]")
                continue
            }
            guard inTransfer, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            fields[key] = value
        }

        guard let kind = fields["check"] else { return nil }
        switch kind {
        case "xcode":
            // A scheme is required: `xcodebuild test` with no scheme is not a
            // check anybody meant. No scheme, no declaration — fall back.
            guard let scheme = fields["scheme"], !scheme.isEmpty else { return nil }
            return .xcode(scheme: scheme)
        case "swift": return .swiftPackage
        case "cargo": return .cargo
        case "npm": return .npm(script: fields["script"].flatMap { $0.isEmpty ? nil : $0 } ?? "test")
        case "make": return .make(target: fields["target"].flatMap { $0.isEmpty ? nil : $0 } ?? "test")
        case "none": return RepositoryCheck.none
        default:
            // An unknown kind is not an error to surface — it is a newer
            // Little Herd's vocabulary in an older one's mouth. Fall back.
            return nil
        }
    }
}

/// What a repository looks like from the outside, and what that implies.
///
/// Detection is Little Herd's, never the successor's. The agent being checked
/// must not choose its own exam, for the same reason the launcher verifies the
/// brief rather than asking the agent to verify it: a compromised or simply
/// mistaken successor would otherwise mark its own work.
nonisolated enum RepositoryCheckDetector {
    /// - Parameter entries: the names directly inside the repository root.
    ///   Names rather than paths, and one level rather than a walk, because
    ///   this has to be answerable from a cheap listing of somebody else's
    ///   machine.
    ///
    /// The order matters where a repository is more than one thing. A Swift
    /// package with an `.xcodeproj` beside it is an Xcode project as far as a
    /// check is concerned, because that is what its authors build; a Node
    /// project with a `Makefile` is usually a Node project with a convenience
    /// Makefile.
    static func check(forEntries entries: [String]) -> RepositoryCheck {
        if let project = entries.first(where: { $0.hasSuffix(".xcworkspace") })
            ?? entries.first(where: { $0.hasSuffix(".xcodeproj") })
        {
            // The scheme usually shares the project's name, and when it does
            // not the repository has to say so. Guessing further would mean
            // running `xcodebuild -list` on a machine before deciding whether
            // that machine can be used at all.
            return .xcode(
                scheme: project
                    .replacingOccurrences(of: ".xcworkspace", with: "")
                    .replacingOccurrences(of: ".xcodeproj", with: "")
            )
        }
        if entries.contains("Package.swift") { return .swiftPackage }
        if entries.contains("Cargo.toml") { return .cargo }
        if entries.contains("package.json") { return .npm(script: "test") }
        if entries.contains("Makefile") { return .make(target: "test") }
        return .none
    }
}
