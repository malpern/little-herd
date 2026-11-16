import CryptoKit
import Foundation
import os

/// Sends critical alerts to paired phones through Apple's push service.
///
/// **Token-based APNs, spoken directly** — no relay, no third-party service:
/// a JWT signed with the team's APNs key, one HTTP/2 POST per phone. The key
/// is a file this Mac reads (Settings names its path and key ID), never a
/// Keychain item, for the reason the pairing code is not one, and it is
/// refused unless only its owner can read it. Without a key configured this
/// does nothing, and the phone still hears about alerts the next time it
/// reads the herd.
///
/// Owned by `HerdWatcher`, which shares its device store and hands it to the
/// alert center while this Mac is on duty. It never listens on anything.
@MainActor
final class HerdPushRelay {
    static let keyPathKey = "herdPushKeyPath"
    static let keyIDKey = "herdPushKeyID"
    static let teamIDKey = "herdPushTeamID"
    static let defaultTeamID = "X2RKZ5TG99"
    static let topic = "com.malpern.LittleHerdMobile"

    private static let log = Logger(subsystem: "com.malpern.LittleHerd", category: "herd-push")
    private let defaults: UserDefaults
    private let devices: HerdDeviceStore
    private var credentials: Credentials?
    private var loadedConfiguration: Configuration?
    private var cachedToken: (jwt: String, issuedAt: Date)?
    private var session: URLSession?
    private(set) var lastResult: String?

    private struct Configuration: Equatable {
        let path: String
        let keyID: String
        let teamID: String
    }

    private struct Credentials {
        let configuration: Configuration
        let key: P256.Signing.PrivateKey
    }

    init(devices: HerdDeviceStore, defaults: UserDefaults = .standard) {
        self.devices = devices
        self.defaults = defaults
    }

    var isConfigured: Bool {
        reloadIfChanged()
        return credentials != nil
    }

    /// Rereads the key when Settings changed its path or ID. Cheap when they
    /// did not, so it runs before every send.
    private func reloadIfChanged() {
        let configuration = readConfiguration()
        guard configuration != loadedConfiguration else { return }
        loadedConfiguration = configuration
        updateCredentials(configuration)
    }

    private func readConfiguration() -> Configuration? {
        guard let path = defaults.string(forKey: Self.keyPathKey), !path.isEmpty,
              let keyID = defaults.string(forKey: Self.keyIDKey), Self.isAppleIdentifier(keyID)
        else { return nil }
        let teamID = defaults.string(forKey: Self.teamIDKey).flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.defaultTeamID
        guard Self.isAppleIdentifier(teamID) else { return nil }
        return Configuration(path: (path as NSString).expandingTildeInPath, keyID: keyID, teamID: teamID)
    }

