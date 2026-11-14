import CryptoKit
import Foundation

/// A phone that can register an APNs token with this watcher.
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
    var pushRegisteredAt: Date? = nil
}

/// The phones that may register for push, in defaults beside the pairing code.
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
            updated.pushRegisteredAt = .now
            return updated
        }
    }

    func dropPushToken(for target: HerdDevice) {
        devices = devices.map { device in
            guard device.id == target.id, device.pushToken == target.pushToken,
                  device.pushRegisteredAt == target.pushRegisteredAt
            else { return device }
            var updated = device
            updated.pushToken = nil
            return updated
        }
    }

    /// Existing registrations belong to the code used during their key exchange.
    /// Check on launch as well as while settings are open.
    func bindToPairingCode(_ code: String) {
        let key = "herdPairedDevicesCode"
        guard defaults.string(forKey: key) != code else { return }
        defaults.removeObject(forKey: Self.defaultsKey)
        defaults.set(code, forKey: key)
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
