import Foundation

/// The things you actually do next, after looking at a machine.
///
/// **URL schemes rather than scripting another app.** `ssh://`, `vnc://` and
/// `smb://` are handled by Terminal, Screen Sharing and the Finder, so opening
/// one asks nothing of the user and needs no automation permission — where
/// driving Terminal through AppleScript would raise a prompt the first time and
/// fail silently for anyone who said no.
nonisolated struct MachineAction: Equatable, Identifiable {
    let title: String
    let systemImage: String
    let url: URL

    var id: String { url.absoluteString }
}

nonisolated enum MachineActions {
    static func actions(for machine: MachineConfiguration) -> [MachineAction] {
        // Nothing to open on the Mac this is running on: a shell here is a
        // Terminal window away, and offering to "connect" to yourself reads as
        // a mistake in the list.
        guard machine.connection != .local else { return [] }
        guard SSHHostName.isValid(machine.hostname) else { return [] }

        var actions: [MachineAction] = []
        let host = machine.hostname

        switch machine.connection {
        case .ssh:
            // The account travels with it, so a machine configured as one
            // login opens a shell on that login rather than whichever one
            // ssh would have picked.
            if let url = URL(string: "ssh://\(machine.sshDestination)") {
                actions.append(
                    MachineAction(
                        title: "Open SSH Session",
                        systemImage: "apple.terminal",
                        url: url
                    )
                )
            }
            if machine.platform == .macOS,
               let url = URL(string: "vnc://\(host)") {
                actions.append(
                    MachineAction(
                        title: "Screen Sharing",
                        systemImage: "display",
                        url: url
                    )
                )
            }
        case .dsm:
            // The NAS is a web console and a file server, and neither of those
            // is a shell: DSM restricts shell access to administrators.
            let port = machine.dsmPort ?? 5000
            if let url = URL(string: "http://\(host):\(port)") {
                actions.append(
                    MachineAction(
                        title: "Open DSM",
                        systemImage: "globe",
                        url: url
                    )
                )
            }
            if let url = URL(string: "smb://\(host)") {
                actions.append(
                    MachineAction(
                        title: "Browse Files",
                        systemImage: "folder",
                        url: url
                    )
                )
            }
        case .smb:
            if let url = URL(string: "smb://\(host)") {
                actions.append(
                    MachineAction(
                        title: "Browse Files",
                        systemImage: "folder",
                        url: url
                    )
                )
            }
        case .local:
            break
        }
        return actions
    }
}
