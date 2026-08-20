import Foundation
import Testing
@testable import LittleHerd

/// DSM's responses are decoded rather than screen-scraped, but its JSON is
/// inconsistent in ways that break naive `Codable` types: byte counts arrive as
/// strings, models differ in which keys they send at all, and the same drive
/// condition is spelled several ways. The fixtures here keep those shapes
/// honest without needing a NAS on the network.
struct SynologyDSMTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Envelope and error mapping

    @Test
    func anUnsuccessfulEnvelopeCarriesDSMsErrorCode() throws {
        let envelope = try decode(
            DSMEnvelope<DSMLoginPayload>.self,
            #"{"error":{"code":400},"success":false}"#
        )
        #expect(envelope.success == false)
        #expect(envelope.data == nil)
        #expect(envelope.error?.code == 400)
    }

    /// The codes a user can act on have to say what to do. 402 and 403 in
    /// particular are the difference between "wrong password" and "this account
    /// is the wrong kind of account", which is the whole setup story.
    @Test
    func theErrorCodesAUserCanFixExplainThemselves() {
        #expect(
            SynologyDSMError.detailForAPICode(400).contains("password")
        )
        #expect(
            SynologyDSMError.detailForAPICode(402).contains("administrators")
        )
        #expect(
            SynologyDSMError.detailForAPICode(403).contains("two-factor")
        )
        #expect(
            SynologyDSMError.detailForAPICode(407).contains("blocked")
        )
        #expect(
            SynologyDSMError.detailForAPICode(9999).contains("9999")
        )
    }

    @Test
    func anExpiredSessionIsDistinguishedFromARefusedOne() {
        #expect(SynologyDSMError.fromAPICode(119).isExpiredSession)
        #expect(!SynologyDSMError.fromAPICode(400).isExpiredSession)
    }

    // MARK: - Numbers

    /// DSM sends volume sizes as strings and utilization figures as numbers, in
    /// the same API surface.
    @Test
    func byteCountsDecodeWhetherTheyArriveAsStringsOrNumbers() throws {
        struct Box: Decodable { let a: DSMNumber; let b: DSMNumber }
        let box = try decode(Box.self, #"{"a":"878029","b":42.5}"#)
        #expect(box.a.value == 878_029)
        #expect(box.b.value == 42.5)
    }

    @Test
    func anUnreadableNumberBecomesZeroRatherThanFailingTheWholeResponse() throws {
        struct Box: Decodable { let a: DSMNumber }
        let box = try decode(Box.self, #"{"a":null}"#)
        #expect(box.a.value == 0)
    }

    // MARK: - Volumes

    /// Shape taken from `SYNO.Storage.CGI.Storage` `load_info`: sizes as
    /// strings, in bytes.
    private let storageJSON = """
    {"success":true,"data":{
      "volumes":[
        {"id":"volume_1","display_name":"Volume 1","status":"normal",
         "size":{"total":"21474836480","used":"10737418240","free":"9663676416"}},
        {"id":"volume_2","display_name":"Volume 2","status":"normal",
         "size":{"total":"1073741824","used":"536870912","free":"536870912"}}
      ],
      "disks":[
        {"id":"sata1","name":"Drive 1","model":"WD40EFRX-68N32N0 ",
         "status":"normal","smart_status":"normal","temp":38},
        {"id":"sata2","name":"Drive 2","model":"WD40EFRX-68N32N0 ",
         "status":"normal","smart_status":"warning","temp":41}
      ]}}
    """

    /// Captured verbatim from a real DS-series unit running DSM 7, trimmed to
    /// the keys the parsers read. It differs from the documented shape in three
    /// ways that each broke something: `display_name` is null, `size.free` is
    /// absent, and a damaged drive reports "normal" in both `status` and
    /// `smart_status` while `overview_status` says "critical".
    private let realStorageJSON = """
    {"success":true,"data":{
      "volumes":[
        {"id":"volume_1","num_id":1,"desc":"","vol_desc":"","display_name":null,
         "vol_path":"/volume1","status":"attention","summary_status":"attention",
         "raidType":"single","fs_type":"ext4","disk_failure_number":0,
         "size":{"free_inode":"272271642","total":"8915941834752",
                 "total_device":"8986933854208","total_inode":"274259968",
                 "used":"5930997547008"}}
      ],
      "disks":[
        {"id":"sda","name":"Drive 1","model":"WD30EFRX-68EUZN0","status":"normal",
         "smart_status":"normal","overview_status":"normal",
         "summary_status_key":"normal","unc":0,"temp":33},
        {"id":"sdb","name":"Drive 2","model":"WD30EFRX-68EUZN0","status":"normal",
         "smart_status":"normal","overview_status":"critical",
         "summary_status_key":"critical","unc":229,"temp":34},
        {"id":"sdc","name":"Drive 3","model":"WD30EFRX-68EUZN0","status":"normal",
         "smart_status":"normal","overview_status":"normal",
         "summary_status_key":"normal","unc":0,"temp":32},
        {"id":"sdd","name":"Drive 4","model":"WD30EFRX-68EUZN0","status":"normal",
         "smart_status":"normal","overview_status":"normal",
         "summary_status_key":"normal","unc":0,"temp":35}
      ]}}
    """

    // MARK: - The real unit

    /// The regression that matters most: reading only `status` and
    /// `smart_status` called a drive with 229 uncorrectable sectors healthy.
    @Test
    func aDriveDSMCallsCriticalIsNotReportedHealthy() throws {
        let payload = try #require(
            try decode(DSMEnvelope<DSMStoragePayload>.self, realStorageJSON).data
        )
        let drives = SynologyDSMParser.drives(from: payload)

        #expect(drives.count == 4)
        let bad = try #require(drives.first { $0.name == "Drive 2" })
        #expect(bad.health == .critical)
        #expect(bad.uncorrectableSectors == 229)

        // And the healthy ones stay healthy — a check that fires on everything
        // would be as useless as one that never fires.
        let healthy = drives.filter { $0.name != "Drive 2" }
        #expect(healthy.count == 3)
        #expect(healthy.allSatisfy { $0.health == .normal })
        #expect(healthy.allSatisfy { $0.uncorrectableSectors == 0 })
    }

    /// Uncorrectable sectors are damage even if every status string says
    /// otherwise, so the count alone is enough to raise a warning.
    @Test
    func badSectorsAloneAreEnoughToStopCallingASynologyHealthy() throws {
        let json = """
        {"success":true,"data":{"disks":[
          {"id":"sda","name":"Drive 1","status":"normal","smart_status":"normal",
           "overview_status":"normal","summary_status_key":"normal","unc":3,"temp":30}]}}
        """
        let payload = try #require(
            try decode(DSMEnvelope<DSMStoragePayload>.self, json).data
        )
        #expect(SynologyDSMParser.drives(from: payload)[0].health == .warning)
    }

    /// The real unit reports its volume as "attention" while every drive string
    /// says "normal". Before "attention" was understood it fell through to
    /// `.unknown`, so a degraded pool was indistinguishable from one that
    /// reported nothing.
    @Test
    func aVolumeInAttentionIsRecognisedAsTrouble() throws {
        let payload = try #require(
            try decode(DSMEnvelope<DSMStoragePayload>.self, realStorageJSON).data
        )
        let volume = SynologyDSMParser.storageVolumes(from: payload)[0]
        #expect(volume.health == .warning)
    }

    @Test
    func dsmsVolumeAndPoolWordsMapOntoHealth() {
        #expect(SynologyHealth.parse("attention") == .warning)
        #expect(SynologyHealth.parse("danger") == .critical)
        #expect(SynologyHealth.parse("normal") == .normal)
        // Still true after adding those two — the substring trap that started
        // all this.
        #expect(SynologyHealth.parse("abnormal") == .warning)
    }

    /// A Mac's volumes have no health opinion at all, and must not be made to
    /// look like they do.
    @Test
    func aVolumeFromAMachineWithNoOpinionReportsNoHealth() {
        let volume = StorageVolume(
            id: "/",
            name: "Macintosh HD",
            mountPath: "/",
            availableBytes: 100,
            totalBytes: 200
        )
        #expect(volume.health == nil)
    }

    /// `display_name` is null and `desc` is empty on a real unit, so the name
    /// has to come from the identifier rather than rendering as "volume_1".
    @Test
    func aVolumeWithNoNameIsCalledSomethingReadable() throws {
        let payload = try #require(
            try decode(DSMEnvelope<DSMStoragePayload>.self, realStorageJSON).data
        )
        let volumes = SynologyDSMParser.storageVolumes(from: payload)

        #expect(volumes.count == 1)
        #expect(volumes[0].name == "Volume 1")
        #expect(volumes[0].mountPath == "/volume1")
    }

    /// This unit sends no `size.free`, so free space is derived — the path the
    /// documented shape suggested would be the unusual one.
    @Test
    func freeSpaceIsDerivedWhenTheUnitOmitsIt() throws {
        let payload = try #require(
            try decode(DSMEnvelope<DSMStoragePayload>.self, realStorageJSON).data
        )
        let volume = SynologyDSMParser.storageVolumes(from: payload)[0]

        #expect(volume.totalBytes == 8_915_941_834_752)
        #expect(volume.availableBytes == 8_915_941_834_752 - 5_930_997_547_008)
        #expect(abs(volume.usedPercent - 66.5) < 0.1)
    }

    @Test
    func volumesComeBackInBytesWithDSMsOwnFreeFigure() throws {
        let envelope = try decode(DSMEnvelope<DSMStoragePayload>.self, storageJSON)
        let payload = try #require(envelope.data)
        let volumes = SynologyDSMParser.storageVolumes(from: payload)

        #expect(volumes.count == 2)
        #expect(volumes[0].name == "Volume 1")
        #expect(volumes[0].totalBytes == 21_474_836_480)
        // DSM's own `free`, not total - used: a volume reserves space that is
        // neither, so deriving it would disagree with DSM's own UI.
        #expect(volumes[0].availableBytes == 9_663_676_416)
        #expect(volumes[0].id == "dsm:volume_1")
    }

    @Test
    func aVolumeWithoutASizeIsSkippedRatherThanReportedAsEmpty() throws {
        let json = """
        {"success":true,"data":{"volumes":[
          {"id":"volume_1","display_name":"Broken"},
          {"id":"volume_2","display_name":"Fine",
           "size":{"total":"100","used":"25","free":"75"}}]}}
        """
        let payload = try #require(
            try decode(DSMEnvelope<DSMStoragePayload>.self, json).data
        )
        let volumes = SynologyDSMParser.storageVolumes(from: payload)
        #expect(volumes.count == 1)
        #expect(volumes[0].name == "Fine")
    }

    @Test
    func freeSpaceIsDerivedOnlyWhenDSMOmitsIt() throws {
        let json = """
        {"success":true,"data":{"volumes":[
          {"id":"v","display_name":"V","size":{"total":"100","used":"30"}}]}}
        """
        let payload = try #require(
            try decode(DSMEnvelope<DSMStoragePayload>.self, json).data
        )
        #expect(SynologyDSMParser.storageVolumes(from: payload)[0].availableBytes == 70)
    }

    @Test
    func theDiskReadingSumsEveryVolumeIntoOneFigure() throws {
        let payload = try #require(
            try decode(DSMEnvelope<DSMStoragePayload>.self, storageJSON).data
        )
        let volumes = SynologyDSMParser.storageVolumes(from: payload)
        let reading = try #require(SynologyDSMParser.diskReading(for: volumes))

        // 22548578304 total, 10200547328 free -> 54.76% used
        #expect(reading.capacity == 22_548_578_304)
        #expect(reading.auxiliaryValue == 10_200_547_328)
        let used = try #require(reading.value)
        #expect(abs(used - 54.76) < 0.01)
    }

    @Test
    func noVolumesMeansNoDiskReadingRatherThanZeroPercentFull() {
        #expect(SynologyDSMParser.diskReading(for: []) == nil)
    }

    // MARK: - Drive health

    @Test
    func driveHealthReadsDSMsSeveralSpellingsOfTheSameCondition() {
        #expect(SynologyHealth.parse("normal") == .normal)
        #expect(SynologyHealth.parse("Good") == .normal)
        #expect(SynologyHealth.parse("warning") == .warning)
        #expect(SynologyHealth.parse("abnormal") == .warning)
        #expect(SynologyHealth.parse("critical") == .critical)
        #expect(SynologyHealth.parse("crashed") == .critical)
        #expect(SynologyHealth.parse("") == .unknown)
        #expect(SynologyHealth.parse(nil) == .unknown)
    }

    /// A drive DSM has taken offline matters even when its SMART data still
    /// reads clean, so the worse of the two wins.
    @Test
    func aDriveTakesTheWorseOfItsSMARTStatusAndItsDSMStatus() throws {
        let json = """
        {"success":true,"data":{"disks":[
          {"id":"sata1","name":"Drive 1","status":"crashed","smart_status":"normal","temp":38}]}}
        """
        let payload = try #require(
            try decode(DSMEnvelope<DSMStoragePayload>.self, json).data
        )
        #expect(SynologyDSMParser.drives(from: payload)[0].health == .critical)
    }

    @Test
    func drivesCarryModelAndTemperature() throws {
        let payload = try #require(
            try decode(DSMEnvelope<DSMStoragePayload>.self, storageJSON).data
        )
        let drives = SynologyDSMParser.drives(from: payload)

        #expect(drives.count == 2)
        #expect(drives[0].name == "Drive 1")
        // DSM pads model strings.
        #expect(drives[0].model == "WD40EFRX-68N32N0")
        #expect(drives[0].temperatureCelsius == 38)
        #expect(drives[0].health == .normal)
        #expect(drives[1].health == .warning)
    }

    @Test
    func aDriveReportingNoTemperatureSaysSoRatherThanClaimingZeroDegrees() throws {
        let json = """
        {"success":true,"data":{"disks":[
          {"id":"sata1","name":"Drive 1","status":"normal","smart_status":"normal","temp":0}]}}
        """
        let payload = try #require(
            try decode(DSMEnvelope<DSMStoragePayload>.self, json).data
        )
        #expect(SynologyDSMParser.drives(from: payload)[0].temperatureCelsius == nil)
    }

    // MARK: - Utilization

    /// Captured from the same real unit: `total_real` sits just below
    /// `memory_size`, and DSM reports its own `real_usage` percentage.
    private let utilizationJSON = """
    {"success":true,"data":{
      "cpu":{"user_load":1,"system_load":1,"other_load":5,"1min_load":12},
      "memory":{"memory_size":2097152,"total_real":2034248,"avail_real":129372,
                "cached":1349996,"buffer":93956,"avail_swap":100,
                "real_usage":22}}}
    """

    @Test
    func cpuLoadIsTheSumOfDSMsThreeComponents() throws {
        let payload = try #require(
            try decode(DSMEnvelope<DSMUtilizationPayload>.self, utilizationJSON).data
        )
        // 1 + 1 + 5. The `1min_load` alongside it is a load average, not a
        // percentage, and must not be mistaken for one.
        #expect(SynologyDSMParser.cpuReading(from: payload)?.value == 7)
    }

    /// DSM reports its own used percentage. Preferring it keeps the dashboard
    /// and DSM's own UI from disagreeing by a few points.
    @Test
    func memoryUsesDSMsOwnPercentageWhenItReportsOne() throws {
        let payload = try #require(
            try decode(DSMEnvelope<DSMUtilizationPayload>.self, utilizationJSON).data
        )
        let reading = try #require(SynologyDSMParser.memoryReading(from: payload))

        #expect(reading.value == 22)
        // Capacity comes from `total_real` (usable RAM), which is what DSM's
        // percentage is computed against — not `memory_size`, which would give
        // 2_097_152 KB and read a few points lower.
        let capacity = try #require(reading.capacity)
        #expect(capacity == Double(2_034_248) * 1024)
    }

    /// DSM's `avail_real` excludes cache and buffers, which macOS counts as
    /// available. Adding them back is what makes a NAS's memory row comparable
    /// to a Mac's rather than permanently alarming.
    @Test
    func memoryCountsCacheAndBuffersAsAvailableTheWayMacOSDoes() throws {
        let json = """
        {"success":true,"data":{"memory":{
          "memory_size":8388608,"avail_real":1048576,
          "cached":2097152,"buffer":524288}}}
        """
        let payload = try #require(
            try decode(DSMEnvelope<DSMUtilizationPayload>.self, json).data
        )
        let reading = try #require(SynologyDSMParser.memoryReading(from: payload))

        // No `real_usage` here, so it falls back to our own arithmetic:
        // available = (1048576 + 2097152 + 524288) KB of 8 GiB.
        #expect(reading.capacity == 8_589_934_592)
        #expect(reading.auxiliaryValue == 3_758_096_384)
        let used = try #require(reading.value)
        #expect(abs(used - 56.25) < 0.01)
    }

    @Test
    func utilizationWithoutMemoryYieldsNoMemoryReading() throws {
        let payload = try #require(
            try decode(
                DSMEnvelope<DSMUtilizationPayload>.self,
                #"{"success":true,"data":{"cpu":{"user_load":3}}}"#
            ).data
        )
        #expect(SynologyDSMParser.memoryReading(from: payload) == nil)
        #expect(SynologyDSMParser.cpuReading(from: payload)?.value == 3)
    }

    // MARK: - Endpoint

    /// The endpoint reuses the SSH host validator, so a Bonjour name can no more
    /// smuggle something into a URL than into an ssh argument list.
    @Test
    func anEndpointRefusesAHostnameTheSSHValidatorWouldRefuse() {
        #expect(
            SynologyDSMEndpoint(host: "AlpernServer.local", username: "herd")
                .isValid
        )
        #expect(
            !SynologyDSMEndpoint(host: "nas .local", username: "herd").isValid
        )
        #expect(
            !SynologyDSMEndpoint(host: "-oProxyCommand=x", username: "herd")
                .isValid
        )
        #expect(!SynologyDSMEndpoint(host: "nas.local", username: "").isValid)
        #expect(
            !SynologyDSMEndpoint(host: "nas.local", port: 0, username: "herd")
                .isValid
        )
    }

    @Test
    func theEndpointBuildsADSMWebAPIURL() throws {
        let endpoint = SynologyDSMEndpoint(
            host: "AlpernServer.local",
            username: "herd"
        )
        let url = try #require(
            endpoint.url(query: [URLQueryItem(name: "api", value: "SYNO.API.Auth")])
        )
        #expect(
            url.absoluteString
                == "https://AlpernServer.local:5001/webapi/entry.cgi?api=SYNO.API.Auth"
        )
    }

    // MARK: - What the sign-in sheet says

    /// The defect this covers: the sheet reported whatever string URLSession
    /// handed up, so four unrelated situations produced one unactionable
    /// sentence. Each must now name its own stage — that is the whole point,
    /// and it is what would have shortened the ATS hunt.
    @Test
    func everyRefusalNamesTheStageThatRefused() {
        let host = "nas.example"
        #expect(
            SynologyDSMError.transport("A TLS error caused the secure connection to fail.")
                .explanation(host: host).stage == .certificate
        )
        #expect(
            SynologyDSMError.transport("The request timed out.")
                .explanation(host: host).stage == .network
        )
        #expect(
            SynologyDSMError.fromAPICode(400).explanation(host: host).stage == .dsm
        )
        #expect(
            SynologyDSMError.notAuthenticated.explanation(host: host).stage
                == .beforeAsking
        )
        #expect(
            SynologyDSMError.certificateChanged(expected: "a", received: "b")
                .explanation(host: host).stage == .certificate
        )
    }

    /// A TLS failure is not the NAS being down, and it was read as that for an
    /// evening. It must not classify as a network problem.
    @Test
    func aTLSFailureIsNotMistakenForAnUnreachableNAS() {
        let explanation = SynologyDSMError
            .transport("A TLS error caused the secure connection to fail.")
            .explanation(host: "nas.example")
        #expect(explanation.stage != .network)
        // And the original string survives, because the sentence a person can
        // act on and the string an engineer needs are not the same one.
        #expect(explanation.evidence?.contains("TLS") == true)
    }

    /// The fingerprints existed all along and the sheet threw them away. A
    /// certificate that changed is the one failure worth reading carefully.
    @Test
    func aChangedCertificateShowsBothFingerprints() throws {
        let explanation = SynologyDSMError
            .certificateChanged(expected: "aaa111", received: "bbb222")
            .explanation(host: "nas.example")
        let evidence = try #require(explanation.evidence)
        #expect(evidence.contains("aaa111"))
        #expect(evidence.contains("bbb222"))
        #expect(explanation.stage.caption == "Certificate refused")
    }

    /// DSM's own code is kept beside the sentence: the sentence is for the
    /// person, the code is for anyone searching Synology's documentation.
    @Test
    func aDSMRefusalCarriesItsCode() throws {
        let explanation = SynologyDSMError.fromAPICode(403)
            .explanation(host: "nas.example")
        #expect(explanation.headline.contains("two-factor"))
        #expect(try #require(explanation.evidence).contains("403"))
    }

    /// macOS words a denied Local Network permission as an offline internet
    /// connection, which points at the wrong fix entirely.
    @Test
    func aBlockedLocalNetworkIsNamedInTheSheetToo() {
        let explanation = SynologyDSMError
            .transport("The Internet connection appears to be offline.")
            .explanation(host: "nas.example")
        #expect(explanation.headline.contains("Local Network"))
    }

    /// Sheet and tooltip read the same classifier, so they cannot drift into
    /// disagreeing about what happened.
    @Test
    func theSheetAndTheTooltipAgreeAboutWhatFailed() {
        #expect(SynologyTransportProblem.classify("The request timed out.") == .noAnswer)
        #expect(
            SynologyTransportProblem.classify("A server with the specified hostname could not be found.")
                == .nameNotFound
        )
        #expect(SynologyTransportProblem.classify("Connection refused") == .refused)
        #expect(
            SynologyTransportProblem.classify("An SSL error has occurred.") == .tlsRefused
        )
    }
}
