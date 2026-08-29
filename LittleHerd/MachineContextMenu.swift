import SwiftUI

/// The same machine menu, as AppKit rows — which can carry an image.
nonisolated enum MachineMenuItems {
    static func items(
        for machine: MachineConfiguration,
        onOpenPage: (() -> Void)?,
        onOpenAgents: (() -> Void)?,
        open: @escaping (URL) -> Void
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
