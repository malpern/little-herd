import Foundation

/// Measures a Synology through DSM, falling back to a mounted SMB share.
///
/// The fallback exists because DSM can be unreachable for reasons that have
/// nothing to do with the NAS being down — no password stored yet, an account
/// that turned out to need 2FA, a certificate that changed. In those cases a
/// mounted share still answers "how full is it", which is better than the
/// dashboard going blank.
actor SynologyMetricsSampler {
    private let client: SynologyDSMClient
    private let fallback: SMBStorageSampler?
    private let onCertificateObserved: @Sendable (String) -> Void

    /// Set once DSM has answered, so a later failure can say whether this NAS
    /// has ever worked or was never configured correctly in the first place.
    private var hasSucceeded = false

    init(
        endpoint: SynologyDSMEndpoint,
        pinnedCertificate: String?,
        fallbackServerNames: [String],
        passwordProvider: @escaping @Sendable () -> String?,
        onCertificateObserved: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.client = SynologyDSMClient(
            endpoint: endpoint,
            pinnedCertificate: pinnedCertificate,
            passwordProvider: passwordProvider
        )
        self.fallback = fallbackServerNames.isEmpty
            ? nil
            : SMBStorageSampler(serverNames: fallbackServerNames)
        self.onCertificateObserved = onCertificateObserved
    }

    func sample() async throws -> SystemSnapshot {
        do {
            let snapshot = try await sampleDSM()
            hasSucceeded = true
            if let certificate = await client.observedCertificate {
                onCertificateObserved(certificate)
            }
            return snapshot
        } catch let error as SynologyDSMError {
            // A certificate that changed under us is the one failure we must not
            // paper over with a fallback: something is impersonating the NAS, or
            // its certificate was replaced and needs re-approving.
            if case .certificateChanged = error { throw error }

            if let fallback, let snapshot = try? await fallback.sample() {
                return snapshot
            }
            throw error
        }
    }

    private func sampleDSM() async throws -> SystemSnapshot {
        let storage = try await client.storage()
        let volumes = SynologyDSMParser.storageVolumes(from: storage)
        let drives = SynologyDSMParser.drives(from: storage)

        var readings: [MetricKind: MetricReading] = [:]
        if let disk = SynologyDSMParser.diskReading(for: volumes) {
            readings[.disk] = disk
        }

        // Utilization is a second round trip, and a NAS that can report its
        // volumes but not its load is still worth showing. Losing CPU should not
        // cost us the disk figures.
        if let utilization = try? await client.utilization() {
            if let cpu = SynologyDSMParser.cpuReading(from: utilization) {
                readings[.cpu] = cpu
            }
            if let memory = SynologyDSMParser.memoryReading(from: utilization) {
                readings[.memory] = memory
            }
        }

        guard !readings.isEmpty else {
            throw SynologyDSMError.malformedResponse(
                "no readable metrics in DSM's response"
            )
        }

        return SystemSnapshot(
            timestamp: .now,
            readings: readings,
            storageVolumes: volumes,
            drives: drives
        )
    }

    func signOut() async {
        await client.signOut()
    }

    var hasEverSucceeded: Bool { hasSucceeded }
}

// MARK: - Explaining a failure

extension RemoteUnavailability {
    /// Maps a DSM failure onto the same vocabulary an unreachable Mac uses, so a
    /// NAS gets a real explanation in the tooltip instead of a bare
    /// "Unavailable" — the gap that made the Synology read as broken when it was
    /// only unmounted.
    static func classify(dsm error: SynologyDSMError) -> RemoteUnavailability {
        switch error {
        case .invalidHost:
            .unusableHostName
        case .notAuthenticated:
            .other("No DSM password saved for this NAS yet.")
        case .certificateChanged:
            .other(error.detail)
        case .malformedResponse:
            .incompleteOutput
        case .api(let code, let detail):
            // 400/401/402/403 are all "DSM answered and said no", which is the
            // same shape of problem as a rejected SSH key.
            (400...410).contains(code) ? .keyRejected : .other(detail)
        case .transport(let message):
            Self.classifyTransport(message)
        }
    }

    private static func classifyTransport(
        _ message: String
    ) -> RemoteUnavailability {
        let lowered = message.lowercased()
        // macOS reports a blocked local network as "The Internet connection
        // appears to be offline", which is actively misleading about a NAS on
        // the same desk — and points at the wrong fix. Observed with the real
        // unit reachable and answering.
        if lowered.contains("internet connection appears to be offline") {
            return .other(
                "macOS is blocking Little Herd from reaching your local network. Allow it under System Settings → Privacy & Security → Local Network."
            )
        }
        if lowered.contains("hostname could not be found")
            || lowered.contains("could not be found")
            || lowered.contains("nodename") {
            return .nameNotFound
        }
        if lowered.contains("timed out") || lowered.contains("not connect") {
            return .noAnswer
        }
        if lowered.contains("refused") { return .refused }
        return .other(message)
    }
}
