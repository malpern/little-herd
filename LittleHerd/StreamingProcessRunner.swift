import Foundation

/// Runs a command and hands back its output a line at a time, as it arrives.
///
/// `du -sk a b c` prints each result the moment that path is finished, so
/// waiting for the process to exit throws away the very thing that makes a slow
/// scan bearable. Reading the pipe as it fills turns one command into a stream
/// of answers: the round trips stay low, and the list still fills row by row.
///
/// Cancelling terminates the launched process. KNOWN GAP: that is not yet
/// enough. The command is a shell, and terminating it can leave the `du` it
/// started still walking /System — observed surviving the app quitting
/// altogether. The shell now traps TERM and passes it to its child, which works
/// when a signal is delivered by hand, but something in this teardown path is
/// not delivering one; a test written to prove otherwise failed, twice, in two
/// different ways. Until that is understood, Stop stops the listening and the
/// next batch, not necessarily the measurement already in flight.
nonisolated enum StreamingProcessRunner {
    static func lines(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            if let environment { process.environment = environment }
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            continuation.onTermination = { _ in
                if process.isRunning { process.terminate() }
            }

            let queue = DispatchQueue(label: "com.malpern.LittleHerd.stream")
            queue.async {
                var pending = Data()
                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                let handle = output.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    pending.append(chunk)

                    // Only whole lines are handed on; a partial one waits for
                    // the rest of its bytes rather than being reported as a
                    // truncated path.
                    while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                        let line = pending[pending.startIndex ..< newline]
                        pending.removeSubrange(pending.startIndex ... newline)
                        let text = String(decoding: line, as: UTF8.self)
                        if !text.isEmpty { continuation.yield(text) }
                    }
                }
                if !pending.isEmpty {
                    continuation.yield(String(decoding: pending, as: UTF8.self))
                }
                process.waitUntilExit()
                continuation.finish()
            }
        }
    }
}
