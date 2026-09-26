import Foundation

/// What the watcher tells a phone.
///
/// **The one file the iPhone app and this app both compile.** Everything else
/// the phone knows about the herd arrives as this JSON, which is the whole of
/// why it can exist without IOKit, Sparkle, `ssh` or a sampler: the phone does
/// not measure, it reads what a Mac measured. Item 6 in the handoff was clear
/// that iOS must not sample — a phone will not ssh-poll in the background —
/// and the cheapest way to honour that is to give it nothing to sample with.
///
/// **Codable structs rather than the `[String: String]` rows the command line
/// prints.** The command line's encoder was written to avoid making every model
/// type `Codable` for one verb, and that reasoning still holds for the models.
/// These are not the models: they are a second, flatter shape that exists only
/// to cross a wire, so they can be `Codable` without dragging anything with
/// them. Every field a phone might draw is here already reduced — a percent,
/// a byte count, a short state — so the phone needs no knowledge of how a
/// reading was made.
///
/// Versioned from the first byte. A phone and a Mac update on different days,
/// and a reader that cannot tell which shape it was handed will guess.
nonisolated enum HerdWire {
    /// The wire format this build writes and reads.
    static let version = 1

    /// Advertised on the local network so a phone can find the watcher without
    /// being told an address. Registered in the iOS app's `NSBonjourServices`;
    /// the two must agree or the phone browses for a name nobody announces.
    static let serviceType = "_littleherd._tcp"

    /// The port the watcher listens on unless told otherwise. High enough to
    /// collide with nothing common; fixed rather than ephemeral so an address
    /// typed by hand (a Tailscale name, off the local network) keeps working
    /// across restarts.
    static let defaultPort: UInt16 = 7841

    struct Snapshot: Codable, Hashable, Sendable {
        var version: Int = HerdWire.version
        /// The Mac that made this — what the phone shows as its source.
        let watcher: String
        let generatedAt: Date
        let machines: [Machine]
    }

    struct Machine: Codable, Hashable, Identifiable, Sendable {
        let id: String
        let name: String
        let shortName: String
        /// The Herdware animal, by asset name, so the phone draws the same
        /// creature the Mac does.
        let avatar: String
        /// `macOS`, `linux` or `storage`.
        let platform: String
        let isStorage: Bool
        /// Whether this is the watcher itself.
        let isWatcher: Bool
        /// `connecting`, `live`, `offline` or `stopped`.
        let state: String
        let lastUpdated: Date?
        /// Why the machine is unreachable, in a sentence, when it is.
        let unavailability: String?
        let cpuPercent: Double?
        /// What the CPU has averaged over the last few minutes, when there is
        /// enough history to say. The current reading is for looking; this is
        /// for deciding — see `SustainedLoad`.
        let sustainedCPUPercent: Double?
        /// `normal`, `warning` or `critical`, from the kernel on a Mac and
        /// estimated from free memory elsewhere.
        let memoryPressure: String?
        let memoryUsedBytes: Double?
        let memoryTotalBytes: Double?
        let diskUsedPercent: Double?
        let volumes: [Volume]
        let sessions: [Session]

        /// Sessions actually working, the number that decides whether a
        /// machine is carrying anything.
        var activeSessionCount: Int {
            sessions.filter { $0.state == "active" }.count
        }

        /// Sessions holding for a person — what is waiting on you.
        var waitingSessionCount: Int {
            sessions.filter { $0.state == "waiting" }.count
        }
    }

    struct Volume: Codable, Hashable, Identifiable, Sendable {
        let id: String
        let name: String
        let usedBytes: Double
        let totalBytes: Double
        /// The machine's own opinion of the volume, when it has one. Only a
        /// NAS does.
        let health: String?

        var usedPercent: Double {
            guard totalBytes > 0 else { return 0 }
            return usedBytes / totalBytes * 100
        }
    }

    struct Session: Codable, Hashable, Identifiable, Sendable {
        /// The provider-prefixed identifier the Mac uses — `claude:0d5f…`.
        let id: String
        /// The first eight characters after the provider, which is what the
        /// dashboard and the command line both show and what `move` accepts.
        let short: String
        /// `claude` or `codex`.
        let provider: String
        /// `active`, `waiting`, `completed` or `stalled`.
        let state: String
        /// The session's own name, or its project's when it has none.
        let title: String
        let updatedAt: Date
        /// What it was last seen doing, as one present-tense line.
        let activity: String?
        let workingDirectory: String?
        let contextTokens: Int?
        let model: String?
    }

    // MARK: - Pairing

    /// How a phone proves it was told about this watcher.
    ///
    /// **A code a person can read off one screen and type on another.** The
    /// watcher shows it in Settings; the phone asks for it once and sends it
    /// with every read. It is not a secret against someone on the wire — this
    /// is plain HTTP on a private network — it is the difference between
    /// "anyone on the network can read the herd" and "anyone you told can",
    /// and the prerequisite for ever letting a phone *do* anything.
    ///
    /// The alphabet leaves out `0`/`O` and `1`/`I`, and comparison ignores
    /// case and punctuation, because the code will be read aloud across a
    /// room and typed on a phone keyboard.
    enum Pairing {
        static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        static let length = 8
        static let headerName = "Authorization"

        static func generate() -> String {
            String((0..<length).map { _ in alphabet.randomElement()! })
        }

        /// Upper case, letters and digits only — what both ends compare.
        static func normalize(_ text: String) -> String {
            String(text.uppercased().filter { $0.isLetter || $0.isNumber })
        }

        /// `XXXX-XXXX`, for showing.
        static func display(_ code: String) -> String {
            let normalized = normalize(code)
            guard normalized.count > 4 else { return normalized }
            let middle = normalized.index(normalized.startIndex, offsetBy: 4)
            return normalized[..<middle] + "-" + normalized[middle...]
        }

        static func headerValue(_ code: String) -> String {
            "Bearer " + normalize(code)
        }

        /// Whether a request's `Authorization` value carries this code.
        static func accepts(_ headerValue: String?, code: String) -> Bool {
            guard let headerValue else { return false }
            let presented = headerValue.hasPrefix("Bearer ")
                ? String(headerValue.dropFirst("Bearer ".count))
                : headerValue
            let expected = normalize(code)
            return !expected.isEmpty && normalize(presented) == expected
        }
    }

    // MARK: - Encoding

    /// Dates as ISO 8601, so a Mac and a phone agree on them and a person
    /// reading the wire with `curl` can too.
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
