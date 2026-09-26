import CryptoKit
import Foundation
import Testing

@testable import LittleHerd

/// A phone asking the watcher to do something, not just to say something.
///
/// The claims these pin are the ones that made moving from a phone safe to
/// build at all: someone who can read the traffic — and so has the pairing
/// code — still cannot forge, replay or alter a write.
@Suite("Herd writes")
@MainActor
struct HerdWriteTests {
    static let code = "ABCD2345"

    /// A fresh store in its own defaults suite, so tests never touch the
    /// watcher's real paired phones.
    private func store() -> HerdDeviceStore {
        let suite = "HerdWriteTests.\(UUID().uuidString)"
        return HerdDeviceStore(defaults: UserDefaults(suiteName: suite)!)
    }

    /// Pairs a phone the way the app does, returning the key it derived.
    private func pair(
        _ store: HerdDeviceStore,
        code: String = Self.code
    ) throws -> (id: String, key: SymmetricKey) {
        let phone = P256.KeyAgreement.PrivateKey()
        let answer = try store.pair(
            HerdWire.PairRequest(deviceName: "Test iPhone", publicKey: phone.publicKey.rawRepresentation),
            pairingCode: code
        )
        let key = try HerdWire.Signing.sharedKey(
            privateKey: phone,
            peerPublicKey: answer.watcherPublicKey,
            pairingCode: code
        )
        return (answer.deviceID, key)
    }

    private func signed(
        path: String = "/move",
        body: Data,
        id: String,
        key: SymmetricKey,
        time: Date = .now,
        nonce: String = UUID().uuidString
    ) -> HerdRequest {
        let seconds = String(Int(time.timeIntervalSince1970))
        let canonical = HerdWire.Signing.canonical(
            method: "POST", path: path, time: seconds, nonce: nonce, body: body
        )
        return HerdRequest(
            method: "POST",
            path: path,
            headers: [
                HerdWire.Signing.deviceHeader.lowercased(): id,
                HerdWire.Signing.timeHeader.lowercased(): seconds,
                HerdWire.Signing.nonceHeader.lowercased(): nonce,
                HerdWire.Signing.signatureHeader.lowercased():
                    HerdWire.Signing.signature(key: key, canonical: canonical),
            ],
            body: body
        )
    }

    /// Both ends arrive at the same key without either sending it.
    @Test
    func bothEndsDeriveTheSameKey() throws {
        let store = store()
        let phone = try pair(store)
        let watcherKey = try #require(store.key(for: phone.id))
        #expect(watcherKey == phone.key)
    }

    @Test
    func aSignedWriteIsAccepted() throws {
        let store = store()
        let phone = try pair(store)
        let request = signed(body: Data("{}".utf8), id: phone.id, key: phone.key)
        #expect(HerdWriteGate().verify(request, keys: store.key(for:)) == .accepted(deviceID: phone.id))
    }

    /// The one attack a replayable code invited: capture a request, send it
    /// again. The nonce has been spent.
    @Test
    func aCapturedWriteCannotBeReplayed() throws {
        let store = store()
        let phone = try pair(store)
        let gate = HerdWriteGate()
        let request = signed(body: Data("{}".utf8), id: phone.id, key: phone.key)
        #expect(gate.verify(request, keys: store.key(for:)) == .accepted(deviceID: phone.id))
        #expect(gate.verify(request, keys: store.key(for:)) == .refused("already seen"))
    }

