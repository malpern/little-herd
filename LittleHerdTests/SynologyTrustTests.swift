import CryptoKit
import Foundation
import Security
import Testing
@testable import LittleHerd

/// The certificate-pinning path, exercised against the actual certificate the
/// Synology presents.
///
/// This is the part of the feature with no other coverage: if the fingerprint
/// cannot be extracted the trust evaluator cancels every challenge and the NAS
/// simply never connects. The fixture is the DER the unit served, so this fails
/// if the extraction ever stops working on a real Synology certificate.
struct SynologyTrustTests {
    /// Captured from AlpernServer.local:5001 — the factory certificate Synology
    /// ships on every unit (CN=synology.com, issued 2015, no DNS names in its
    /// SAN), which is why system validation rejects it and pinning exists.
    private static let factoryCertificateDER = """
        MIIDLTCCApagAwIBAgIHFDkVlGAXXjANBgkqhkiG9w0BAQsFADCBpzELMAkGA1UEBhMCVFcxDzAN
        BgNVBAgMBlRhaXdhbjEPMA0GA1UEBwwGVGFpcGVpMRYwFAYDVQQKDA1TeW5vbG9neSBJbmMuMR4w
        HAYDVQQLDBVDZXJ0aWZpY2F0ZSBBdXRob3JpdHkxGTAXBgNVBAMMEFN5bm9sb2d5IEluYy4gQ0Ex
        IzAhBgkqhkiG9w0BCQEWFHByb2R1Y3RAc3lub2xvZ3kuY29tMB4XDTE1MDgwOTIyMzEwMFoXDTM1
        MDQyNjIyMzEwMFowgZYxCzAJBgNVBAYTAlRXMQ8wDQYDVQQIDAZUYWl3YW4xDzANBgNVBAcMBlRh
        aXBlaTEWMBQGA1UECgwNU3lub2xvZ3kgSW5jLjERMA8GA1UECwwIRlRQIFRlYW0xFTATBgNVBAMM
        DHN5bm9sb2d5LmNvbTEjMCEGCSqGSIb3DQEJARYUcHJvZHVjdEBzeW5vbG9neS5jb20wgZ8wDQYJ
        KoZIhvcNAQEBBQADgY0AMIGJAoGBANRn6V57aJPLjrrXk1vfN/AiT3OHYOe5FseQHZSB5l9cgU8c
        SFeeIlOGBDONGa7tRSBB6siH/O4SAaqxm7GSANjsNJp2kuYhGzZZjm4B63URdz+ZRo9QFiIBp3G1
        6T4ZZIx9nSvkHqMMVcuSPdVPI48KctlbgoG68AoSDipcfa6zAgMBAAGjcjBwMB8GA1UdEQQYMBaB
        FHByb2R1Y3RAc3lub2xvZ3kuY29tMDoGCWCGSAGG+EIBDQQtFittb2Rfc3NsIGdlbmVyYXRlZCBj
        dXN0b20gc2VydmVyIGNlcnRpZmljYXRlMBEGCWCGSAGG+EIBAQQEAwIGQDANBgkqhkiG9w0BAQsF
        AAOBgQB+iFUTzH0xIBuxmHsrW7NSuFaY/FdcVtiwrHsbzLqBrEctnAj0GgCYIkTEB8tTIxUe4Rgv
        5pAMOgEYdhKITWVHFZlgvB4JJ3j5yD6yIDrYuG/3e/2bOBZIqFA7ZHaF1R9A9z6mEOSbowjArdHn
        TgyJqccKRbxa3WFm/7F4NCVYrw==
        """