    private static func isAppleIdentifier(_ value: String) -> Bool {
        value.utf8.count == 10 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) }
    }

    private func updateCredentials(_ configuration: Configuration?) {
        session?.finishTasksAndInvalidate()
        session = nil
        credentials = nil
        cachedToken = nil
        guard let configuration else { return }
        guard configuration.path.hasPrefix("/"),
              let permissions = (try? FileManager.default.attributesOfItem(atPath: configuration.path))?[.posixPermissions]
                as? NSNumber,
              permissions.intValue & 0o077 == 0,
              let pem = try? String(contentsOfFile: configuration.path, encoding: .utf8),
              let key = try? P256.Signing.PrivateKey(pemRepresentation: pem)
        else {
            Self.log.error("APNs key unreadable or its file permissions are not private")
            lastResult = "The APNs key is unreadable, or other users can read it (it must be mode 0600)."
            return
        }
        credentials = Credentials(configuration: configuration, key: key)
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 15
        session = URLSession(configuration: options)
    }

    func send(title: String, body: String, machine: MachineID, alert: MachineAlert, recovery: Bool) {
        reloadIfChanged()
        guard let credentials, let session else { return }
        let targets = devices.devices.filter { $0.pushToken != nil }
        guard !targets.isEmpty, let jwt = token(credentials) else { return }
        let event = recovery ? "recovery" : "outage"
        for device in targets {
            guard let request = Self.request(
                for: device, jwt: jwt, title: title, body: body,
                machine: machine, alert: alert, recovery: recovery
            ) else { continue }
            Task { [weak self] in
                do {
                    let (data, response) = try await session.data(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let reason = (try? JSONDecoder().decode(Rejection.self, from: data))?.reason ?? ""
                    if status == 200 {
                        Self.log.notice("APNs accepted \(event, privacy: .public)")
                        self?.lastResult = "sent"
                    } else {
                        Self.log.error("APNs rejected \(event, privacy: .public): \(status) \(reason, privacy: .public)")
                        self?.lastResult = "\(status) \(reason)"
                        // Gone for good: the app was deleted or the token rotated.
                        if status == 410 || reason == "BadDeviceToken" {
                            self?.devices.dropPushToken(for: device)
                        }
                    }
                } catch {
                    // URLSession's error text can contain the device token in the URL.
                    Self.log.error("APNs \(event, privacy: .public) transport error \((error as NSError).code)")
                    self?.lastResult = "transport error \((error as NSError).code)"
                }
            }
        }
    }

    private struct Rejection: Decodable { let reason: String }

    /// The episode id the phone uses for its own copy of an alert, so an
    /// outage pushed while the phone also read the herd replaces rather than
    /// doubles. A recovery never collapses into its outage.
    nonisolated static func collapseID(machine: MachineID, alert: MachineAlert, recovery: Bool) -> String {
        let episode = "\(machine.rawValue):\(alert.rawValue)"
        // APNs allows 64 bytes; a user-defined machine id can be longer.
        if !recovery, episode.utf8.count <= 64, episode.allSatisfy(\.isASCII) { return episode }
        let input = recovery ? episode + ":recovery" : episode
        return base64url(Data(SHA256.hash(data: Data(input.utf8))))
    }

    static func request(
        for device: HerdDevice, jwt: String, title: String, body: String,
        machine: MachineID, alert: MachineAlert, recovery: Bool
    ) -> URLRequest? {
        guard let token = device.pushToken else { return nil }
        // Pairings from before the environment was recorded were all sandbox builds.
        let environment = device.pushEnvironment ?? "development"
        guard HerdWire.PushRegistration(token: token, environment: environment).isValid else { return nil }
        let host = environment == "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com"
        guard let url = URL(string: "https://\(host)/3/device/\(token)") else { return nil }
        var message = ["title": title]
        if !body.isEmpty { message["body"] = body }
        let payload: [String: Any] = ["aps": [
            "alert": message,
            "sound": "default",
            "interruption-level": recovery ? "active" : "time-sensitive",
        ] as [String: Any], "machine": machine.rawValue]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        request.setValue(topic, forHTTPHeaderField: "apns-topic")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        request.setValue(
            collapseID(machine: machine, alert: alert, recovery: recovery),
            forHTTPHeaderField: "apns-collapse-id"
        )
        return request
    }

    /// Apple wants a fresh token at most hourly and refuses one older than an
    /// hour; forty minutes sits between the two.
    private func token(_ credentials: Credentials) -> String? {
        let now = Date.now
        if let cachedToken, (0 ..< 2400).contains(now.timeIntervalSince(cachedToken.issuedAt)) {
            return cachedToken.jwt
        }
        let configuration = credentials.configuration
        let jwt = Self.jwt(key: credentials.key, keyID: configuration.keyID, teamID: configuration.teamID, issuedAt: now)
        cachedToken = jwt.map { ($0, now) }
        return jwt
    }

    nonisolated static func jwt(
        key: P256.Signing.PrivateKey, keyID: String, teamID: String, issuedAt: Date
    ) -> String? {
        let header = #"{"alg":"ES256","kid":"\#(keyID)"}"#
        let claims = #"{"iss":"\#(teamID)","iat":\#(Int(issuedAt.timeIntervalSince1970))}"#
        let input = base64url(Data(header.utf8)) + "." + base64url(Data(claims.utf8))
        guard let signature = try? key.signature(for: Data(input.utf8)) else { return nil }
        return input + "." + base64url(signature.rawRepresentation)
    }

    nonisolated static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
