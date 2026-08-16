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
        let store = MachineConfigurationStore(
            storage: InMemoryConfigurationStorage()
        )
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

    /// macOS words a blocked local network as an offline internet connection,
    /// which sends the user to the wrong fix entirely — the NAS is on the same
    /// desk and answering. Seen for real against a reachable unit.
    @Test
    func aBlockedLocalNetworkNamesTheActualPermission() {
        let blocked = RemoteUnavailability.classify(
            dsm: .transport("The Internet connection appears to be offline.")
        )
        guard case .other(let message) = blocked else {
            Issue.record("expected a spelled-out reason, got \(blocked)")
            return
        }
        #expect(message.contains("Local Network"))
        // It must not read as the NAS being down, which is the wrong diagnosis.
        #expect(blocked != .noAnswer)
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

/// What the menu bar says when a drive is going.
@MainActor
struct SynologyMenuBarTests {
    private func snapshot(
        _ name: String,
        cpu: Double? = nil,
        memory: MemoryPressureLevel? = .normal,
        disk: Double? = 50,
        health: SynologyHealth? = nil
    ) -> MenuBarMachineSnapshot {
        MenuBarMachineSnapshot(
            machine: MachineID(name),
            state: .live,
            cpuPercent: cpu,
            memoryPressure: memory,
            diskUsedPercent: disk,
            storageHealth: health
        )
    }

    /// A failing drive outranks everything else on screen. A pegged CPU and a
    /// full disk are both recoverable; the drive is not, and the menu bar is
    /// the only surface visible when the dashboard is closed.
    @Test
    func aFailingDriveOutranksAPeggedCPUAndAFullDisk() {
        let headline = MenuBarStatusSelector.headline(for: [
            snapshot("mini", cpu: 99, disk: 99),
            snapshot("synology", health: .critical),
        ])
        guard case .storageUnhealthy(let machine, let critical) = headline else {
            Issue.record("expected storageUnhealthy, got \(headline)")
            return
        }
        #expect(machine == MachineID("synology"))
        #expect(critical)
    }

    @Test
    func aDegradedDriveOutranksMemoryPressureButReadsAsLessSevere() {
        let headline = MenuBarStatusSelector.headline(for: [
            snapshot("mini", memory: .critical),
            snapshot("synology", health: .warning),
        ])
        guard case .storageUnhealthy(_, let critical) = headline else {
            Issue.record("expected storageUnhealthy, got \(headline)")
            return
        }
        #expect(!critical)
    }

    /// Healthy and unreported storage must not displace the ordinary headline,
    /// or the menu bar would permanently cry wolf.
    @Test
    func healthyOrSilentStorageChangesNothing() {
        for health: SynologyHealth? in [nil, .normal, .unknown] {
            let headline = MenuBarStatusSelector.headline(for: [
                snapshot("mini", cpu: 10, health: health)
            ])
            guard case .normal = headline else {
                Issue.record("\(String(describing: health)) should not raise a headline, got \(headline)")
                return
            }
        }
    }
}

/// Offline means two different things, and the interface has to tell them
/// apart: a NAS that has never been set up is not a NAS that has failed.
@MainActor
struct NeverConnectedTests {
    private func storageMachine() -> MachineMonitorModel {
        MachineMonitorModel(
            configuration: MachineConfiguration(
                id: MachineID("synology"),
                name: "Synology",
                shortName: "Synology",
                hostname: "AlpernServer.local",
                hardwareSummary: "Network storage",
                platform: .storage,
                connection: .smb,
                avatar: .pigletNAS,
                identityFile: nil,
                serverNames: ["AlpernServer.local"],
                supportsGPU: false
            )
        )
    }

    @Test
    func aMachineThatHasNeverAnsweredIsNotReportedAsFailed() {
        let machine = storageMachine()
        machine.markOffline(.other("No shared folder is mounted."))
        #expect(machine.hasNeverConnected)
    }

    /// Once it has worked, going offline is a real fault again.
    @Test
    func aMachineThatWorkedAndStoppedIsAFault() {
        let machine = storageMachine()
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.disk: MetricReading(value: 40)]
            )
        )
        machine.markOffline(.noAnswer)
        #expect(!machine.hasNeverConnected)
        #expect(machine.state == .offline)
    }

    /// The same rule the alert center already applies — a machine that never
    /// connected is configuration, not news.
    @Test
    func aMachineThatNeverConnectedRaisesNoUnreachableAlert() {
        let machine = storageMachine()
        machine.markOffline(.other("No shared folder is mounted."))
        #expect(!MachineAlert.active(for: machine).contains(.unreachable))
    }
}

