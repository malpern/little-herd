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
