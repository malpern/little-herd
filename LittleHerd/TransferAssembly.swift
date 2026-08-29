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
        let scheme: String
    }

    enum Refusal: Equatable, Error {
        case sessionCannotBeMoved(TransferEligibility.Refusal)
        /// The destination has no checkout of the repository the work is in.
        case destinationLacksRepository
        case destinationLacksAgent
        case originUnknown
    }

    static func request(
        session: AgentSession,
        from origin: MachineID,
        to destination: MachineID,
        in herd: [DestinationAccount],
        scheme: String
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

        let branch = self.branch(for: session)
        let briefPath = "Documentation/transfers/\(branch.dropFirst("transfer/".count)).md"

        return .success(
            Request(
                transfer: Transfer(
                    origin: origin,
                    destination: destination,
                    branch: branch,
                    title: session.title ?? session.projectName,
                    repository: sourceRepository
                ),
                departure: TransferDeparture.steps(
                    repository: sourceRepository,
                    branch: branch,
                    sessionIdentifier: session.id,
                    provider: session.provider,
                    agentExecutable: installation.path,
                    promptFile: "\(sourceRepository)/.git/little-herd-prompt",
                    indexFile: "\(sourceRepository)/.git/little-herd-index",
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
                scheme: scheme
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