/// The badge says something is wrong; this is what says what.
@MainActor
struct StorageConcernTests {
    private func nas(
        drives: [SynologyDrive] = [],
        volumes: [StorageVolume] = []
    ) -> MachineMonitorModel {
        let machine = MachineMonitorModel(
            configuration: MachineConfiguration(
                id: MachineID("synology"),
                name: "Synology",
                shortName: "Synology",
                hostname: "AlpernServer.local",
                hardwareSummary: "Network storage",
                platform: .storage,
                connection: .dsm,
                avatar: .pigletNAS,
                identityFile: nil,
                serverNames: [],
                supportsGPU: false,
                dsmUsername: "malpern"
            )
        )
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.disk: MetricReading(value: 67)],
                storageVolumes: volumes,
                drives: drives
            )
        )
        return machine
    }

    private func drive(
        _ name: String,
        _ health: SynologyHealth,
        sectors: Int = 0
    ) -> SynologyDrive {
        SynologyDrive(
            id: name,
            name: name,
            model: "WD30EFRX",
            health: health,
            uncorrectableSectors: sectors,
            temperatureCelsius: 33
        )
    }

    /// Named, so the sentence identifies the part to pull out of the bay.
    @Test
    func theConcernNamesTheDriveAndTheEvidence() throws {
        let machine = nas(drives: [
            drive("Drive 1", .normal),
            drive("Drive 2", .critical, sectors: 229),
        ])
        let concern = try #require(machine.storageConcern)

        #expect(concern.health == .critical)
        #expect(concern.subject == "Drive 2")
        #expect(concern.summary.contains("Drive 2"))
        #expect(concern.summary.contains("failing"))
        #expect(concern.summary.contains("229 bad sectors"))
    }

    /// A drive beats a volume: it is the thing you would physically replace,
    /// and the volume is usually reporting the same fault second-hand.
    @Test
    func aNamedDriveIsPreferredOverTheVolumeReportingTheSameFault() throws {
        let machine = nas(
            drives: [drive("Drive 2", .critical, sectors: 229)],
            volumes: [
                StorageVolume(
                    id: "dsm:volume_1",
                    name: "Volume 1",
                    mountPath: "/volume1",
                    availableBytes: 1,
                    totalBytes: 3,
                    health: .warning
                )
            ]
        )
        #expect(try #require(machine.storageConcern).subject == "Drive 2")
    }

    /// With no drive condemned, the volume still has to be named — otherwise
    /// the badge appears with nothing behind it.
    @Test
    func aVolumeIsNamedWhenNoDriveIsAtFault() throws {
        let machine = nas(
            drives: [drive("Drive 1", .normal)],
            volumes: [
                StorageVolume(
                    id: "dsm:volume_1",
                    name: "Volume 1",
                    mountPath: "/volume1",
                    availableBytes: 1,
                    totalBytes: 3,
                    health: .warning
                )
            ]
        )
        let concern = try #require(machine.storageConcern)
        #expect(concern.subject == "Volume 1")
        #expect(concern.summary.contains("needs attention"))
    }

    /// A badge that is always lit says nothing at all.
    @Test
    func healthyStorageProducesNoConcern() {
        #expect(nas(drives: [drive("Drive 1", .normal)]).storageConcern == nil)
        #expect(nas(drives: [drive("Drive 1", .unknown)]).storageConcern == nil)
        #expect(nas().storageConcern == nil)
    }
}


/// Drives are listed in bay order, not by how sick they are.
@MainActor
struct DriveOrderTests {
    @Test
    func drivesKeepTheOrderTheMachineReportsThem() {
        let machine = MachineMonitorModel(
            configuration: MachineConfiguration(
                id: MachineID("synology"),
                name: "Synology",
                shortName: "Synology",
                hostname: "nas.local",
                hardwareSummary: "Network storage",
                platform: .storage,
                connection: .dsm,
                avatar: .pigletNAS,
                identityFile: nil,
                serverNames: [],
                supportsGPU: false,
                dsmUsername: "herd"
            )
        )
        let reported = ["Drive 1", "Drive 2", "Drive 3", "Drive 4"]
        machine.apply(
            SystemSnapshot(
                timestamp: .now,
                readings: [.disk: MetricReading(value: 67)],
                drives: reported.enumerated().map { index, name in
                    SynologyDrive(
                        id: "sd\(index)",
                        name: name,
                        model: "WD30EFRX",
                        // The second bay is the sick one; it must not be
                        // promoted to the top of the list because of it.
                        health: index == 1 ? .critical : .normal,
                        uncorrectableSectors: index == 1 ? 229 : 0,
                        temperatureCelsius: 33
                    )
                }
            )
        )

        #expect(machine.drives.map(\.name) == reported)
        // The concern still finds the bad one wherever it sits.
        #expect(machine.storageConcern?.subject == "Drive 2")
    }
}
