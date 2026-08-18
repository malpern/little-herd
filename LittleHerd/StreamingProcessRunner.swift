import Foundation

/// Runs a command and hands back its output a line at a time, as it arrives.
///
/// `du -sk a b c` prints each result the moment that path is finished, so
/// waiting for the process to exit throws away the very thing that makes a slow
/// scan bearable. Reading the pipe as it fills turns one command into a stream
/// of answers: the round trips stay low, and the list still fills row by row.
///
/// Stopping kills the process, and this is where an earlier version was wrong.
/// It hung termination on `AsyncStream`'s `onTermination`, assuming that
/// breaking out of a `for await` tears the stream down. Measured: it does not
/// fire at all, so nothing was ever terminated and a `du` walked /System long
/// after the app had quit.
///
/// Cancellation is therefore taken from the task as well as the stream. The
/// caller wraps its consumption in `withTaskCancellationHandler` and calls
/// `terminate`, which is a fact about the process rather than a guess about a
/// sequence's lifecycle.
///
/// Both paths are kept, and the distinction is worth stating precisely because
/// it was measured rather than reasoned about: `onTermination` *does* fire when
/// the consuming task is cancelled, and does *not* fire when a consumer merely
/// breaks out of the loop. The app cancels, so either would serve today; the
/// explicit terminate is what stops a future caller who breaks from silently
/// leaking a `du` across the disk.
nonisolated enum StreamingProcessRunner {
    /// The output, and a way to stop producing it. The caller must arrange for
    /// `terminate` to be reached on cancellation; nothing here can do it alone.
    struct Run: Sendable {
        let lines: AsyncThrowingStream<String, Error>
        let terminate: @Sendable () -> Void
    }

    static func lines(
        executablePath: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> Run {
        let process = Process()
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            if let environment { process.environment = environment }
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice

            // Kept as a courtesy for the paths where it does fire; the
            // caller's cancellation handler is what this actually relies on.
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

        return Run(lines: stream) {
            if process.isRunning { process.terminate() }
        }
    }
}