    private func certificate() throws -> SecCertificate {
        let der = try #require(
            Data(
                base64Encoded: Self.factoryCertificateDER
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: " ", with: "")
            )
        )
        return try #require(SecCertificateCreateWithData(nil, der as CFData))
    }

    private func trust() throws -> SecTrust {
        var trust: SecTrust?
        let cert = try certificate()
        let status = SecTrustCreateWithCertificates(
            cert as CFTypeRef,
            SecPolicyCreateBasicX509(),
            &trust
        )
        #expect(status == errSecSuccess)
        return try #require(trust)
    }

    /// Independently computed with openssl:
    ///   openssl x509 -pubkey -noout | openssl rsa -pubin -RSAPublicKey_out \
    ///     -outform DER | openssl dgst -sha256
    /// SecKeyCopyExternalRepresentation returns the PKCS#1 RSAPublicKey form,
    /// not SubjectPublicKeyInfo, so this is the hash that must match.
    private static let expectedFingerprint =
        "838f1e6004a4fba5fc74e8ed743c4252dbe8dfb2991a38f5085652d0f02bda3f"

    @Test
    func theFingerprintOfARealSynologyCertificateCanBeExtracted() throws {
        let serverTrust = try trust()
        let fingerprint = try #require(
            SynologyTrustEvaluator.fingerprint(of: serverTrust)
        )
        #expect(fingerprint == Self.expectedFingerprint)
        #expect(fingerprint.count == 64)
    }

    /// The factory certificate is shared by every Synology ever shipped, so the
    /// system must not trust it — the premise the whole pinning design rests on.
    @Test
    func theFactoryCertificateIsNotSystemTrusted() throws {
        let serverTrust = try trust()
        #expect(!SecTrustEvaluateWithError(serverTrust, nil))
    }

    /// The accept/refuse decision itself needs a real URLAuthenticationChallenge,
    /// which cannot be constructed here — so this covers only the starting state:
    /// an evaluator reports nothing seen and no mismatch until a challenge
    /// actually arrives. The decision is exercised for real by connecting.
    @Test
    func aNewEvaluatorHasSeenNothingYet() {
        let matching = SynologyTrustEvaluator(pinned: Self.expectedFingerprint)
        #expect(matching.certificateMismatch == nil)
        #expect(matching.observed == nil)
        #expect(SynologyTrustEvaluator(pinned: nil).observed == nil)
    }

    /// Two units, or a replaced certificate, must produce different pins —
    /// otherwise pinning would silently accept a substitution.
    @Test
    func aDifferentKeyProducesADifferentFingerprint() throws {
        let other = SecKeyCreateRandomKey(
            [
                kSecAttrKeyType: kSecAttrKeyTypeRSA,
                kSecAttrKeySizeInBits: 2048,
            ] as CFDictionary,
            nil
        )
        let privateKey = try #require(other)
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
        let data = try #require(
            SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        )
        let fingerprint = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(fingerprint != Self.expectedFingerprint)
    }

    /// The half of this decision that is not written in Swift.
    ///
    /// App Transport Security runs its own system-trust evaluation and refuses
    /// a self-signed certificate *before* the evaluator above is consulted, so
    /// every accept path here is dead unless Info.plist lifts that blanket.
    /// That is not a hypothesis: with the key absent, a NAS that answers `curl`
    /// gives this app `NSURLErrorDomain -1200` and logs `ATS failed system
    /// trust`, while the evaluator computes the correct pin and is overruled.
    /// Nothing else in the suite would notice the key going away, because the
    /// only thing it breaks is talking to a real Synology.
    @Test
    func appTransportSecurityLeavesTheDecisionToTheEvaluator() throws {
        let policy = try #require(
            Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity")
                as? [String: Any]
        )
        #expect(policy["NSAllowsArbitraryLoads"] as? Bool == true)

        // The update feed is the one host known in advance, so it stays under
        // ATS: an exception still binds when arbitrary loads are allowed.
        // Tying this to the feed URL rather than to a literal means moving the
        // feed and forgetting the exception fails here rather than in the wild.
        let domains = try #require(
            policy["NSExceptionDomains"] as? [String: Any]
        )
        let feed = try #require(
            Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        )
        let host = try #require(URL(string: feed)?.host)
        #expect(
            domains.keys.contains { host == $0 || host.hasSuffix(".\($0)") }
        )
    }
}
