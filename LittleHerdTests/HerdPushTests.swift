import CryptoKit
import Foundation
import Testing

@testable import LittleHerd

@MainActor
struct HerdPushTests {
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

    /// The phone files its own copy of an alert under the episode id, so a
    /// pushed outage with the same id replaces it rather than doubling.
    @Test
    func anOutageCollapsesIntoThePhonesOwnCopy() {
        #expect(HerdPushRelay.collapseID(machine: .macMini, alert: .unreachable, recovery: false)
            == "\(MachineID.macMini.rawValue):\(MachineAlert.unreachable.rawValue)")
        let long = MachineID(rawValue: String(repeating: "m", count: 80))
        #expect(HerdPushRelay.collapseID(machine: long, alert: .unreachable, recovery: false).utf8.count <= 64)
    }

    @Test
    func aMalformedTokenIsNeverSentTo() {
        let device = HerdDevice(
            id: "device", name: "iPhone", key: "", pairedAt: .now, pushToken: "../not-hex", pushEnvironment: "development"
        )
        #expect(HerdPushRelay.request(
            for: device, jwt: "test", title: "t", body: "",
            machine: .macMini, alert: .unreachable, recovery: false
        ) == nil)
    }
}
