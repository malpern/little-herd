import Foundation
import Testing
@testable import LittleHerd

/// How a DSM-measured NAS behaves once it is wired into the herd: what it is
/// allowed to report, how its failures are explained, and what it can raise an
/// alert about.
@MainActor
struct SynologyWiringTests {
    private func dsmConfiguration(
        username: String? = "littleherd",
        fingerprint: String? = nil
    ) -> MachineConfiguration {
        MachineConfiguration(
            id: MachineID("synology"),
            name: "Synology",
            shortName: "Synology",
            hostname: "AlpernServer.local",
            hardwareSummary: "Network storage",
            platform: .storage,
            connection: .dsm,
            avatar: .pigletNAS,
            identityFile: nil,
            serverNames: ["AlpernServer.local"],
            supportsGPU: false,
            dsmUsername: username,
            dsmPort: nil,
            dsmCertificateFingerprint: fingerprint
        )
    }

    // MARK: - Configuration

    /// Existing configurations were written before these fields existed. They
    /// have to keep decoding, or the whole herd disappears on upgrade.
    @Test
    func aConfigurationSavedBeforeDSMExistedStillDecodes() throws {
        let legacy = """
        [{"platform":"storage","hostname":"AlpernServer.local","avatar":"piglet-nas",
          "serverNames":["AlpernServer.local"],"id":"synology","shortName":"Synology",
          "hardwareSummary":"Network storage","connection":"smb","supportsGPU":false,
          "name":"Synology"}]
        """
        let decoded = try JSONDecoder().decode(
            [MachineConfiguration].self,
            from: Data(legacy.utf8)
        )

        #expect(decoded.count == 1)
        #expect(decoded[0].connection == .smb)
        #expect(decoded[0].dsmUsername == nil)
        #expect(decoded[0].dsmPort == nil)
        #expect(decoded[0].dsmCertificateFingerprint == nil)
        #expect(decoded[0].isStorage)
    }

