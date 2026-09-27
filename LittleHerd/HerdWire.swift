import CryptoKit
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
        // Everything below is optional and was added after version 1 shipped:
        // an older watcher simply omits it, and an older phone ignores it, so
        // neither end needs the other to update first.
        /// Moves in flight or just finished, newest first.
        var transfers: [Transfer]? = nil
        /// The critical events the watcher's own alerts are raising right now —
        /// what a phone turns into notifications.
        var alerts: [Alert]? = nil
        /// Whether this watcher accepts signed writes (`/pair`, `/move`). A
        /// watcher that does not is read-only, and the phone hides moving.
        var acceptsWrites: Bool? = nil
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
        /// Recent readings, oldest first, thinned to a few dozen points.
        var cpuHistory: [Point]? = nil
        var memoryHistory: [Point]? = nil
        /// What is using the CPU, busiest first, as a share of the whole
        /// machine rather than of one core.
        var processes: [Process]? = nil
        /// What is holding memory, largest first.
        var memoryConsumers: [Consumer]? = nil

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
        /// Whether it can be moved, and where to. Absent from a read-only
        /// watcher.
        var move: Move? = nil
    }

    struct Point: Codable, Hashable, Sendable {
        let t: Date
        let v: Double
    }

    struct Process: Codable, Hashable, Identifiable, Sendable {
        var id: String { name + (pid.map { ":\($0)" } ?? "") }
        let name: String
        let pid: Int?
        /// Share of the whole machine, 0–100.
        let percent: Double?
        /// Cores in use, for when there is no core count to divide by.
        let cores: Double
        /// Set when the process is an agent's, with what it is doing.
        let agent: String?
    }

    struct Consumer: Codable, Hashable, Identifiable, Sendable {
        var id: String { name }
        let name: String
        let bytes: Double
        /// Growth over the observed window, when it has been rising.
        let growingBytes: Double?
    }

    /// The move verdict for one session, taken from `TransferEligibility` and
    /// `AgentDropEligibility` on the watcher so the phone decides nothing.
    struct Move: Codable, Hashable, Sendable {
        /// `ready`, `afterItFinishes` or `refused`.
        let verdict: String
        /// Why not, in a sentence, when refused.
        let reason: String?
        /// Machines that would take it; `fixable` means the watcher sets the
        /// machine up first, as a phase you can watch.
        let destinations: [Destination]
    }

    struct Destination: Codable, Hashable, Sendable {
        let machine: String
        /// `ready` or `fixable`.
        let disposition: String
    }

    struct Transfer: Codable, Hashable, Identifiable, Sendable {
        /// The branch carrying the work — unique per move.
        let id: String
        let title: String
        let origin: String
        let destination: String
        /// `fixing`, `preparing`, `running`, `landed` or `failed`.
        let phase: String
        /// 0–1.
        let progress: Double
        /// What it is doing now, or why it stopped.
        let detail: String?
        /// A command that would clear a refusal, for a person to run.
        var fix: String? = nil
    }

    struct Alert: Codable, Hashable, Identifiable, Sendable {
        /// `machine:kind` — stable for as long as the condition lasts, so a
        /// phone notifies once per episode rather than once per read.
        let id: String
        let machine: String
        let kind: String
        let title: String
        let body: String
    }

    // MARK: - Writes

    /// A phone asking to be trusted with writes. Sent with the pairing code,
    /// once; the answer is the watcher's half of a key exchange.
    struct PairRequest: Codable, Sendable {
        let deviceName: String
        /// The phone's P-256 key-agreement public key, raw representation.
        let publicKey: Data
    }

    struct PairResponse: Codable, Sendable {
        let deviceID: String
        let watcherPublicKey: Data
    }

    struct MoveRequest: Codable, Sendable {
        /// The provider-prefixed session id.
        let session: String
        let from: String
        let to: String
        /// True asks what would happen and changes nothing — the plan the
        /// phone shows before a person confirms. The command line's exit 2.
        let dryRun: Bool
    }

    struct MoveResponse: Codable, Hashable, Sendable {
        /// False for a plan or a refusal: nothing was started.
        let applied: Bool
        let title: String
        let fromName: String
        let toName: String
        /// Present when the move cannot go ahead.
        let refusal: String?
        /// Set up first, when the destination lacks the checkout or agent.
        let fixesFirst: Bool
        /// What will happen, in order, for a person deciding.
        let steps: [String]
        /// A command that would clear the refusal, for a person to run —
        /// never run by the watcher.
        var fix: String? = nil
    }

    struct PushRegistration: Codable, Sendable {
        /// The APNs device token, hex.
        let token: String
        /// `development` or `production`, from the app's entitlement.
        let environment: String
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

    // MARK: - Signing

    /// How a paired phone signs a write, and how the watcher checks it.
    ///
    /// **The pairing code gates reads; it cannot gate a transfer.** It crosses
    /// the wire in the clear on every read, so anyone who can see the traffic
    /// has it. Writes use a key neither end ever sends: at pairing, each side
    /// makes a P-256 key pair and sends only the public half, and both derive
    /// the same secret from their own private key and the other's public one.
    /// Someone watching sees two public keys and cannot compute it. Every write
    /// is then an HMAC over the method, path, a timestamp, a one-time nonce and
    /// the body, so a captured request cannot be replayed or altered.
    ///
    /// The pairing code is mixed in as salt, so a code change retires every
    /// device paired under the old one.
    enum Signing {
        static let deviceHeader = "X-Herd-Device"
        static let timeHeader = "X-Herd-Time"
        static let nonceHeader = "X-Herd-Nonce"
        static let signatureHeader = "X-Herd-Signature"
        /// How far a request's clock may be from the watcher's.
        static let window: TimeInterval = 120

        static func sharedKey(
            privateKey: P256.KeyAgreement.PrivateKey,
            peerPublicKey: Data,
            pairingCode: String
        ) throws -> SymmetricKey {
            let peer = try P256.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey)
            let secret = try privateKey.sharedSecretFromKeyAgreement(with: peer)
            return secret.hkdfDerivedSymmetricKey(
                using: SHA256.self,
                salt: Data(Pairing.normalize(pairingCode).utf8),
                sharedInfo: Data("little-herd write v1".utf8),
                outputByteCount: 32
            )
        }

        static func canonical(
            method: String,
            path: String,
            time: String,
            nonce: String,
            body: Data
        ) -> Data {
            let bodyHash = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
            return Data([method.uppercased(), path, time, nonce, bodyHash].joined(separator: "\n").utf8)
        }

        static func signature(key: SymmetricKey, canonical: Data) -> String {
            Data(HMAC<SHA256>.authenticationCode(for: canonical, using: key)).base64EncodedString()
        }

        static func verify(key: SymmetricKey, canonical: Data, signature: String) -> Bool {
            guard let presented = Data(base64Encoded: signature) else { return false }
            return HMAC<SHA256>.isValidAuthenticationCode(presented, authenticating: canonical, using: key)
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
