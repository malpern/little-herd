import Foundation

/// Host names reach Little Herd from Bonjour advertisements and from free-text
/// fields, so they are untrusted input. `ssh` parses any argument beginning
/// with `-` as an option, which would turn a host name such as
/// `-oProxyCommand=…` into arbitrary command execution.
///
/// Now shared with the Synology endpoint, which builds a URL rather than an
/// argument list — a hostile name cannot be smuggled into either.
nonisolated enum SSHHostName {
    private static let allowedPunctuation: Set<Character> = [
        ".", "-", "_", "@", "%", ":",
    ]

    static func isValid(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, !host.hasPrefix("-") else {
            return false
        }

        return host.allSatisfy { character in
            guard character.isASCII else { return false }
            return character.isLetter
                || character.isNumber
                || allowedPunctuation.contains(character)
        }
    }
}
