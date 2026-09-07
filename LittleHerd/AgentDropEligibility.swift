import Foundation

/// Whether a machine could take the token being carried over it.
///
/// The drag's `canAccept` used to say yes to every machine but the one the
/// token came from, which made the refusal states unreachable. This asks the
/// question `DestinationEligibility` was written to answer, and every part of
/// the answer is a real measurement: the destination has an agent this account
/// can run, it has a checkout of the repository the work is in, and its
/// provider has not refused the credentials.
///
/// **Whether intent is asked at all is a setting, off by default.** With
/// `requiresDestinationApproval` off — the shipped default — every machine
/// that *could* run the work will take it, and `mayHostSessions` is not
/// consulted. That is deliberate: Little Herd reaches these machines over the
/// user's own SSH keys, so a transfer starts nothing they could not already
/// start from a shell. The switch is an accident boundary, not a security one.
///
/// **Turning it on must not brick the herd, and nearly did.**
/// `mayHostSessions` defaults to *off*, so gating on it while nothing can set
/// it refuses every machine with no way for anyone to say otherwise — a
/// default outliving its control. The per-machine allowance on the machine's
/// AI page is what makes the switch usable, and it appears only when the
/// switch is on, so the setting and its setter arrive together or not at all.
nonisolated enum AgentDropEligibility {
    /// - Parameters:
    ///   - activity: what is in hand.
    ///   - origin: where it was picked up, which supplies the checkouts that
    ///     name the repository the work is in.
    ///   - herd: every account, including the origin's.
    ///   - requiresApproval: `LittleHerdPreferences.requiresDestinationApprovalKey`.
    static func eligibility(
        of machine: MachineID,
        carrying activity: MachineAgentActivity,
        from origin: MachineID,
        in herd: [DestinationAccount],
        requiresApproval: Bool = false
    ) -> DestinationEligibility {
        guard machine != origin,
              let destination = herd.first(where: { $0.machine == machine })
        else { return .excluded }

        return DestinationEligibility.resolve(
            report: destination.report,
            repository: repository(of: activity, from: origin, in: herd),
            isAllowed: requiresApproval ? destination.mayHostSessions : true,
            auth: destination.auth
        )
    }

    /// What a drag can do with a machine: take it as it is, offer to make it
    /// ready first, or not land on it at all.
    ///
    /// **Three states, because a gap is not one thing.** A machine that lacks
    /// the checkout or an agent Little Herd can install is one a drop can
    /// *prepare* — so it should lift to meet the drag, and the drop offers the
    /// fix. A machine whose gap needs a browser or an Apple Account cannot be
    /// prepared from here and stays put, the way an ineligible machine always
    /// has. The eligible case is unchanged.
    enum DropDisposition: Equatable, Sendable {
        case ready
        case fixable
        case refuse
    }

    /// **Optimistic about a checkout, honest at the drop.** Whether a missing
    /// checkout can be cloned depends on the source having a remote, which is a
    /// URL this cannot read during a drag without a command per frame. So a
    /// missing checkout is `fixable` here and the real remedy — clone or,
    /// if the source has no remote, an explanation — is computed when the card
    /// lands. A missing agent is `fixable` only for a provider whose install is
    /// one non-interactive command, because that is the only kind `--fix` runs.
    static func disposition(
        of machine: MachineID,
        carrying activity: MachineAgentActivity,
        from origin: MachineID,
        in herd: [DestinationAccount],
        requiresApproval: Bool = false
    ) -> DropDisposition {
        let e = eligibility(
            of: machine, carrying: activity, from: origin,
            in: herd, requiresApproval: requiresApproval
        )
        if e.isEligible { return .ready }
        switch e {
        case .noCheckout:
            return .fixable
        case .noAgent:
            return TransferRemedy.installCommand(for: activity.provider) != nil
                ? .fixable : .refuse
        case .eligible, .signedOut, .excluded, .unknown:
            return .refuse
        }
    }

    static func canAccept(
        _ machine: MachineID,
        carrying activity: MachineAgentActivity,
        from origin: MachineID,
        in herd: [DestinationAccount],
        requiresApproval: Bool = false
    ) -> Bool {
        eligibility(
            of: machine, carrying: activity, from: origin,
            in: herd, requiresApproval: requiresApproval
        )
        .isEligible
    }

    /// The repository the carried work is in, named by the origin.
    ///
    /// Nothing in a session says which repository it belongs to — only where it
    /// is working. The origin's own report is the translation: it maps every
    /// repository slug to the directory it is checked out in, so the session's
    /// working directory can be matched against them.
    ///
    /// **The busiest session decides**, which is the same session whose
    /// provider the token is drawn with. A token standing for two sessions in
    /// two different repositories can only ask about one of them, and asking
    /// about the one the token already represents is the answer a person can
    /// predict. Nil when nothing matches, and then the checkout question is
    /// not asked of anybody rather than being guessed at.
    static func repository(
        of activity: MachineAgentActivity,
        from origin: MachineID,
        in herd: [DestinationAccount]
    ) -> String? {
        guard let source = herd.first(where: { $0.machine == origin })?.report,
              let directory = activity.sessions.first?.workingDirectory
        else { return nil }
        return source.repository(containing: directory)
    }
}

nonisolated extension DestinationReport {
    /// Which of this account's checkouts a directory sits in.
    ///
    /// The longest match wins, so a repository checked out inside another —
    /// a submodule, or a worktree under a parent — is named as itself rather
    /// than as its container.
    func repository(containing directory: String) -> String? {
        checkouts
            .filter { _, path in
                directory == path || directory.hasPrefix(path + "/")
            }
            .max { $0.value.count < $1.value.count }?
            .key
    }
}
