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

/// The right-click menu on a machine.
///
/// **Little Herd has been read-only staring.** You watch a machine fill up, or
/// stop answering, and then leave the app to do something about it. These are
/// the things people go and do next, put where they are already pointing.
struct MachineContextMenu: View {
    let machine: MachineConfiguration
    var onOpenPage: (() -> Void)?
    var onOpenAgents: (() -> Void)?

    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            // **The animal, in the menu.** A menu item takes any image, and
            // the herd's whole idea is that a machine is a creature rather
            // than a hostname — so the cow you right-clicked is the cow you
            // are looking at. It also does the work a header would: you can
            // tell at a glance which machine this menu belongs to, which
            // matters when four of them sit twenty points apart.
            if let onOpenPage {
                Button(action: onOpenPage) {
                    Label {
                        Text(machine.name)
                    } icon: {
                        Image(machine.avatar.assetName)
                            .resizable()
                            .scaledToFit()
                    }
                }
            }
            if let onOpenAgents {
                Button("Its Agents", systemImage: "sparkles") {
                    onOpenAgents()
                }
            }
        }

        let actions = MachineActions.actions(for: machine)
        if !actions.isEmpty {
            Section {
                ForEach(actions) { action in
                    Button(action.title, systemImage: action.systemImage) {
                        openURL(action.url)
                    }
                }
            }
        }

        Section {
            Button("Copy Hostname", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    machine.sshDestination,
                    forType: .string
                )
            }
        }
    }
}

/// The right-click menu on one agent's card.
///
/// It leads with the project, because that is the question the card raises and
/// cannot answer in twenty points of width — and because a session's own title
/// is often the more useful of the two, so both are here rather than one.
struct AgentContextMenu: View {
    let session: AgentSession
    let machine: MachineConfiguration
    var onOpenAgents: (() -> Void)?

    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            // The agent's own icon, for the same reason: these cards are
            // twenty points wide and two providers look alike at that size.
            Label {
                Text(session.displayTitle)
            } icon: {
                Image(nsImage: AgentProviderIcons.icon(for: session.provider))
                    .resizable()
                    .scaledToFit()
            }
            if let directory = session.workingDirectory {
                Text(directory)
            }
        }

        Section {
            if let onOpenAgents {
                Button("Show It On \(machine.shortName)", systemImage: "sparkles") {
                    onOpenAgents()
                }
            }
            // **Resuming happens where the session is.** A local one opens a
            // Terminal here; a remote one opens a shell on that machine first,
            // because `--resume` reads a transcript that only exists there.
            Button("Copy Resume Command", systemImage: "arrow.clockwise") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(resumeCommand, forType: .string)
            }
            Button("Copy Session ID", systemImage: "number") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
        }
    }

    private var resumeCommand: String {
        let resume = switch session.provider {
        case .claude: "claude --resume \(session.id)"
        case .codex: "codex resume \(session.id)"
        }
        guard machine.connection != .local else { return resume }
        return "ssh \(machine.sshDestination) -t '\(resume)'"
    }
}
