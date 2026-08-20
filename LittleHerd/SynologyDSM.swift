import Foundation

/// Talks to a Synology NAS through DSM's Web API instead of reading a mounted
/// SMB share.
///
/// A mounted share can only ever answer "how full is this volume", and only
/// while the Finder happens to have it mounted. DSM answers in the NAS's own
/// terms — pools, volumes, and the health of each physical drive — over a port
/// that is already open, so a NAS with a failing disk can say so.
nonisolated enum SynologyDSM {
    /// DSM rejects a session whose name collides with another client's, so this
    /// stays distinct from the `DownloadStation`/`FileStation` names DSM's own
    /// clients use.
    static let sessionName = "LittleHerd"
    static let defaultPort = 5001
}

// MARK: - Errors

nonisolated enum SynologyDSMError: Error, Equatable, Sendable {
    case invalidHost(String)
    case notAuthenticated
    case transport(String)
    case malformedResponse(String)
    /// DSM answered, but refused. The code is DSM's own; `detail` is our
    /// reading of it.
    case api(code: Int, detail: String)
    case certificateChanged(expected: String, received: String)

    /// DSM reports every failure as a bare integer, and the integers that
    /// matter most here are the ones a user can actually fix.
    static func fromAPICode(_ code: Int) -> Self {
        .api(code: code, detail: detailForAPICode(code))
    }

    static func detailForAPICode(_ code: Int) -> String {
        switch code {
        // The 100-block is Little Herd asking wrongly, not the user doing
        // anything wrong. Worth naming so it is never mistaken for a
        // credential problem.
        case 101: "DSM rejected the request parameters."
        case 102: "This NAS does not offer the API Little Herd asked for."
        case 103: "This NAS does not offer the method Little Herd asked for."
        case 104: "This NAS runs a DSM version Little Herd cannot use here."
        case 400: "Wrong account or password."
        case 401: "That DSM account is disabled."
        case 402: "That account lacks permission. Storage details need an account in DSM's administrators group."
        case 403: "That account requires two-factor authentication, which Little Herd cannot answer. Use a dedicated account with 2FA turned off."
        case 404: "Two-factor code rejected."
        case 406: "DSM requires two-factor authentication to be enforced for this account."
        case 407: "DSM has blocked this Mac's IP address."
        case 408: "That account's password has expired and must be changed in DSM."
        case 409: "That account's password has expired."
        case 410: "DSM requires that account to change its password before signing in."
        case 119: "DSM rejected the session. Little Herd will sign in again."
        default: "DSM returned error \(code)."
        }
    }

    /// A signed-in session that DSM has since invalidated. Worth distinguishing
    /// because the fix is to log in again rather than to bother the user.
    var isExpiredSession: Bool {
        if case .api(let code, _) = self { return code == 119 || code == 105 }
        return false
    }

    var detail: String {
        switch self {
        case .invalidHost(let host): "\(host) is not a usable hostname."
        case .notAuthenticated: "Not signed in to DSM."
        case .transport(let message): message
        case .malformedResponse(let what): "DSM sent something unreadable: \(what)."
        case .api(_, let detail): detail
        case .certificateChanged:
            "The NAS presented a different TLS certificate than the one Little Herd recorded. Little Herd stopped rather than send credentials to it."
        }
    }

    /// The first characters of a fingerprint, which is where two of them
    /// differ if they differ at all.
    static func abbreviated(_ fingerprint: String) -> String {
        guard fingerprint.count > 10 else { return fingerprint }
        return String(fingerprint.prefix(8)) + "…"
    }

    /// What the sign-in sheet says, and which of its own branches refused.
    ///
    /// The sheet used to report `detail` alone, which for a transport failure
    /// is whatever string URLSession handed up — "A TLS error caused the secure
    /// connection to fail." That sentence is true, unactionable, and identical
    /// whether the NAS is unplugged, the certificate was swapped, or the app
    /// itself is misconfigured. An evening went into a bug the sheet already
    /// knew enough to describe.
    ///
    /// So every refusal names its stage. There are only four, and they have
    /// nothing to do with each other: Little Herd declining to ask, the network
    /// never getting there, the certificate check refusing, and DSM itself
    /// saying no. Which one it was is most of the diagnosis, and it is the one
    /// thing the raw error never says.
    func explanation(host: String) -> SynologySignInExplanation {
        switch self {
        case .invalidHost(let host):
            .init(
                stage: .beforeAsking,
                headline: "“\(host)” is not a usable address.",
                evidence: nil
            )
        case .notAuthenticated:
            .init(
                stage: .beforeAsking,
                headline: "Little Herd has no password to send.",
                evidence: nil
            )
        case .certificateChanged(let expected, let received):
            .init(
                stage: .certificate,
                headline: "“\(host)” presented a different certificate than the one Little Herd recorded, so nothing was sent to it.",
                // One line rather than two: the sheet has a fixed height that
                // was set after it once clipped the password field, so evidence
                // that grows without bound is a layout bug waiting to happen.
                // The full pair is here to be copied and hovered, not read.
                evidence: "Expected \(expected) · Received \(received)",
                // Enough of each to compare at a glance. A fingerprint differs
                // from its neighbour in the first characters or not at all, so
                // the head is the part worth showing.
                displayEvidence: "Expected \(Self.abbreviated(expected)) · Received \(Self.abbreviated(received))"
            )
        case .api(let code, let detail):
            .init(stage: .dsm, headline: detail, evidence: "DSM error \(code)")
        case .malformedResponse(let what):
            .init(
                stage: .dsm,
                headline: "“\(host)” answered with something Little Herd could not read.",
                evidence: what
            )
        case .transport(let message):
            SynologyTransportProblem.classify(message)
                .explanation(host: host, underlying: message)
        }
    }
}

