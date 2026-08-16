import CryptoKit
import Foundation

/// Signs in to DSM, keeps the session id, and re-signs in when DSM drops it.
///
/// One instance per NAS. The session id is deliberately not persisted: DSM
/// invalidates sessions on its own schedule, and a stale id on disk buys
/// nothing over signing in again.
actor SynologyDSMClient {
    private let endpoint: SynologyDSMEndpoint
    private let passwordProvider: @Sendable () -> String?
    private let session: URLSession
    private let trust: SynologyTrustEvaluator

    private var sessionID: String?

    init(
        endpoint: SynologyDSMEndpoint,
        pinnedCertificate: String?,
        passwordProvider: @escaping @Sendable () -> String?
    ) {
        self.endpoint = endpoint
        self.passwordProvider = passwordProvider
        self.trust = SynologyTrustEvaluator(pinned: pinnedCertificate)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        self.session = URLSession(
            configuration: configuration,
            delegate: trust,
            delegateQueue: nil
        )
    }

    /// The certificate Little Herd saw, so a first successful connection can be
    /// recorded and every later one checked against it.
    var observedCertificate: String? { trust.observed }

    deinit { session.invalidateAndCancel() }

    // MARK: - Session

    func signIn() async throws {
        guard endpoint.isValid else {
            throw SynologyDSMError.invalidHost(endpoint.host)
        }
        guard let password = passwordProvider(), !password.isEmpty else {
            throw SynologyDSMError.notAuthenticated
        }

        let payload: DSMLoginPayload = try await request(
            api: "SYNO.API.Auth",
            version: 7,
            method: "login",
            parameters: [
                "account": endpoint.username,
                "passwd": password,
                "session": SynologyDSM.sessionName,
                "format": "sid",
            ]
        )
        sessionID = payload.sid
    }

    func signOut() async {
        guard sessionID != nil else { return }
        // Best effort: a NAS that has gone away should not make teardown throw.
        _ = try? await requestData(
            api: "SYNO.API.Auth",
            version: 7,
            method: "logout",
            parameters: ["session": SynologyDSM.sessionName]
        )
        sessionID = nil
    }

    // MARK: - Reads

    func storage() async throws -> DSMStoragePayload {
        try await authenticated(
            api: "SYNO.Storage.CGI.Storage",
            version: 1,
            method: "load_info"
        )
    }

    func utilization() async throws -> DSMUtilizationPayload {
        try await authenticated(
            api: "SYNO.Core.System.Utilization",
            version: 1,
            method: "get"
        )
    }

    /// Signs in on demand, and retries once when DSM reports the session has
    /// expired — that is routine, not a failure worth showing the user.
    private func authenticated<Payload: Decodable & Sendable>(
        api: String,
        version: Int,
        method: String
    ) async throws -> Payload {
        if sessionID == nil { try await signIn() }

        do {
            return try await request(api: api, version: version, method: method)
        } catch let error as SynologyDSMError where error.isExpiredSession {
            sessionID = nil
            try await signIn()
            return try await request(api: api, version: version, method: method)
        }
    }

    // MARK: - Transport

    private func request<Payload: Decodable & Sendable>(
        api: String,
        version: Int,
        method: String,
        parameters: [String: String] = [:]
    ) async throws -> Payload {
        let data = try await requestData(
            api: api,
            version: version,
            method: method,
            parameters: parameters
        )

        let envelope: DSMEnvelope<Payload>
        do {
            envelope = try JSONDecoder().decode(
                DSMEnvelope<Payload>.self,
                from: data
            )
        } catch {
            throw SynologyDSMError.malformedResponse(api)
        }

        guard envelope.success else {
            throw SynologyDSMError.fromAPICode(envelope.error?.code ?? -1)
        }
        guard let payload = envelope.data else {
            throw SynologyDSMError.malformedResponse("\(api) returned no data")
        }
        return payload
    }

    private func requestData(
        api: String,
        version: Int,
        method: String,
        parameters: [String: String] = [:]
    ) async throws -> Data {
        guard let url = endpoint.url(query: []) else {
            throw SynologyDSMError.invalidHost(endpoint.host)
        }

        // Everything goes in the body, including api/version/method. DSM's
        // entry.cgi reads a POST from its body alone: with these in the query
        // string it answers 101 "invalid parameter" to every call that has no
        // other parameters to send. Login happened to work, because it carries
        // credentials — so this failed only after signing in.
        //
        // It is also where credentials belong, since DSM writes request URLs to
        // its own logs, and that now covers the session id too.
        var fields = [
            "api": api,
            "version": String(version),
            "method": method,
        ]
        if let sessionID { fields["_sid"] = sessionID }
        fields.merge(parameters) { _, new in new }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        var body = URLComponents()
        body.queryItems = fields.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        request.httpBody = body.percentEncodedQuery.map { Data($0.utf8) }

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                throw SynologyDSMError.transport(
                    "DSM answered with HTTP \(http.statusCode)."
                )
            }
            return data
        } catch let error as SynologyDSMError {
            throw error
        } catch {
            if let mismatch = trust.certificateMismatch {
                throw mismatch
            }
            throw SynologyDSMError.transport(
                (error as NSError).localizedDescription
            )
        }
    }
}

// MARK: - TLS

/// Decides whether to trust the NAS's certificate.
///
/// Synology ships every unit with the same factory certificate — `CN=synology.com`,
/// issued 2015, no DNS names in its SAN — so its private key is effectively
/// public and system validation rejects it. Refusing outright would make the
/// feature unusable on a stock NAS; accepting anything would make the TLS
/// decorative. So: a certificate the system already trusts is trusted normally
/// and may rotate freely (which is what a Let's Encrypt certificate from DSM's
/// own DDNS integration does every 90 days). A certificate the system does not
/// trust is pinned to the first one seen, and any later change is refused.
final class SynologyTrustEvaluator: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let pinned: String?
    private var observedFingerprint: String?
    private var mismatch: SynologyDSMError?

    init(pinned: String?) {
        self.pinned = pinned
    }

    var observed: String? {
        lock.withLock { observedFingerprint }
    }

    var certificateMismatch: SynologyDSMError? {
        lock.withLock { mismatch }
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (
            URLSession.AuthChallengeDisposition, URLCredential?
        ) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod
            == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let fingerprint = Self.fingerprint(of: serverTrust) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        lock.withLock { observedFingerprint = fingerprint }

        // A certificate the system trusts needs no pin, and rotating it should
        // not require the user to re-approve anything.
        if SecTrustEvaluateWithError(serverTrust, nil) {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let pinned else {
            // Trust on first use: nothing recorded yet, so record what we saw.
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
            return
        }

        if pinned == fingerprint {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            lock.withLock {
                mismatch = .certificateChanged(
                    expected: pinned,
                    received: fingerprint
                )
            }
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    /// SHA-256 of the leaf certificate's public key, rather than of the whole
    /// certificate: a renewal that keeps the key keeps the pin valid.
    static func fingerprint(of trust: SecTrust) -> String? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let key = SecCertificateCopyKey(leaf),
              let data = SecKeyCopyExternalRepresentation(key, nil) as Data?
        else {
            return nil
        }
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
