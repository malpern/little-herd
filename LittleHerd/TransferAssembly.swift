import Foundation

/// Turns a drop into something that can actually be run, or says why not.
///
/// The last pure step. Everything the transfer needs is already in the herd
/// report — which machine has the repository checked out and where, which
/// agent it would run, what the session's working directory is — so this
/// gathers it and refuses early if any of it is missing, before a machine is
/// touched.
nonisolated enum TransferAssembly {
    struct Request: Equatable {
        let transfer: Transfer
        let departure: [TransferDeparture.Step]
        /// Everything the arrival needs once the sha is known. It cannot be
        /// built yet: the commit does not exist until the departure has run.
        let briefPath: String
        let destinationRepository: String
        let destinationAgentPath: String
        let provider: AgentTaskProvider
        let check: RepositoryCheck
    }

    enum Refusal: Equatable, Error {
        case sessionCannotBeMoved(TransferEligibility.Refusal)
        /// The destination has no checkout of the repository the work is in.
        case destinationLacksRepository
        case destinationLacksAgent
        /// The source has no agent to ask. The brief is written by the
        /// departing session, on its own machine, through that machine's own
        /// agent — so this is a different question from whether the
        /// destination can run one, and it used to be conflated with it.
        case originLacksAgent
        case originUnknown
    }

    static func request(
        session: AgentSession,
        from origin: MachineID,
        to destination: MachineID,
        in herd: [DestinationAccount],
        check: RepositoryCheck
    ) -> Result<Request, Refusal> {
        guard let source = herd.first(where: { $0.machine == origin })?.report,
              let directory = session.workingDirectory,
              let slug = source.repository(containing: directory),
              let sourceRepository = source.checkouts[slug]
        else { return .failure(.originUnknown) }

        // The source's own eligibility first: a stalled session cannot be
        // asked where it got to, and no amount of destination readiness
        // changes that.
        switch TransferEligibility.verdict(for: session, hasRepository: true) {
        case .refused(let refusal):
            return .failure(.sessionCannotBeMoved(refusal))
        case .ready, .afterItFinishes:
            break
        }

        guard let target = herd.first(where: { $0.machine == destination })?
            .report
        else { return .failure(.destinationLacksRepository) }
        guard let destinationRepository = target.checkouts[slug] else {
            return .failure(.destinationLacksRepository)
        }
        guard let installation = target.bestInstallation else {
            return .failure(.destinationLacksAgent)
        }
        // **The brief runs on the source, so it needs the source's agent.**
        // This used to pass the destination's path to the departure, which is
        // the machine the departure never touches. Two Macs with the agent in
        // the same place hid it completely; here one of them has no CLI agent
        // at all, and the step would have tried to run the other machine's
        // path locally and reported it as a missing agent.
        guard let sourceInstallation = source.bestInstallation else {
            return .failure(.originLacksAgent)
        }

        let branch = self.branch(for: session)
        let briefPath = "Documentation/transfers/\(branch.dropFirst("transfer/".count)).md"

        return .success(
            Request(
                transfer: Transfer(
                    origin: origin,
                    destination: destination,
                    branch: branch,
                    title: session.title ?? session.projectName,
                    // Read back from here too: the diff is taken locally, on
                    // the machine the work came from, and it has to be the
                    // same tree the departure pushed.
                    repository: directory
                ),
                departure: TransferDeparture.steps(
                    // The session's own directory, not `sourceRepository`.
                    // The probe finds checkouts at `~/local-code/<repo>`
                    // exactly, so a git worktree is never one of its own — and
                    // a session running in a worktree resolved to its parent,
                    // whose tree is a different commit entirely. The slug is
                    // still what says the destination has the same repository;
                    // only the path the departure operates on changes.
                    repository: directory,
                    branch: branch,
                    sessionIdentifier: session.id,
                    provider: session.provider,
                    agentExecutable: sourceInstallation.path,
                    prompt: TransferDeparture.briefRequest(
                        path: briefPath,
                        destination: herd.first {
                            $0.machine == destination
                        }?.name ?? destination.rawValue
                    ),
                    message: "Carry \(session.title ?? session.projectName)"
                ),
                briefPath: briefPath,
                destinationRepository: destinationRepository,
                destinationAgentPath: installation.path,
                provider: session.provider,
                check: check
            )
        )
    }

    /// A branch name that is legal, readable, and cannot collide with another
    /// session's.
    ///
    /// The session id is what makes it unique; the title is there so a person
    /// looking at `git branch` can tell which one it was. Git refuses plenty
    /// of characters in a ref, and a session title is free text somebody's
    /// agent chose, so everything but letters, numbers and dashes goes.
    static func branch(for session: AgentSession) -> String {
        let titleParts = (session.title ?? session.projectName)
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .split(separator: "-")
            .prefix(4)
            .joined(separator: "-")
        let title = String(titleParts)
        let identifier = session.id
            .filter { $0.isLetter || $0.isNumber }
            .prefix(8)
        return title.isEmpty
            ? "transfer/session-\(identifier)"
            : "transfer/\(title)-\(identifier)"
    }
}