    @Test
    func aDSMConfigurationSurvivesARoundTrip() throws {
        let original = dsmConfiguration(fingerprint: "abc123")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            MachineConfiguration.self,
            from: data
        )
        #expect(decoded == original)
        #expect(decoded.connection == .dsm)
    }

    /// SMB can only ever answer "how full is it", so it stays out of the CPU,
    /// memory, and AI overviews. DSM answers load and memory too, so a NAS
    /// reached that way belongs with the rest of the herd.
    @Test
    func aDSMNASJoinsTheOverviewsAnSMBOneIsKeptOutOf() {
        var smb = dsmConfiguration()
        smb.connection = .smb

        #expect(dsmConfiguration().reportsFullMetrics)
        #expect(!smb.reportsFullMetrics)

        let model = MonitorModel(configurations: [.local(), dsmConfiguration()])
        #expect(model.machines.count == 2)
        #expect(model.diskMachines.count == 2)

        let smbModel = MonitorModel(configurations: [.local(), smb])
        #expect(smbModel.machines.count == 1)
        #expect(smbModel.diskMachines.count == 2)
    }

    @Test
    func anEndpointIsOnlyBuiltForADSMMachineWithAnAccount() {
        #expect(dsmConfiguration().dsmEndpoint?.username == "littleherd")
        #expect(dsmConfiguration().dsmEndpoint?.port == 5001)
        #expect(dsmConfiguration(username: nil).dsmEndpoint == nil)
        #expect(dsmConfiguration(username: "").dsmEndpoint == nil)

        var smb = dsmConfiguration()
        smb.connection = .smb
        #expect(smb.dsmEndpoint == nil)
    }

    @Test
    func updatingOneMachineLeavesTheRestAlone() {
        // Named so it can be removed again: these suites otherwise accumulate in
        // the user's preferences, one per test run.
        let suiteName = "LittleHerdTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MachineConfigurationStore(defaults: defaults)
        store.add([dsmConfiguration()])

        var updated = dsmConfiguration(fingerprint: "recorded")
        updated.name = "Renamed"
        store.update(updated)

        #expect(store.machines.count == 2)  // local + synology
        let synology = store.machines.first { $0.id == MachineID("synology") }
        #expect(synology?.dsmCertificateFingerprint == "recorded")
        #expect(synology?.name == "Renamed")
        #expect(store.machines.contains { $0.connection == .local })
    }

    // MARK: - Explaining failures

    /// The gap this whole change closes: a NAS used to go offline with no
    /// reason at all, so "Unavailable" was the entire explanation.
    @Test
    func everyDSMFailureExplainsItself() {
        let noPassword = RemoteUnavailability.classify(dsm: .notAuthenticated)
        #expect(noPassword != nil)
        if case .other(let message) = noPassword {
            #expect(message.contains("password"))
        } else {
            Issue.record("expected a spelled-out reason, got \(noPassword)")
        }

        #expect(
            RemoteUnavailability.classify(dsm: .invalidHost("nas .local"))
                == .unusableHostName
        )
        #expect(
            RemoteUnavailability.classify(dsm: .malformedResponse("storage"))
                == .incompleteOutput
        )
    }

    /// DSM refusing an account is the same shape of problem as ssh refusing a
    /// key, and reusing that case means the existing tooltip already reads
    /// correctly.
    @Test
    func anAccountDSMRefusesReadsAsARejectedCredential() {
        for code in [400, 402, 403, 407, 410] {
            #expect(
                RemoteUnavailability.classify(dsm: .fromAPICode(code))
                    == .keyRejected,
                "DSM error \(code) should read as a refused credential"
            )
        }
    }

    @Test
    func aNASThatIsSimplyDownIsDistinguishedFromOneThatRefused() {
        #expect(
            RemoteUnavailability.classify(
                dsm: .transport("The request timed out.")
            ) == .noAnswer
        )
        #expect(
            RemoteUnavailability.classify(
                dsm: .transport("Could not connect to the server.")
            ) == .noAnswer
        )
        #expect(
            RemoteUnavailability.classify(
                dsm: .transport("A server with the specified hostname could not be found.")
            ) == .nameNotFound
        )
        #expect(
            RemoteUnavailability.classify(
                dsm: .transport("Connection refused")
            ) == .refused
        )
    }

    @Test
    func aChangedCertificateSaysWhatHappenedRatherThanJustFailing() {
        let error = SynologyDSMError.certificateChanged(
            expected: "aaa",
            received: "bbb"
        )
        #expect(error.detail.contains("certificate"))
        // It must not be mistaken for a bad password: the fix is completely
        // different, and the situation is worth taking seriously.
        #expect(RemoteUnavailability.classify(dsm: error) != .keyRejected)
    }

    // MARK: - Alerts

    @Test
    func aDrivePastSMARTWarningRaisesAnAlert() {
        let machine = MachineMonitorModel(configuration: dsmConfiguration())
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.disk: MetricReading(value: 40)],
                drives: [
                    SynologyDrive(
                        id: "sata1",
                        name: "Drive 1",
                        model: "WD40EFRX",
                        health: .warning,
                        temperatureCelsius: 41
                    )
                ]
            )
        )
        #expect(MachineAlert.active(for: machine).contains(.storageUnhealthy))
    }

    /// Plenty of drives report no SMART status at all. Treating silence as
    /// failure is how a monitor earns being muted.
    @Test
    func drivesReportingNothingRaiseNoAlert() {
        let machine = MachineMonitorModel(configuration: dsmConfiguration())
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.disk: MetricReading(value: 40)],
                drives: [
                    SynologyDrive(
                        id: "sata1",
                        name: "Drive 1",
                        model: "",
                        health: .unknown,
                        temperatureCelsius: nil
                    ),
                    SynologyDrive(
                        id: "sata2",
                        name: "Drive 2",
                        model: "",
                        health: .normal,
                        temperatureCelsius: 38
                    ),
                ]
            )
        )
        #expect(!MachineAlert.active(for: machine).contains(.storageUnhealthy))
    }

    @Test
    func aFailingDriveNamesItselfSoTheRightBayGetsOpened() {
        let machine = MachineMonitorModel(configuration: dsmConfiguration())
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.disk: MetricReading(value: 40)],
                drives: [
                    SynologyDrive(
                        id: "sata1",
                        name: "Drive 1",
                        model: "WD40EFRX",
                        health: .warning,
                        temperatureCelsius: 41
                    ),
                    SynologyDrive(
                        id: "sata2",
                        name: "Drive 2",
                        model: "WD40EFRX",
                        health: .critical,
                        temperatureCelsius: 55
                    ),
                ]
            )
        )

        var delivered: [(String, String)] = []
        let center = MachineAlertCenter { title, body in
            delivered.append((title, body))
        }
        center.evaluate(machine, isEnabled: true)

        let alert = delivered.first { $0.0.contains("storage needs attention") }
        let body = try? #require(alert?.1)
        // The critical drive, not merely the first hurt one.
        #expect(body?.contains("Drive 2") == true)
        #expect(body?.contains("failing") == true)
        #expect(body?.contains("2 drives affected") == true)
    }

    // MARK: - What the interface shows

    /// Severity ordering drives both the badge and the row order, so a failing
    /// drive is never sorted below a healthy one.
    @Test
    func healthSeverityRanksDamageAboveSilence() {
        #expect(SynologyHealth.critical.severity > SynologyHealth.warning.severity)
        #expect(SynologyHealth.warning.severity > SynologyHealth.normal.severity)
        // Unknown is the absence of news, not bad news: it must sort below
        // healthy, or a NAS reporting nothing would look worse than one
        // reporting fine.
        #expect(SynologyHealth.normal.severity > SynologyHealth.unknown.severity)
    }

    @Test
    func everyHealthHasItsOwnLabelAndSymbol() {
        let healths: [SynologyHealth] = [.normal, .warning, .critical, .unknown]
        let labels = Set(healths.map(\.label))
        let symbols = Set(healths.map(\.symbolName))
        #expect(labels.count == 4)
        #expect(symbols.count == 4)
        #expect(SynologyHealth.critical.label == "Failing")
    }

    /// The worst drive determines what the parser reports for a disk whose SMART
    /// status and DSM status disagree — the same rule the badge relies on.
    @Test
    func theWorseOfTwoHealthsAlwaysWins() {
        #expect(SynologyDSMParser.worse(.normal, .critical) == .critical)
        #expect(SynologyDSMParser.worse(.critical, .normal) == .critical)
        #expect(SynologyDSMParser.worse(.unknown, .normal) == .normal)
        #expect(SynologyDSMParser.worse(.warning, .critical) == .critical)
    }

    /// A pool can be degraded while every drive still reads normal. Alerting
    /// only on drives would stay silent through exactly that.
    @Test
    func aDegradedVolumeAlertsEvenWhenEveryDriveLooksFine() {
        let machine = MachineMonitorModel(configuration: dsmConfiguration())
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.disk: MetricReading(value: 40)],
                storageVolumes: [
                    StorageVolume(
                        id: "dsm:volume_1",
                        name: "Volume 1",
                        mountPath: "/volume1",
                        availableBytes: 3_000,
                        totalBytes: 9_000,
                        health: .warning
                    )
                ],
                drives: [
                    SynologyDrive(
                        id: "sda",
                        name: "Drive 1",
                        model: "WD30EFRX",
                        health: .normal,
                        temperatureCelsius: 33
                    )
                ]
            )
        )
        #expect(MachineAlert.active(for: machine).contains(.storageUnhealthy))

        var delivered: [(String, String)] = []
        let center = MachineAlertCenter { title, body in
            delivered.append((title, body))
        }
        center.evaluate(machine, isEnabled: true)

        // With no drive condemned, the message has to name the volume rather
        // than going out empty.
        let alert = delivered.first { $0.0.contains("storage needs attention") }
        #expect(alert?.1.contains("Volume 1") == true)
    }

    /// A healthy NAS must stay quiet, or the alert means nothing.
    @Test
    func aHealthyNASRaisesNothing() {
        let machine = MachineMonitorModel(configuration: dsmConfiguration())
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.disk: MetricReading(value: 40)],
                storageVolumes: [
                    StorageVolume(
                        id: "dsm:volume_1",
                        name: "Volume 1",
                        mountPath: "/volume1",
                        availableBytes: 5_000,
                        totalBytes: 9_000,
                        health: .normal
                    )
                ],
                drives: [
                    SynologyDrive(
                        id: "sda",
                        name: "Drive 1",
                        model: "WD30EFRX",
                        health: .normal,
                        temperatureCelsius: 33
                    )
                ]
            )
        )
        #expect(MachineAlert.active(for: machine).isEmpty)
    }

    /// A machine that has gone offline reports last-known numbers, so a drive
    /// warning frozen in place must not keep re-raising.
    @Test
    func anOfflineNASReportsOnlyThatItIsUnreachable() {
        let machine = MachineMonitorModel(configuration: dsmConfiguration())
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.disk: MetricReading(value: 40)],
                drives: [
                    SynologyDrive(
                        id: "sata1",
                        name: "Drive 1",
                        model: "",
                        health: .critical,
                        temperatureCelsius: nil
                    )
                ]
            )
        )
        machine.markOffline(.noAnswer)

        let active = MachineAlert.active(for: machine)
        #expect(active == [.unreachable])
    }
}