    /// Changing where a move goes, after it was signed, breaks the signature.
    @Test
    func anAlteredBodyIsRefused() throws {
        let store = store()
        let phone = try pair(store)
        var request = signed(body: Data(#"{"to":"linux"}"#.utf8), id: phone.id, key: phone.key)
        request.body = Data(#"{"to":"macMini"}"#.utf8)
        #expect(HerdWriteGate().verify(request, keys: store.key(for:)) == .refused("bad signature"))
    }

    /// A signature from last week is not a request from now.
    @Test
    func aStaleClockIsRefused() throws {
        let store = store()
        let phone = try pair(store)
        let request = signed(
            body: Data(), id: phone.id, key: phone.key,
            time: Date.now.addingTimeInterval(-HerdWire.Signing.window - 30)
        )
        #expect(HerdWriteGate().verify(request, keys: store.key(for:)) == .refused("clock too far from the watcher's"))
    }

    /// Someone who read the pairing code off the wire can compute neither
    /// key: signing with a key derived from the code alone fails.
    @Test
    func knowingTheCodeIsNotEnoughToSign() throws {
        let store = store()
        let phone = try pair(store)
        let guessed = SymmetricKey(data: SHA256.hash(data: Data(Self.code.utf8)))
        let request = signed(body: Data(), id: phone.id, key: guessed)
        #expect(HerdWriteGate().verify(request, keys: store.key(for:)) == .refused("bad signature"))
    }

    /// A phone paired under an old code has a key salted with it; a new code
    /// forgets every such phone rather than leaving entries that can't work.
    @Test
    func aNewCodeForgetsEveryPhone() throws {
        let store = store()
        let phone = try pair(store)
        store.removeAll()
        let request = signed(body: Data(), id: phone.id, key: phone.key)
        #expect(HerdWriteGate().verify(request, keys: store.key(for:))
            == .refused("this phone is not paired with this watcher"))
    }

    // MARK: - Through the server

    private func writes(_ store: HerdDeviceStore, moves: @escaping (HerdWire.MoveRequest) -> HerdWire.MoveResponse) -> HerdWrites {
        let gate = HerdWriteGate()
        return HerdWrites(
            pair: { try store.pair($0, pairingCode: Self.code) },
            verify: { gate.verify($0, keys: store.key(for:)) },
            move: moves,
            registerPush: { store.setPush($0, for: $1) }
        )
    }

    private static func status(_ response: Data) -> String {
        String(decoding: response.prefix(while: { $0 != 13 }), as: UTF8.self)
    }

    /// `/pair` is the only write the code alone admits; without it, 401.
    @Test
    func pairingNeedsTheCode() throws {
        let body = try HerdWire.encoder().encode(
            HerdWire.PairRequest(deviceName: "x", publicKey: P256.KeyAgreement.PrivateKey().publicKey.rawRepresentation)
        )
        let response = HerdServer.response(
            for: HerdRequest(method: "POST", path: "/pair", body: body),
            pairingCode: Self.code,
            snapshot: { HerdWire.Snapshot(watcher: "w", generatedAt: .now, machines: []) },
            writes: writes(store()) { _ in fatalError("not reached") }
        )
        #expect(Self.status(response) == "HTTP/1.1 401 Unauthorized")
    }

    /// A move carrying only the code — what a sniffer could send — is refused
    /// before the model is ever asked.
    @Test
    func aMoveWithOnlyTheCodeNeverReachesTheModel() throws {
        let body = try HerdWire.encoder().encode(
            HerdWire.MoveRequest(session: "claude:x", from: "a", to: "b", dryRun: false)
        )
        var reached = false
        let response = HerdServer.response(
            for: HerdRequest(
                method: "POST",
                path: "/move",
                headers: ["authorization": HerdWire.Pairing.headerValue(Self.code)],
                body: body
            ),
            pairingCode: Self.code,
            snapshot: { HerdWire.Snapshot(watcher: "w", generatedAt: .now, machines: []) },
            writes: writes(store()) { _ in
                reached = true
                fatalError("a move must not run unsigned")
            }
        )
        #expect(Self.status(response) == "HTTP/1.1 403 Forbidden")
        #expect(!reached)
    }

    /// A read-only watcher stays read-only: no writes wired, 405.
    @Test
    func aWatcherWithoutWritesRefusesPost() {
        let response = HerdServer.response(
            for: HerdRequest(method: "POST", path: "/move"),
            pairingCode: Self.code,
            snapshot: { HerdWire.Snapshot(watcher: "w", generatedAt: .now, machines: []) }
        )
        #expect(Self.status(response) == "HTTP/1.1 405 Method Not Allowed")
    }

    /// The body is read whole before the request exists — a write answered
    /// half-read would be signed over bytes it never saw.
    @Test
    func aBodyIsWaitedForByItsLength() {
        let head = Data("POST /move HTTP/1.1\r\nContent-Length: 5\r\n\r\nab".utf8)
        #expect(HerdRequest.parse(head) == nil)
        #expect(HerdRequest.parse(head + Data("cde".utf8))?.body == Data("abcde".utf8))
    }

    // MARK: - Push

    /// The token Apple is sent: three base64url parts, ES256, and a
    /// signature the key's own public half verifies.
    @Test
    func theAPNsTokenIsAValidES256JWT() throws {
        let key = P256.Signing.PrivateKey()
        let jwt = try #require(HerdPushRelay.jwt(key: key, keyID: "KEY123", teamID: "TEAM", issuedAt: .now))
        let parts = jwt.split(separator: ".").map(String.init)
        #expect(parts.count == 3)
        #expect(!jwt.contains("=") && !jwt.contains("+") && !jwt.contains("/"))

        func decode(_ part: String) -> Data? {
            var base64 = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while base64.count % 4 != 0 { base64 += "=" }
            return Data(base64Encoded: base64)
        }
        let header = try #require(decode(parts[0]))
        #expect(String(decoding: header, as: UTF8.self).contains(#""kid":"KEY123""#))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: try #require(decode(parts[2])))
        #expect(key.publicKey.isValidSignature(signature, for: Data((parts[0] + "." + parts[1]).utf8)))
    }
}
