import AppKit
import Foundation

extension MonitorModel {
    /// Runs a one-off command on a machine, after saying what it will do.
    ///
    /// **Asked every time, and not remembered.** These are changes to a
    /// machine somebody else may be sitting at — starting a server on it, in
    /// the one case that exists today — and the app's whole posture is that it
    /// watches rather than alters. A confirmation is cheap next to discovering
    /// later that a menu started something.
    func run(_ command: MachineCommand, on machine: MachineID) {
        guard let model = machines.first(where: { $0.machine == machine }),
              !model.isLocal
        else { return }

        let alert = NSAlert()
        alert.messageText = "\(command.title) on \(model.shortName)?"
        alert.informativeText = command.explanation
        alert.addButton(withTitle: command.title)
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let host = model.sshDestination
        let identity = model.identityFile
        Task {
            let result = await SSHCommandRunner.runReportingStatus(
                host: host,
                command: command.command,
                identityFile: identity,
                timeout: 20
            )
            guard !result.succeeded else { return }
            // Only failures are reported. A command that worked has already
            // said so by the machine doing the thing.
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = "\(command.title) didn’t work."
            failure.informativeText = result.output.isEmpty
                ? "The machine gave no reason."
                : String(result.output.prefix(400))
            failure.runModal()
        }
    }
}
