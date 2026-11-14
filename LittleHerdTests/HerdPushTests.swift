import CryptoKit
import Foundation
import Testing

@testable import LittleHerd

@MainActor
struct HerdPushTests {
    @Test
    func iphoneCanRegisterButCannotMoveSessions() throws {
        let suite = "HerdPushTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let devices = HerdDeviceStore(defaults: defaults)
        let code = "ABCD2345"
        devices.bindToPairingCode(code)
        let server = HerdPhoneServer(devices: devices, pairingCode: code) { nil }

        let clientKey = P256.KeyAgreement.PrivateKey()
        let pairing = HerdWire.PairRequest(deviceName: "iPhone", publicKey: clientKey.publicKey.rawRepresentation)
        let pairBody = try HerdWire.encoder().encode(pairing)
        let refused = server.response(to: HerdRequest(method: "POST", path: "/pair", body: pairBody))
        #expect(String(decoding: refused, as: UTF8.self).hasPrefix("HTTP/1.1 401"))

        let accepted = server.response(to: HerdRequest(
            method: "POST", path: "/pair", headers: ["authorization": "Bearer \(code)"], body: pairBody
        ))
        let delimiter = try #require(accepted.range(of: Data("\r\n\r\n".utf8)))
        let pair = try HerdWire.decoder().decode(HerdWire.PairResponse.self, from: accepted[delimiter.upperBound...])
        let key = try HerdWire.Signing.sharedKey(
            privateKey: clientKey, peerPublicKey: pair.watcherPublicKey, pairingCode: code
        )
        let push = HerdWire.PushRegistration(token: "1234abcd", environment: "development")
        let body = try HerdWire.encoder().encode(push)
        let time = String(Int(Date.now.timeIntervalSince1970))
        let nonce = UUID().uuidString
        let canonical = HerdWire.Signing.canonical(method: "POST", path: "/push", time: time, nonce: nonce, body: body)
        let headers = [
            "x-herd-device": pair.deviceID, "x-herd-time": time, "x-herd-nonce": nonce,
            "x-herd-signature": HerdWire.Signing.signature(key: key, canonical: canonical),
        ]

        let request = HerdRequest(method: "POST", path: "/push", headers: headers, body: body)
        #expect(String(decoding: server.response(to: request), as: UTF8.self).hasPrefix("HTTP/1.1 200"))
        #expect(HerdDeviceStore(defaults: defaults).devices.first?.pushToken == push.token)
        #expect(String(decoding: server.response(to: request), as: UTF8.self).hasPrefix("HTTP/1.1 403"))
        let move = HerdRequest(method: "POST", path: "/move", headers: headers, body: body)
        #expect(String(decoding: server.response(to: move), as: UTF8.self).hasPrefix("HTTP/1.1 404"))

        devices.bindToPairingCode("FGHJ6789")
        #expect(devices.devices.isEmpty)
    }

    @Test
    func recoveryHasItsOwnNotificationInTheRegisteredEnvironment() throws {
        let device = HerdDevice(
            id: "device", name: "iPhone", key: "", pairedAt: .now, pushToken: "1234abcd", pushEnvironment: "development"
        )
        let first = try #require(HerdPushRelay.request(
            for: device, jwt: "test", title: "Mac stopped responding", body: "No answer",
            machine: .macMini, alert: .unreachable, recovery: false
        ))
        let second = try #require(HerdPushRelay.request(
            for: device, jwt: "test", title: "Mac is back", body: "",
            machine: .macMini, alert: .unreachable, recovery: true
        ))
        #expect(first.url?.host == "api.sandbox.push.apple.com")
        #expect(first.value(forHTTPHeaderField: "apns-topic") == "com.malpern.LittleHerdMobile")
        #expect(first.value(forHTTPHeaderField: "apns-collapse-id") != second.value(forHTTPHeaderField: "apns-collapse-id"))
        #expect(second.value(forHTTPHeaderField: "apns-collapse-id") != nil)
        let body = try #require(second.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(payload["machine"] as? String == MachineID.macMini.rawValue)
        let aps = try #require(payload["aps"] as? [String: Any])
        #expect(aps["alert"] as? [String: String] == ["title": "Mac is back"])
    }

    @Test
    func listenerWillNotBindToAllInterfacesOrLAN() {
        #expect(HerdPhoneServer.Binding(address: "0.0.0.0", port: 7841) == nil)
        #expect(HerdPhoneServer.Binding(address: "192.168.1.1", port: 7841) == nil)
        #expect(HerdPhoneServer.Binding(address: "100.128.0.1", port: 7841) == nil)
        #expect(HerdPhoneServer.Binding(address: "100.96.0.1", port: 7841) != nil)
    }
}