/// A refusal, said in the sheet's own voice rather than the layer below's.
nonisolated struct SynologySignInExplanation: Equatable, Sendable {
    /// Which branch refused. Four unrelated situations that used to look the
    /// same; the interface tints and captions them differently so the shape of
    /// the problem is legible before the sentence is read.
    enum Stage: Equatable, Sendable {
        /// Little Herd never asked — the address or the password is missing.
        case beforeAsking
        /// Nothing got as far as the NAS.
        case network
        /// The NAS answered and its certificate was refused.
        case certificate
        /// DSM answered and said no.
        case dsm

        var caption: String {
            switch self {
            case .beforeAsking: "Nothing was sent"
            case .network: "Could not reach the NAS"
            case .certificate: "Certificate refused"
            case .dsm: "DSM refused"
            }
        }
    }

    let stage: Stage
    let headline: String
    /// The specifics in full — fingerprints, a DSM code, the original message.
    /// Kept because a sentence a person can act on and the string an engineer
    /// needs are rarely the same one, and discarding the second to get the
    /// first is how the certificate fingerprints went missing in the first
    /// place. This is what a tooltip shows and what selecting the line copies.
    let evidence: String?
    /// The same thing, short enough to survive one line.
    ///
    /// Two 64-character fingerprints on a 420-point line truncate in the middle
    /// to `Expected aa…bbbbbbbbbbbb` — the expected value gone entirely, the
    /// received one reduced to a run of identical characters, and no way to
    /// tell which is which. It read as text on screen and as nothing at all to
    /// a person. Rendering the sheet is what caught it; the test asserting both
    /// fingerprints were present passed throughout, because they were.
    var displayEvidence: String?

    init(
        stage: Stage,
        headline: String,
        evidence: String?,
        displayEvidence: String? = nil
    ) {
        self.stage = stage
        self.headline = headline
        self.evidence = evidence
        // Most evidence is already short enough to show as it is.
        self.displayEvidence = displayEvidence ?? evidence
    }
}

/// Why a DSM request never got an answer, classified once.
///
/// This used to live privately inside `RemoteUnavailability` for the tooltip,
/// so the sign-in sheet — the surface with a person actually watching — had no
/// access to it and printed the raw string instead. One home, two readers.
nonisolated enum SynologyTransportProblem: Equatable, Sendable {
    case nameNotFound
    case noAnswer
    case refused
    /// macOS wording for a denied Local Network permission, which is actively
    /// misleading about a NAS on the same desk and points at the wrong fix.
    case localNetworkBlocked
    case tlsRefused
    case unknown(String)

    static func classify(_ message: String) -> Self {
        let text = message.lowercased()
        if text.contains("internet connection appears to be offline") {
            return .localNetworkBlocked
        }
        if text.contains("hostname could not be found")
            || text.contains("could not be found")
            || text.contains("nodename")
        {
            return .nameNotFound
        }
        if text.contains("tls") || text.contains("ssl")
            || text.contains("secure connection")
        {
            return .tlsRefused
        }
        if text.contains("timed out") || text.contains("not connect") {
            return .noAnswer
        }
        if text.contains("refused") { return .refused }
        return .unknown(message)
    }

    func explanation(
        host: String,
        underlying: String
    ) -> SynologySignInExplanation {
        switch self {
        case .nameNotFound:
            .init(
                stage: .network,
                headline: "“\(host)” did not resolve. Check whether Tailscale is connected.",
                evidence: underlying
            )
        case .noAnswer:
            .init(
                stage: .network,
                headline: "“\(host)” did not answer. It may be asleep, or on a network this Mac cannot see.",
                evidence: underlying
            )
        case .refused:
            .init(
                stage: .network,
                headline: "“\(host)” refused the connection. Check that DSM is listening on this port.",
                evidence: underlying
            )
        case .localNetworkBlocked:
            .init(
                stage: .network,
                headline: "macOS is blocking Little Herd from reaching your local network. Allow it under System Settings → Privacy & Security → Local Network.",
                evidence: underlying
            )
        case .tlsRefused:
            // Named as its own thing because it is not a password problem and
            // not the NAS being down, and it was mistaken for both.
            .init(
                stage: .certificate,
                headline: "The secure connection to “\(host)” failed before Little Herd could check its certificate.",
                evidence: underlying
            )
        case .unknown(let message):
            .init(stage: .network, headline: message, evidence: nil)
        }
    }
}

