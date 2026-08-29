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

/// Something to run on a machine rather than a URL to open.
nonisolated struct MachineCommand: Equatable {
    let title: String
    let systemImage: String
    /// Run over the ssh connection the app already holds.
    let command: String
    /// Said before it runs, because these change the machine.
    let explanation: String
}

nonisolated enum MachineCommands {
    /// **Screen sharing on a Linux box, when it can be started.**
    ///
    /// `wayvnc` is installed on this herd's Linux machine and not running, so
    /// the port is closed and the menu would otherwise offer nothing. Starting
    /// it is one command — but it is a real change to somebody else's machine,
    /// which is why this carries an explanation and is not simply done.
    static func startScreenSharing(
        for machine: MachineConfiguration
    ) -> MachineCommand? {
        guard machine.platform == .linux, machine.connection == .ssh else {
            return nil
        }
        return MachineCommand(
            title: "Start Screen Sharing",
            systemImage: "display",
            // Backgrounded and detached, or it dies with the ssh connection —
            // the same `-tt` behaviour that makes cancelling a transfer work.
            command: "nohup wayvnc --render-cursor 0.0.0.0 >/dev/null 2>&1 &",
            explanation: "Starts a VNC server on this machine so its screen "
                + "can be reached. It runs until the machine restarts."
        )
    }
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
