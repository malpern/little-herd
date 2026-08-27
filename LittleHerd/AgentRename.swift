import Foundation

/// Renames a Codex thread through the app server's own protocol.
///
/// The one first-party way to do this, and it was verified against a live
/// thread before any of it was written: `initialize`, then
/// `thread/name/set { threadId, name }`, then reading the name back to see it
/// had taken. Codex treats a thread name as a first-class mutable property —
/// `resume`, `archive` and `delete` all accept "id or session name" — so this
/// is the same thing the desktop app changes, not a file being edited behind
/// its back.
///
/// **Codex only, deliberately.** Claude Code renames the same idea by
/// appending a `custom-title` line to its own transcript, which is an internal
/// file format rather than an interface, and a running session has not been
/// shown to notice one written from outside. Renaming half a herd through a
/// supported door beats renaming all of it through a window.
nonisolated enum AgentRenamer {
    enum Failure: Error, Equatable {
        /// The provider has no supported way to do this.
        case unsupported(AgentTaskProvider)
        /// The app server answered, and said no.
        case refused(String)
        /// It never answered.
        case noAnswer
    }

    /// - Parameters:
    ///   - threadID: Codex's own thread id, which is the session id Little
    ///     Herd already reads from the rollout.
    ///   - install: which Codex, and where. An absolute path resolved now
    ///     rather than remembered: the runtime carries its version in its path
    ///     and replaces the directory when it updates.
    static func rename(
        threadID: String,
        to name: String,
        using install: AgentInstallation,
        isLocal: Bool,
        host: String,
        identityFile: String?
    ) async -> Result<Void, Failure> {
        guard install.provider == .codex else {
            return .failure(.unsupported(install.provider))
        }

        let requests = [
            AppServerRequest.initialize(),
            AppServerRequest.setName(threadID: threadID, to: name),
        ]

        let reply = await AppServerSession.exchange(
            requests: requests,
            awaiting: 2,
            install: install,
            isLocal: isLocal,
            host: host,
            identityFile: identityFile
        )

        switch reply {
        case .none:
            return .failure(.noAnswer)
        case .some(let response) where response.error != nil:
            return .failure(.refused(response.error ?? ""))
        case .some:
            return .success(())
        }
    }
}