// MARK: - Endpoint

nonisolated struct SynologyDSMEndpoint: Equatable, Sendable {
    var host: String
    var port: Int
    var username: String

    init(host: String, port: Int = SynologyDSM.defaultPort, username: String) {
        self.host = host
        self.port = port
        self.username = username
    }

    /// Reuses the SSH host validator so a Bonjour-advertised name can no more
    /// smuggle something into a URL than it could into an ssh argument list.
    var isValid: Bool {
        SSHHostName.isValid(host) && port > 0 && port <= 65535
            && !username.isEmpty
    }

    func url(query: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = port
        components.path = "/webapi/entry.cgi"
        components.queryItems = query
        return components.url
    }
}

// MARK: - Decoded payloads

/// DSM writes byte counts as strings often enough that a plain `Double` key
/// fails on half of real responses. Everything numeric goes through this.
nonisolated struct DSMNumber: Decodable, Sendable {
    let value: Double

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self),
                  let double = Double(string) {
            value = double
        } else {
            value = 0
        }
    }
}

nonisolated struct DSMEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let success: Bool
    let data: Payload?
    let error: DSMErrorBody?

    struct DSMErrorBody: Decodable, Sendable {
        let code: Int
    }
}

nonisolated struct DSMLoginPayload: Decodable, Sendable {
    let sid: String
}

/// The shape of `SYNO.Storage.CGI.Storage` `load_info`. Every field is optional
/// because DSM varies these across versions and models, and a missing drive
/// temperature should not cost us the volume sizes.
nonisolated struct DSMStoragePayload: Decodable, Sendable {
    let volumes: [Volume]?
    let disks: [Disk]?

    struct Volume: Decodable, Sendable {
        let id: String?
        /// Absent on DS-series DSM 7 — `display_name` came back null on a real
        /// unit, so the name has to be built from `desc` or the id.
        let displayName: String?
        let desc: String?
        let volPath: String?
        let status: String?
        let summaryStatus: String?
        let size: Size?

        struct Size: Decodable, Sendable {
            let total: DSMNumber?
            let used: DSMNumber?
            /// Not sent by every model. When it is missing, free space is
            /// derived from `total - used`.
            let free: DSMNumber?
        }

        enum CodingKeys: String, CodingKey {
            case id, desc, status, size
            case displayName = "display_name"
            case volPath = "vol_path"
            case summaryStatus = "summary_status"
        }
    }

    struct Disk: Decodable, Sendable {
        let id: String?
        let name: String?
        let model: String?
        let status: String?
        let smartStatus: String?
        /// DSM's own rolled-up verdict, and the only field that caught a drive
        /// with 229 uncorrectable sectors on a real unit — `status` and
        /// `smart_status` both still read "normal" for it.
        let overviewStatus: String?
        let summaryStatusKey: String?
        /// Uncorrectable sector count. Any non-zero value is damage, whatever
        /// the status strings say.
        let unc: DSMNumber?
        let temp: DSMNumber?

        enum CodingKeys: String, CodingKey {
            case id, name, model, status, temp, unc
            case smartStatus = "smart_status"
            case overviewStatus = "overview_status"
            case summaryStatusKey = "summary_status_key"
        }
    }
}

