import CryptoKit
import Foundation
import os

/// An opt-in sender owned by the Mac watcher. Its key stays on this Mac and
/// the phone registers using the same protocol as the original iOS pilot.
@MainActor
final class HerdPushRelay {
    static let keyPathKey = "herdPushKeyPath"
    static let keyIDKey = "herdPushKeyID"
    static let teamIDKey = "herdPushTeamID"
    static let addressKey = "herdPhoneAddress"
    static let portKey = "herdServerPort"
    static let pairingCodeKey = "herdPairingCode"

    private static let log = Logger(subsystem: "com.malpern.LittleHerd", category: "herd-push")
    private static let topic = "com.malpern.LittleHerdMobile"
    private let defaults: UserDefaults
    private let devices: HerdDeviceStore
    private var server: HerdPhoneServer?
    private var retryListener: Task<Void, Never>?
    private var credentials: Credentials?
    private var cachedToken: (jwt: String, issuedAt: Date)?
    private var session: URLSession?

    private struct Configuration: Equatable {
        let path: String
        let keyID: String
        let teamID: String
    }

    private struct Credentials {
        let configuration: Configuration
        let key: P256.Signing.PrivateKey
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.devices = HerdDeviceStore(defaults: defaults)
    }

    func reconcile(enabled: Bool, snapshot: @escaping @MainActor () -> HerdWire.Snapshot?) {
        let configuration = enabled ? readConfiguration() : nil
        if configuration != credentials?.configuration {
            updateCredentials(configuration)
        }
        let port = defaults.object(forKey: Self.portKey) == nil
            ? HerdWire.defaultPort
            : UInt16(exactly: defaults.integer(forKey: Self.portKey)) ?? 0
        guard credentials != nil,
              let binding = HerdPhoneServer.Binding(
                address: defaults.string(forKey: Self.addressKey) ?? "", port: port
              )
        else {
            retryListener?.cancel()
            retryListener = nil
            server?.reconcile(binding: nil)
            server = nil
            return
        }
        let code = pairingCode()
        server?.pairingCode = code
        if server == nil {
            server = HerdPhoneServer(devices: devices, pairingCode: code, snapshot: snapshot)
        }
        retryListener?.cancel()
        server?.reconcile(binding: binding)
        retryListener = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
                self?.server?.reconcile(binding: binding)
            }
        }
    }

    private func readConfiguration() -> Configuration? {
        guard let path = defaults.string(forKey: Self.keyPathKey), !path.isEmpty,
              let keyID = defaults.string(forKey: Self.keyIDKey), Self.isAppleIdentifier(keyID)
        else { return nil }
        let teamID = defaults.string(forKey: Self.teamIDKey) ?? "X2RKZ5TG99"
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
            return
        }
        credentials = Credentials(configuration: configuration, key: key)
        let options = URLSessionConfiguration.ephemeral
        options.timeoutIntervalForRequest = 15
        session = URLSession(configuration: options)
    }

    private func pairingCode() -> String {
        let saved = defaults.string(forKey: Self.pairingCodeKey) ?? ""
        let normalized = HerdWire.Pairing.normalize(saved)
        let code = normalized.count == HerdWire.Pairing.length ? normalized : HerdWire.Pairing.generate()
        devices.bindToPairingCode(code)
        defaults.set(code, forKey: Self.pairingCodeKey)
        return code
    }

    func send(title: String, body: String, machine: MachineID, alert: MachineAlert, recovery: Bool) {
        guard let credentials, let session else { return }
        let devices = devices.devices
        guard !devices.isEmpty, let jwt = token(credentials) else { return }
        let event = recovery ? "recovery" : "outage"
        for device in devices {
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
                    } else {
                        Self.log.error("APNs rejected \(event, privacy: .public): \(status) \(reason, privacy: .public)")
                        if status == 410 { self?.devices.dropPushToken(for: device) }
                    }
                } catch {
                    // URLSession's error text can contain the device token in the URL.
                    Self.log.error("APNs \(event, privacy: .public) transport error \((error as NSError).code)")
                }
            }
        }
    }

    private struct Rejection: Decodable { let reason: String }

    static func request(
        for device: HerdDevice, jwt: String, title: String, body: String,
        machine: MachineID, alert: MachineAlert, recovery: Bool
    ) -> URLRequest? {
        guard let token = device.pushToken, let environment = device.pushEnvironment,
              HerdWire.PushRegistration(token: token, environment: environment).isValid
        else { return nil }
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
        // Never collapse a recovery into its outage. Hashing keeps user-defined
        // machine IDs within APNs's 64-byte ASCII limit.
        let input = "\(machine.rawValue):\(alert.rawValue):\(recovery)"
        let collapseID = base64url(Data(SHA256.hash(data: Data(input.utf8))))
        request.setValue(collapseID, forHTTPHeaderField: "apns-collapse-id")
        return request
    }

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

    private nonisolated static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
