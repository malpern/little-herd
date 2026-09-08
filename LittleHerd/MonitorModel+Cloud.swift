import AppKit
import Foundation

extension MonitorModel {
    /// Applies a Codex cloud task in a machine's checkout.
    ///
    /// **The vendor's command, on the machine this app decided was eligible.** Item 9's
    /// rule is that cloud work moves by the vendors' own vehicles; Little Herd's whole
    /// contribution is choosing *which* machine, and it ends the moment `codex cloud
    /// apply` starts.
    ///
    /// Asked every time, like every other command that changes a machine — see
    /// `run(_:on:)`, whose shape this follows deliberately. This one changes files in a
    /// working tree somebody may be sitting in front of, so the alert names the
    /// directory as well as the machine: "on the mini" is not enough to know what is
    /// about to be written.
    func applyCloudTask(_ task: CodexCloudTask, on candidate: CodexCloudPlacement.Candidate) {
        guard let directory = candidate.directory,
              let model = machines.first(where: { $0.machine == candidate.id })
        else { return }

        let alert = NSAlert()
        alert.messageText = "Apply “\(task.title)” on \(candidate.machine)?"
        alert.informativeText =
            "Runs Codex’s own codex cloud apply in \(directory).\n\n"
            + "It changes files in that checkout. Nothing is committed or pushed, and "
            + "anything uncommitted there is yours to reconcile."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let command = task.applyCommand(in: directory)
        let host = model.sshDestination
        let identity = model.identityFile
        let isLocal = model.isLocal

        Task {
            let result: (output: String, succeeded: Bool) = isLocal
                ? await SuccessorLocal.runReportingStatus(command: command, timeout: 120)
                : await SSHCommandRunner.runReportingStatus(
                    host: host, command: command, identityFile: identity, timeout: 120
                )
            guard !result.succeeded else { return }
            // Only failures are reported, as elsewhere: an apply that worked has said so
            // by the files being different.
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "Couldn’t apply that task on \(candidate.machine)."
            failure.informativeText = result.output.isEmpty
                ? "The machine gave no reason."
                : String(result.output.suffix(400))
            failure.runModal()
        }
    }
}
