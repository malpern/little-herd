import Foundation

/// Quoting for commands sent to another machine.
///
/// Every remote command this app sends is a *string* parsed by a shell on the
/// far side, so anything interpolated into one is interpolated into a parser.
/// `SSHHostName` already guards the host argument for this reason; this is the
/// same care applied to everything after it.
nonisolated enum RemoteShell {
    /// Wrapped in single quotes, which suspend every shell metacharacter, with
    /// embedded single quotes closed and reopened around an escaped one — the
    /// only sequence a single-quoted string cannot contain.
    static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A whole argument list, quoted and joined.
    static func quoted(_ values: [String]) -> String {
        values.map(quoted).joined(separator: " ")
    }
}