/// One JSON-RPC request, built rather than assembled from a dictionary.
///
/// Deliberately not `[String: Any]`: that is not `Sendable`, and this crosses
/// into a detached task. The two shapes this needs are known, so they are
/// spelled out and the encoding is checked once, here.
nonisolated struct AppServerRequest: Sendable {
    let id: Int
    let method: String
    private let params: Params

    private enum Params: Sendable {
        case client(name: String, version: String)
        case setName(threadID: String, name: String)
    }

    static func initialize() -> AppServerRequest {
        AppServerRequest(
            id: 1,
            method: "initialize",
            params: .client(name: "Little Herd", version: "1")
        )
    }

    static func setName(threadID: String, to name: String) -> AppServerRequest {
        AppServerRequest(
            id: 2,
            method: "thread/name/set",
            params: .setName(threadID: threadID, name: name)
        )
    }

    var line: String? {
        let encoded: [String: Any]
        switch params {
        case let .client(name, version):
            encoded = ["clientInfo": ["name": name, "version": version]]
        case let .setName(threadID, name):
            encoded = ["threadId": threadID, "name": name]
        }
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": encoded,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}

nonisolated struct AppServerResponse: Equatable, Sendable {
    let id: Int
    let error: String?
}

/// One conversation with `codex app-server`, spoken over its stdin and stdout.
nonisolated enum AppServerSession {
    /// Long enough for a local process to start and answer; short enough that
    /// a wedged one does not hold the caller. Renaming is a metadata write —
    /// it does not wait on a model — so this is far below the ninety seconds
    /// the authentication probe needs.
    static let timeout: TimeInterval = 20

    /// Finds the reply to `awaiting`, ignoring notifications and the replies
    /// to everything before it.
    ///
    /// The app server is chatty and does not answer in order, so a reader that
    /// takes the first line back will eventually take a notification and call
    /// it a result.
    static func response(
        matching id: Int,
        in output: String
    ) -> AppServerResponse? {
        for line in output.split(whereSeparator: \.isNewline) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let message = object as? [String: Any],
                  message["id"] as? Int == id
            else {
                continue
            }
            let error = message["error"] as? [String: Any]
            let description = error?["message"] as? String
                ?? error.map { "\($0)" }
            return AppServerResponse(id: id, error: description)
        }
        return nil
    }

    /// Sends each request only once the previous one has been answered.
    ///
    /// Not a batch, and that is the protocol's requirement rather than a
    /// preference. Writing `initialize` and `thread/name/set` together and
    /// closing stdin gets the first answered and **the second silently
    /// dropped** — measured, twice, once in a spike that worked because it
    /// happened to wait and once here in a version that did not.
    static func exchange(
        requests: [AppServerRequest],
        awaiting id: Int,
        install: AgentInstallation,
        isLocal: Bool,
        host: String,
        identityFile: String?
    ) async -> AppServerResponse? {
        let lines = requests.compactMap(\.line)
        guard lines.count == requests.count else { return nil }

        let quoted = "'" + install.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = "\(quoted) app-server"

        return await Task.detached(priority: .userInitiated) {
            let process = Process()
            let inPipe = Pipe()
            let outPipe = Pipe()

            if isLocal {
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", command]
            } else {
                guard SSHHostName.isValid(host) else { return nil }
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                // No pseudo-terminal, unlike the authentication probe: one
                // would echo what is written to stdin back into the stream
                // this parses, and there is nothing to cancel here.
                process.arguments = SSHCommandRunner.arguments(
                    host: host,
                    command: command,
                    identityFile: identityFile
                )
            }
            process.standardInput = inPipe
            process.standardOutput = outPipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                return nil
            }

            let watchdog = ProbeWatchdog(process: process, after: timeout)
            defer {
                try? inPipe.fileHandleForWriting.close()
                if process.isRunning { process.terminate() }
                _ = watchdog.finish()
            }

            let reader = LineReader(handle: outPipe.fileHandleForReading)
            var answer: AppServerResponse?

            for (offset, line) in lines.enumerated() {
                inPipe.fileHandleForWriting.write(Data((line + "\n").utf8))
                let wanted = requests[offset].id
                guard let reply = reader.readReply(
                    matching: wanted,
                    deadline: Date().addingTimeInterval(timeout)
                ) else {
                    return nil
                }
                if wanted == id { answer = reply }
                // A failure part-way through is the whole exchange failing:
                // there is no point asking for a rename of a server that
                // refused to say hello.
                if reply.error != nil { return reply }
            }
            return answer
        }.value
    }
}

/// Reads one newline-delimited JSON message at a time from a pipe.
///
/// The app server interleaves notifications with replies and does not answer
/// in order, so a reader that takes the next line back will eventually take a
/// `remoteControl/status/changed` and call it a result.
// `nonisolated` because this project defaults actor isolation to
// MainActor, and this is used from inside a detached task.
private nonisolated final class LineReader {
    private let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) { self.handle = handle }

    func readReply(matching id: Int, deadline: Date) -> AppServerResponse? {
        while Date() < deadline {
            while let line = nextLine() {
                if let reply = AppServerSession.response(
                    matching: id,
                    in: String(decoding: line, as: UTF8.self)
                ) {
                    return reply
                }
            }
            let chunk = handle.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
        return nil
    }

    private func nextLine() -> Data? {
        guard let index = buffer.firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }
        let line = buffer[buffer.startIndex ..< index]
        buffer.removeSubrange(buffer.startIndex ... index)
        return Data(line)
    }
}
