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
/// **Intent is deliberately left out, and this is the one thing to know before
/// changing it.** `DestinationEligibility.resolve` gates on
/// `MachineConfiguration.mayHostSessions`, which defaults to *off* and whose
/// only setter — a checkbox in Settings — was removed on 25 August as
/// pre-solving. Asking the full question today would therefore return
/// `.excluded` for every machine in the herd, and the herd would refuse a drag
/// everywhere with no way for anyone to say otherwise. That is not the safety
/// posture the default was written for; it is the default outliving its
/// control. So this asks the measured half and says so, and when a new
/// destination interface brings the setter back, this becomes
/// `resolve(isAllowed:)` and the tests below change with it.
nonisolated enum AgentDropEligibility {
    /// - Parameters:
    ///   - activity: what is in hand.
    ///   - origin: where it was picked up, which supplies the checkouts that
    ///     name the repository the work is in.
    ///   - herd: every account, including the origin's.
    static func eligibility(
        of machine: MachineID,
        carrying activity: MachineAgentActivity,
        from origin: MachineID,
        in herd: [DestinationAccount]
    ) -> DestinationEligibility {
        guard machine != origin,
              let destination = herd.first(where: { $0.machine == machine })
        else { return .excluded }

        return DestinationEligibility.resolve(
            report: destination.report,
            repository: repository(of: activity, from: origin, in: herd),
            // See the note above: measured only, because intent has no control.
            isAllowed: true,
            auth: destination.auth
        )
    }

    static func canAccept(
        _ machine: MachineID,
        carrying activity: MachineAgentActivity,
        from origin: MachineID,
        in herd: [DestinationAccount]
    ) -> Bool {
        eligibility(of: machine, carrying: activity, from: origin, in: herd)
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
