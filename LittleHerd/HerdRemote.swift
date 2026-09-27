import CryptoKit
import Foundation
import os

/// A phone this watcher has agreed to take writes from.
///
/// Only the derived key is kept, never either private key: the watcher's half
/// of the exchange is thrown away the moment the key exists, so there is
/// nothing to steal that would let someone pair as this watcher.
nonisolated struct HerdDevice: Codable, Equatable, Sendable {
    let id: String
    let name: String
    /// The HMAC key both ends derived, base64.
    let key: String
    let pairedAt: Date
    var pushToken: String?
    var pushEnvironment: String?
}

/// The phones that may write, in defaults beside the pairing code.
///
/// **Defaults, not the Keychain, for the same reason as the code:** this app
/// has been careful never to raise a Keychain prompt, and a prompt on a
/// headless watcher is a watcher that stops answering. The file is the
/// user's own preferences, readable only by them.
@MainActor
final class HerdDeviceStore {
    static let defaultsKey = "herdPairedDevices"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private(set) var devices: [HerdDevice] {
        get {
            guard let data = defaults.data(forKey: Self.defaultsKey) else { return [] }
            return (try? JSONDecoder().decode([HerdDevice].self, from: data)) ?? []
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.defaultsKey)
        }
    }

    /// Completes the watcher's half of the exchange and remembers the phone.
    func pair(_ request: HerdWire.PairRequest, pairingCode: String) throws -> HerdWire.PairResponse {
        let mine = P256.KeyAgreement.PrivateKey()
        let key = try HerdWire.Signing.sharedKey(
            privateKey: mine,
            peerPublicKey: request.publicKey,
            pairingCode: pairingCode
        )
        let device = HerdDevice(
            id: UUID().uuidString,
            name: String(request.deviceName.prefix(80)),
            key: key.withUnsafeBytes { Data($0) }.base64EncodedString(),
            pairedAt: .now
        )
        // One entry per phone name: re-pairing replaces rather than piling up.
        devices = devices.filter { $0.name != device.name } + [device]
        return HerdWire.PairResponse(
            deviceID: device.id,
            watcherPublicKey: mine.publicKey.rawRepresentation
        )
    }

    func key(for deviceID: String) -> SymmetricKey? {
        guard let device = devices.first(where: { $0.id == deviceID }),
              let data = Data(base64Encoded: device.key)
        else { return nil }
        return SymmetricKey(data: data)
    }

    func setPush(_ registration: HerdWire.PushRegistration, for deviceID: String) {
        devices = devices.map { device in
            guard device.id == deviceID else {
                // A token belongs to one phone; if another entry had it, that
                // entry is a stale pairing of the same phone.
                var other = device
                if other.pushToken == registration.token { other.pushToken = nil }
                return other
            }
            var updated = device
            updated.pushToken = registration.token
            updated.pushEnvironment = registration.environment
            return updated
        }
    }

    func dropPushToken(_ token: String) {
        devices = devices.map { device in
            var updated = device
            if updated.pushToken == token { updated.pushToken = nil }
            return updated
        }
    }

    /// A new pairing code retires every phone paired under the old one — the
    /// code is the salt in their keys, so they could not sign anyway.
    func removeAll() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}

/// Checks a signed write: known device, fresh clock, unseen nonce, good MAC.
@MainActor
final class HerdWriteGate {
    private var seenNonces: [String: Date] = [:]

    enum Verdict: Equatable {
        case accepted(deviceID: String)
        case refused(String)
    }

    func verify(
        _ request: HerdRequest,
        keys: (String) -> SymmetricKey?,
        now: Date = .now
    ) -> Verdict {
        let header = { (name: String) in request.headers[name.lowercased()] }
        guard let device = header(HerdWire.Signing.deviceHeader),
              let time = header(HerdWire.Signing.timeHeader),
              let nonce = header(HerdWire.Signing.nonceHeader),
              let signature = header(HerdWire.Signing.signatureHeader)
        else { return .refused("unsigned; pair this phone again") }
        guard let key = keys(device) else {
            return .refused("this phone is not paired with this watcher")
        }
        guard let seconds = TimeInterval(time),
              abs(now.timeIntervalSince1970 - seconds) <= HerdWire.Signing.window
        else { return .refused("clock too far from the watcher's") }

        seenNonces = seenNonces.filter { now.timeIntervalSince($0.value) <= HerdWire.Signing.window * 2 }
        guard seenNonces[nonce] == nil, nonce.count >= 16 else {
            return .refused("already seen")
        }
        let canonical = HerdWire.Signing.canonical(
            method: request.method,
            path: request.path,
            time: time,
            nonce: nonce,
            body: request.body
        )
        guard HerdWire.Signing.verify(key: key, canonical: canonical, signature: signature) else {
            return .refused("bad signature")
        }
        seenNonces[nonce] = now
        return .accepted(deviceID: device)
    }
}