/// `SYNO.Core.System.Utilization` `get`. Memory figures are kilobytes.
nonisolated struct DSMUtilizationPayload: Decodable, Sendable {
    let cpu: CPU?
    let memory: Memory?

    struct CPU: Decodable, Sendable {
        let userLoad: DSMNumber?
        let systemLoad: DSMNumber?
        let otherLoad: DSMNumber?

        enum CodingKeys: String, CodingKey {
            case userLoad = "user_load"
            case systemLoad = "system_load"
            case otherLoad = "other_load"
        }
    }

    struct Memory: Decodable, Sendable {
        let memoryTotal: DSMNumber?
        /// Usable RAM, which is slightly less than `memory_size` — DSM's own
        /// percentage is computed against this one.
        let totalReal: DSMNumber?
        let availReal: DSMNumber?
        let availSwap: DSMNumber?
        let cached: DSMNumber?
        let buffer: DSMNumber?
        /// DSM's own used percentage. Preferred over anything we compute, so the
        /// dashboard agrees with DSM's UI.
        let realUsage: DSMNumber?

        enum CodingKeys: String, CodingKey {
            case memoryTotal = "memory_size"
            case totalReal = "total_real"
            case availReal = "avail_real"
            case availSwap = "avail_swap"
            case realUsage = "real_usage"
            case cached, buffer
        }
    }
}

// MARK: - Drive health

nonisolated enum SynologyHealth: String, Equatable, Sendable {
    case normal
    case warning
    case critical
    case unknown

    /// Ordering for "show the worst first". Unknown sits below normal: it is
    /// the absence of news, not bad news.
    var severity: Int {
        switch self {
        case .critical: 3
        case .warning: 2
        case .normal: 1
        case .unknown: 0
        }
    }

    var label: String {
        switch self {
        case .normal: "Healthy"
        case .warning: "Warning"
        case .critical: "Failing"
        case .unknown: "Unknown"
        }
    }

    var symbolName: String {
        switch self {
        case .normal: "internaldrive"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        case .unknown: "questionmark.circle"
        }
    }

    /// DSM spells the same condition several ways depending on model and
    /// version, so match on what the strings have in common rather than
    /// enumerating every observed spelling.
    /// Order matters: "abnormal" contains "normal", so a healthy match tested
    /// first would read a degrading drive as fine. Damage always wins.
    ///
    /// "attention" and "danger" are the words DSM uses for volumes and pools —
    /// a real unit reported a volume as "attention" while every drive string
    /// said "normal", and without these it fell through to `.unknown`.
    static func parse(_ raw: String?) -> SynologyHealth {
        guard let raw = raw?.lowercased(), !raw.isEmpty else { return .unknown }
        if raw.contains("critical") || raw.contains("fail")
            || raw.contains("crashed") || raw.contains("danger") {
            return .critical
        }
        if raw.contains("warning") || raw.contains("abnormal")
            || raw.contains("degrade") || raw.contains("attention") {
            return .warning
        }
        if raw.contains("normal") || raw.contains("good") || raw == "ok" {
            return .normal
        }
        return .unknown
    }
}

nonisolated struct SynologyDrive: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let model: String
    let health: SynologyHealth
    /// Uncorrectable sectors DSM has counted. Non-zero is the most concrete
    /// evidence a drive is going, and worth showing outright.
    let uncorrectableSectors: Int
    /// Celsius. `nil` when DSM did not report one for this drive.
    let temperatureCelsius: Double?

    init(
        id: String,
        name: String,
        model: String,
        health: SynologyHealth,
        uncorrectableSectors: Int = 0,
        temperatureCelsius: Double?
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.health = health
        self.uncorrectableSectors = uncorrectableSectors
        self.temperatureCelsius = temperatureCelsius
    }
}

// MARK: - Parsing into Little Herd's own types

