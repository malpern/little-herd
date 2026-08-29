import SwiftUI

/// The same machine menu, as AppKit rows — which can carry an image.
nonisolated enum MachineMenuItems {
    static func items(
        for machine: MachineConfiguration,
        onOpenPage: (() -> Void)?,
        onOpenAgents: (() -> Void)?,
        open: @escaping (URL) -> Void,
        run: ((MachineCommand) -> Void)? = nil,
        bluetooth: Bool? = nil
    ) -> [AppKitMenuItem] {
        var items: [AppKitMenuItem] = []

        if let onOpenPage {
            items.append(
                AppKitMenuItem(
                    title: machine.name,
                    icon: .asset(machine.avatar.assetName),
                    action: onOpenPage
                )
            )
        }
        if let onOpenAgents {
            items.append(
                AppKitMenuItem(
                    title: "Its Agents",
                    icon: .symbol("sparkles"),
                    action: onOpenAgents
                )
            )
        }

        let actions = MachineActions.actions(for: machine)
        if !actions.isEmpty {
            items.append(.separator)
            for action in actions {
                items.append(
                    AppKitMenuItem(
                        title: action.title,
                        icon: .symbol(action.systemImage),
                        action: { open(action.url) }
                    )
                )
            }
        }

        // Things that change the machine, kept apart from things that merely
        // open a window on it.
        if let start = MachineCommands.startScreenSharing(for: machine),
           let run {
            items.append(.separator)
            items.append(
                AppKitMenuItem(
                    title: start.title,
                    icon: .symbol(start.systemImage),
                    action: { run(start) }
                )
            )
        }

        // **Universal Control cannot be checked, only pointed at.** Whether
        // two Macs share a pointer depends on the same Apple Account, Handoff,
        // and being within Bluetooth range — and of those, only Bluetooth is
        // readable. A checklist built on the rest would say "all set" when it
        // is not, which is worse than saying nothing. So this opens the pane
        // where it is turned on and claims to know nothing.
        if machine.platform == .macOS,
           let settings = URL(
               string: "x-apple.systempreferences:com.apple.Displays-Settings.extension"
           ) {
            items.append(
                AppKitMenuItem(
                    // The one thing that *is* known is said in the title,
                    // because a pointer that will not cross is a silence with
                    // four possible causes and this rules one of them out.
                    title: bluetooth == false
                        ? "Set Up Universal Control… — Bluetooth is off"
                        : "Set Up Universal Control…",
                    icon: .symbol("rectangle.on.rectangle"),
                    action: { open(settings) }
                )
            )
        }

        items.append(.separator)
        items.append(
            AppKitMenuItem(
                title: "Copy Hostname",
                icon: .symbol("doc.on.doc"),
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        machine.sshDestination,
                        forType: .string
                    )
                }
            )
        )
        return items
    }
}

/// The same agent menu, as AppKit rows.
@MainActor
enum AgentMenuItems {
    static func items(
        for session: AgentSession,
        on machine: MachineConfiguration,
        origin: AgentSessionOrigin?,
        moveTo: [AppKitMenuItem] = [],
        onOpenAgents: (() -> Void)?
    ) -> [AppKitMenuItem] {
        var items: [AppKitMenuItem] = [
            AppKitMenuItem(
                title: session.displayTitle,
                icon: .image(AgentProviderIcons.icon(for: session.provider)),
                action: onOpenAgents
            )
        ]

        // The question the card raises and cannot answer in twenty points.
        if let directory = session.workingDirectory {
            items.append(
                AppKitMenuItem(
                    title: (directory as NSString).lastPathComponent,
                    icon: .symbol("folder")
                )
            )
        }
        // Only when there is something unusual to say — see
        // `AgentSessionOrigin.label`.
        if let label = origin?.label {
            items.append(
                AppKitMenuItem(title: label, icon: .symbol("questionmark.circle"))
            )
        }

        if !moveTo.isEmpty {
            items.append(.separator)
            items.append(
                AppKitMenuItem(
                    title: "Move To",
                    icon: .symbol("arrow.right.circle"),
                    submenu: moveTo
                )
            )
        }

        items.append(.separator)
        items.append(
            AppKitMenuItem(
                title: "Copy Resume Command",
                icon: .symbol("arrow.clockwise"),
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        resumeCommand(for: session, on: machine),
                        forType: .string
                    )
                }
            )
        )
        items.append(
            AppKitMenuItem(
                title: "Copy Session ID",
                icon: .symbol("number"),
                action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(session.id, forType: .string)
                }
            )
        )
        return items
    }

    /// **Resuming happens where the session is.** A local one is a command
    /// here; a remote one needs a shell on that machine first, because
    /// `--resume` reads a transcript that exists only there.
    nonisolated static func resumeCommand(
        for session: AgentSession,
        on machine: MachineConfiguration
    ) -> String {
        let resume = switch session.provider {
        case .claude: "claude --resume \(session.id)"
        case .codex: "codex resume \(session.id)"
        }
        guard machine.connection != .local else { return resume }
        return "ssh \(machine.sshDestination) -t '\(resume)'"
    }
}
