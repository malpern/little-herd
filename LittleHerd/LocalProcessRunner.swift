import Foundation

/// Runs a short-lived helper process away from the Swift concurrency
/// cooperative pool.
///
/// Sampling actors must not block their own executor. The pool holds roughly
/// one thread per core and never grows, so a slow `lsof` — or a `ps` on a
/// loaded machine — would occupy a thread that every other task in the app is
/// competing for. Running the process on a detached task keeps the actor free
/// to serve its next call.
nonisolated enum LocalProcessRunner {
    /// The command's standard output, or `nil` when it could not be launched
    /// or exited with a non-zero status. Standard error is discarded.
    static func run(
        executablePath: String,
        arguments: [String]
    ) async -> String? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let standardOutput = Pipe()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = standardOutput
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return nil
            }

            // Drain the pipe before waiting: a child that fills the 64 KiB
            // buffer blocks on write, so waiting first would deadlock both
            // sides. Standard error goes to /dev/null, so one pipe is enough.
            let outputData = standardOutput.fileHandleForReading
                .readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: outputData, as: UTF8.self)
        }.value
    }
}