nonisolated enum SynologyDSMParser {
    /// DSM reports a volume's size in bytes already; unlike `df` there is no
    /// block-size conversion to get wrong.
    static func storageVolumes(
        from payload: DSMStoragePayload
    ) -> [StorageVolume] {
        (payload.volumes ?? []).compactMap { volume -> StorageVolume? in
            guard let size = volume.size,
                  let total = size.total?.value, total > 0 else { return nil }

            // Prefer DSM's own free figure. Deriving it from `used` disagrees
            // with what DSM's UI shows, because a volume reserves space that
            // counts as neither used nor free.
            let available = size.free?.value
                ?? max(total - (size.used?.value ?? 0), 0)
            let id = volume.id ?? volume.displayName ?? "volume"

            return StorageVolume(
                id: "dsm:\(id)",
                name: name(for: volume, id: id),
                // DSM's own path, so the row names something that exists on the
                // NAS rather than a bare identifier.
                mountPath: volume.volPath ?? id,
                availableBytes: min(available, total),
                totalBytes: total,
                volumeCount: 1,
                // Worst of the two, for the same reason drives take the worst of
                // theirs: a degraded pool shows up here even when no single
                // drive has been condemned.
                health: worse(
                    SynologyHealth.parse(volume.status),
                    SynologyHealth.parse(volume.summaryStatus)
                )
            )
        }
    }

    /// What to call a volume. `display_name` is null on real DSM 7 units and
    /// `desc` is empty unless the owner typed one, so the fallback turns
    /// "volume_1" into "Volume 1" rather than showing the raw identifier.
    static func name(for volume: DSMStoragePayload.Volume, id: String) -> String {
        if let displayName = volume.displayName, !displayName.isEmpty {
            return displayName
        }
        if let desc = volume.desc?.trimmingCharacters(in: .whitespaces),
           !desc.isEmpty {
            return desc
        }
        return id
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    static func drives(from payload: DSMStoragePayload) -> [SynologyDrive] {
        (payload.disks ?? []).map { disk in
            let id = disk.id ?? disk.name ?? UUID().uuidString
            let temperature = disk.temp?.value

            // Every verdict DSM offers, worst wins. On a real unit a drive with
            // 229 uncorrectable sectors reported status "normal" and
            // smart_status "normal" while overview_status said "critical";
            // reading any single field would have called it healthy.
            var health = [
                disk.overviewStatus,
                disk.summaryStatusKey,
                disk.smartStatus,
                disk.status,
            ].map(SynologyHealth.parse).reduce(SynologyHealth.unknown, worse)

            // Uncorrectable sectors are damage regardless of what the status
            // strings claim.
            if (disk.unc?.value ?? 0) > 0 {
                health = worse(health, .warning)
            }

            return SynologyDrive(
                id: id,
                name: disk.name ?? id,
                model: (disk.model ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
                health: health,
                uncorrectableSectors: Int(disk.unc?.value ?? 0),
                temperatureCelsius: (temperature ?? 0) > 0 ? temperature : nil
            )
        }
    }

    static func worse(_ lhs: SynologyHealth, _ rhs: SynologyHealth) -> SynologyHealth {
        lhs.severity >= rhs.severity ? lhs : rhs
    }

    /// Sums the volumes the way the disk overview reads them: one figure for the
    /// whole NAS, with the per-volume detail carried alongside.
    static func diskReading(for volumes: [StorageVolume]) -> MetricReading? {
        let total = volumes.reduce(0) { $0 + $1.totalBytes }
        guard total > 0 else { return nil }
        let available = volumes.reduce(0) { $0 + $1.availableBytes }
        let usedPercent = (total - available) / total * 100
        return MetricReading(
            value: min(max(usedPercent, 0), 100),
            auxiliaryValue: available,
            capacity: total
        )
    }

    static func cpuReading(
        from payload: DSMUtilizationPayload
    ) -> MetricReading? {
        guard let cpu = payload.cpu else { return nil }
        let load = (cpu.userLoad?.value ?? 0)
            + (cpu.systemLoad?.value ?? 0)
            + (cpu.otherLoad?.value ?? 0)
        return MetricReading(value: min(max(load, 0), 100))
    }

    /// DSM's utilization memory figures are kilobytes, and `avail_real` excludes
    /// cache and buffers — which macOS would count as available. Adding them
    /// back keeps a NAS's memory row comparable to a Mac's.
    static func memoryReading(
        from payload: DSMUtilizationPayload
    ) -> MetricReading? {
        guard let memory = payload.memory else { return nil }
        // `total_real` is usable RAM and is what DSM's own percentage is
        // computed against; `memory_size` is the physical total and reads a few
        // points higher.
        let totalKB = memory.totalReal?.value ?? memory.memoryTotal?.value ?? 0
        guard totalKB > 0 else { return nil }

        let availableKB = (memory.availReal?.value ?? 0)
            + (memory.cached?.value ?? 0)
            + (memory.buffer?.value ?? 0)
        let total = totalKB * 1024
        let available = min(availableKB * 1024, total)
        // Prefer DSM's own figure so the dashboard and DSM's UI agree; fall back
        // to our own arithmetic only when DSM does not report one.
        let usedPercent = memory.realUsage?.value
            ?? (total - available) / total * 100

        return MetricReading(
            value: min(max(usedPercent, 0), 100),
            auxiliaryValue: available,
            capacity: total
        )
    }
}