// MARK: - Moving from a phone

extension MonitorModel {
    /// A move asked for by a phone: the plan when `dryRun`, the move itself
    /// otherwise. Goes through the same assembly and the same
    /// `beginTransfer` a drag on the dashboard does, so the phone can start
    /// nothing the Mac would not.
    func remoteMove(_ request: HerdWire.MoveRequest) async -> HerdWire.MoveResponse {
        let origin = MachineID(rawValue: request.from)
        let destination = MachineID(rawValue: request.to)
        let source = machines.first { $0.machine == origin }
        let target = machines.first { $0.machine == destination }
        let session = source?.agentSessions.first { $0.id == request.session }

        func refuse(_ reason: String, fix: String? = nil) -> HerdWire.MoveResponse {
            HerdWire.MoveResponse(
                applied: false,
                title: session.map { $0.title ?? $0.projectName } ?? request.session,
                fromName: source.map(Self.wireName) ?? request.from,
                toName: target.map(Self.wireName) ?? request.to,
                refusal: reason,
                fixesFirst: false,
                steps: [],
                fix: fix
            )
        }

        guard let source, let session else {
            return refuse("That session is no longer on \(source?.shortName ?? request.from).")
        }
        guard let target, origin != destination else {
            return refuse("There is no such machine to move it to.")
        }
        guard target.state == .live else {
            return refuse("\(target.shortName) isn’t answering right now, so it can’t take work.")
        }

        let herd = machines.map(\.destinationAccount)
        let disposition = AgentDropEligibility.disposition(
            of: destination,
            carrying: MachineAgentActivity(provider: session.provider, sessions: [session]),
            from: origin,
            in: herd,
            requiresApproval: UserDefaults.standard
                .bool(forKey: LittleHerdPreferences.requiresDestinationApprovalKey)
        )
        if case .refused(let why) = TransferEligibility.verdict(
            for: session,
            hasRepository: session.workingDirectory != nil
        ) {
            return refuse(TransferEligibility.explanation(for: why))
        }
        if disposition == .refuse {
            return refuse("\(target.shortName) can’t take this one.")
        }
        if disposition == .ready {
            switch TransferAssembly.request(
                session: session,
                from: origin,
                to: destination,
                in: herd,
                check: TransferAssembly.check
            ) {
            case .failure(let refusal):
                return refuse(HerdCommand.reason(refusal).capitalizedFirst + ".")
            case .success(let assembled) where request.dryRun:
                // **The plan asks the destination what the move itself will
                // ask**, so a missing tool is on the phone before anyone
                // presses Move — with the line that would fix it — rather than
                // in a failed card afterwards.
                if case .missingTool(let reason, let remedy) = await TransferDriver.discoverCheck(
                    repository: assembled.destinationRepository,
                    on: Self.wireName(target),
                    sshHost: target.configuration.connection == .local
                        ? nil : target.configuration.sshDestination,
                    run: TransferRunners.command(for: target.configuration)
                ) {
                    return refuse(
                        reason.replacingOccurrences(of: " Nothing was moved.", with: ""),
                        fix: remedy
                    )
                }
            case .success:
                break
            }
        }

        let fixes = disposition == .fixable
        var steps: [String] = []
        if session.state == .active {
            steps.append("Wait for its current turn on \(source.shortName) to finish")
        }
        if fixes {
            steps.append("Set up \(target.shortName) — clone the checkout or install the agent")
        }
        steps += [
            "Ask it to write down where it got to, and push that as a branch",
            "Start the agent on \(target.shortName) from that branch",
            "Run the checks and push the result",
        ]

        if !request.dryRun {
            beginTransfer(of: session, from: origin, to: destination)
        }
        return HerdWire.MoveResponse(
            applied: !request.dryRun,
            title: session.title ?? session.projectName,
            fromName: Self.wireName(source),
            toName: Self.wireName(target),
            refusal: nil,
            fixesFirst: fixes,
            steps: steps
        )
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

extension MonitorModel {
    /// "This Mac" is true only on this Mac; a phone gets its name.
    static func wireName(_ machine: MachineMonitorModel) -> String {
        machine.isLocal && machine.shortName == "This Mac" ? machine.name : machine.shortName
    }
}

// MARK: - Push

nonisolated let herdPushLog = Logger(subsystem: "com.malpern.LittleHerd", category: "herd-push")

/// Sends critical alerts to paired phones through Apple's push service.
///
/// **Token-based APNs, spoken directly** — no relay, no third-party service:
/// a JWT signed with the team's APNs key, one HTTP/2 POST per phone. The key
/// is a file this Mac reads (Settings names its path and key ID), never a
/// Keychain item, for the reason the pairing code is not one. Without a key
/// configured this does nothing, and the phone still hears about alerts the
/// next time it reads the herd.
@MainActor
final class HerdPushRelay {
    /// Set while this Mac is the watcher; the alert center hands it every
    /// alert it raises.
    static var shared: HerdPushRelay?

    static let topic = "com.malpern.LittleHerdMobile"
    static let keyPathKey = "herdPushKeyPath"
    static let keyIDKey = "herdPushKeyID"
    static let teamIDKey = "herdPushTeamID"
    static let defaultTeamID = "X2RKZ5TG99"

    private let devices: HerdDeviceStore
    private let defaults: UserDefaults
    private var cachedToken: (jwt: String, madeAt: Date, keyID: String)?
    private(set) var lastResult: String?

    init(devices: HerdDeviceStore, defaults: UserDefaults = .standard) {
        self.devices = devices
        self.defaults = defaults
    }

    var isConfigured: Bool { credentials != nil }

    private var credentials: (key: P256.Signing.PrivateKey, keyID: String, teamID: String)? {
        guard let path = defaults.string(forKey: Self.keyPathKey), !path.isEmpty,
              let keyID = defaults.string(forKey: Self.keyIDKey), !keyID.isEmpty,
              let pem = try? String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8),
              let key = try? P256.Signing.PrivateKey(pemRepresentation: pem)
        else { return nil }
        let team = defaults.string(forKey: Self.teamIDKey).flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.defaultTeamID
        return (key, keyID, team)
    }

    /// Every phone with a token hears it. `id` collapses repeats of one
    /// episode into one notification on the phone.
    func send(title: String, body: String, id: String? = nil) {
        guard let credentials else { return }
        let targets = devices.devices.compactMap { device in
            device.pushToken.map { ($0, device.pushEnvironment ?? "development") }
        }
        guard !targets.isEmpty, let jwt = token(credentials) else { return }

        var alert: [String: String] = ["title": title]
        if !body.isEmpty { alert["body"] = body }
        let payload: [String: Any] = [
            "aps": [
                "alert": alert,
                "sound": "default",
                "interruption-level": "time-sensitive",
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        for (token, environment) in targets {
            let host = environment == "production"
                ? "api.push.apple.com"
                : "api.sandbox.push.apple.com"
            guard let url = URL(string: "https://\(host)/3/device/\(token)") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = data
            request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
            request.setValue(Self.topic, forHTTPHeaderField: "apns-topic")
            request.setValue("alert", forHTTPHeaderField: "apns-push-type")
            request.setValue("10", forHTTPHeaderField: "apns-priority")
            if let id { request.setValue(String(id.prefix(64)), forHTTPHeaderField: "apns-collapse-id") }

            Task { [weak self] in
                let result: String
                do {
                    let (body, response) = try await URLSession.shared.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    result = status == 200
                        ? "sent"
                        : "\(status) \(String(decoding: body, as: UTF8.self))"
                    // Gone for good: the app was deleted or the token rotated.
                    if status == 410 || (status == 400 && result.contains("BadDeviceToken")) {
                        self?.devices.dropPushToken(token)
                    }
                } catch {
                    result = error.localizedDescription
                }
                herdPushLog.info("push \(result, privacy: .public)")
                self?.lastResult = result
            }
        }
    }

    /// Apple wants a fresh token at most hourly and refuses one older than an
    /// hour; forty minutes sits between the two.
    private func token(_ credentials: (key: P256.Signing.PrivateKey, keyID: String, teamID: String)) -> String? {
        if let cachedToken, cachedToken.keyID == credentials.keyID,
           Date.now.timeIntervalSince(cachedToken.madeAt) < 40 * 60 {
            return cachedToken.jwt
        }
        let jwt = Self.jwt(key: credentials.key, keyID: credentials.keyID, teamID: credentials.teamID, issuedAt: .now)
        cachedToken = jwt.map { ($0, .now, credentials.keyID) }
        return jwt
    }

    nonisolated static func jwt(
        key: P256.Signing.PrivateKey,
        keyID: String,
        teamID: String,
        issuedAt: Date
    ) -> String? {
        let header = #"{"alg":"ES256","kid":"\#(keyID)"}"#
        let claims = #"{"iss":"\#(teamID)","iat":\#(Int(issuedAt.timeIntervalSince1970))}"#
        let signingInput = base64url(Data(header.utf8)) + "." + base64url(Data(claims.utf8))
        guard let signature = try? key.signature(for: Data(signingInput.utf8)) else { return nil }
        return signingInput + "." + base64url(signature.rawRepresentation)
    }

    nonisolated static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
