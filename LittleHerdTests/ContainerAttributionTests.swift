import Foundation
import Testing
@testable import LittleHerd

/// Container attribution has two halves that can fail independently: a shell
/// function that reads cgroups on the remote machine, and the Swift that folds
/// its output back into the activity rows. The shell half is run for real here —
/// against a fixture `/proc`, and against a fake `docker` on the PATH — because
/// a bad `awk` in a string literal shows up only as an activity list that never
/// mentions a container, which no fixture-fed parser test would catch.
struct ContainerAttributionTests {
    // MARK: - Reading the cgroup

    @Test(arguments: [
        // cgroup v2 under systemd
        (
            "0::/system.slice/docker-3f2a1b0c9d8e7f6a5b4c3d2e1f009988776655443322110099887766.scope",
            "3f2a1b0c9d8e"
        ),
        // cgroup v2 without systemd
        (
            "0::/docker/aabbccddeeff00112233445566778899aabbccddeeff0011223344556677",
            "aabbccddeeff"
        ),
        // Podman
        (
            "0::/machine.slice/libpod-ffeeddccbbaa99887766554433221100ffeeddccbbaa9988776655.scope",
            "ffeeddccbbaa"
        ),
        // containerd under Kubernetes
        (
            "0::/kubepods.slice/kubepods-besteffort.slice/kubepods-besteffort-pod9f.slice/cri-containerd-9988776655443322110099887766554433221100998877665544.scope",
            "998877665544"
        ),
        // CRI-O
        (
            "0::/kubepods.slice/crio-1234567890abcdef1234567890abcdef1234567890abcdef12345678.scope",
            "1234567890ab"
        ),
    ])
    func containerIDIsReadFromEveryRuntimesCgroupShape(
        cgroup: String,
        expected: String
    ) {
        #expect(
            ContainerAttributionProbe.containerID(fromCgroupFile: cgroup) == expected
        )
    }

    /// cgroup v1 writes one line per subsystem, so the reader has to walk them
    /// rather than trusting the first.
    @Test
    func containerIDIsReadFromACgroupV1FileWithManySubsystems() {
        let cgroup = """
        12:cpu,cpuacct:/docker/1122334455667788990011223344556677889900112233445566
        11:memory:/docker/1122334455667788990011223344556677889900112233445566
        10:pids:/docker/1122334455667788990011223344556677889900112233445566
        """

        #expect(
            ContainerAttributionProbe.containerID(fromCgroupFile: cgroup)
                == "112233445566"
        )
    }

    /// The whole filter is "a long run of lower-case hex". Anything a process on
    /// the host sits in has to fail it, or every machine grows container rows it
    /// does not have.
    @Test(arguments: [
        "0::/",
        "0::/init.scope",
        "0::/user.slice/user-1000.slice/session-3.scope",
        "0::/system.slice/sshd.service",
        "0::/system.slice/system-postgresql.slice/postgresql@16-main.service",
        // Upper case is not a cgroup ID, and a unit could be named this way.
        "0::/system.slice/AABBCCDDEEFF00112233.scope",
        // Long enough to look like an ID until you read it.
        "0::/system.slice/not-hex-at-all-here.scope",
        "malformed line with no colons",
        "",
    ])
    func aProcessOnTheHostYieldsNoContainer(_ cgroup: String) {
        #expect(ContainerAttributionProbe.containerID(fromCgroupFile: cgroup) == nil)
    }

    // MARK: - Running the real shell function

    @Test
    func theShellFunctionNamesContainersAndIgnoresTheHost() async throws {
        let fixture = try FixtureProc()
        try fixture.write(
            pid: 101,
            cgroup: "0::/system.slice/docker-3f2a1b0c9d8e7f6a5b4c3d2e1f009988776655443322110099887766.scope"
        )
        try fixture.write(
            pid: 102,
            cgroup: "0::/docker/aabbccddeeff00112233445566778899aabbccddeeff0011223344556677"
        )
        try fixture.write(pid: 103, cgroup: "0::/user.slice/session-3.scope")

        // 104 is never written at all: a process can exit between the process
        // list and the cgroup read, and that has to be silent rather than noisy.
        let output = try await fixture.run(pids: [101, 102, 103, 104])

        #expect(output == ["container=101 3f2a1b0c9d8e", "container=102 aabbccddeeff"])
    }

    @Test
    func theShellFunctionPrefersTheRuntimesFriendlyName() async throws {
        let fixture = try FixtureProc()
        try fixture.write(
            pid: 101,
            cgroup: "0::/docker/3f2a1b0c9d8e7f6a5b4c3d2e1f009988776655443322110099887766"
        )
        try fixture.write(
            pid: 102,
            cgroup: "0::/docker/aabbccddeeff00112233445566778899aabbccddeeff0011223344556677"
        )
        // A container the runtime does not list — stopped between the two reads,
        // or owned by a runtime that is not installed.
        try fixture.write(
            pid: 103,
            cgroup: "0::/docker/cccccccccccc00112233445566778899aabbccddeeff0011223344556677"
        )

        try fixture.installFakeDocker(listing: """
        3f2a1b0c9d8e7f6a5b4c3d2e1f009988776655443322110099887766 web
        aabbccddeeff00112233445566778899aabbccddeeff0011223344556677 api-worker
        """)

        let output = try await fixture.run(pids: [101, 102, 103])

        #expect(output == [
            "container=101 web",
            "container=102 api-worker",
            "container=103 cccccccccccc",
        ])
    }

    /// Little Herd never requires socket access. When the account does not have
    /// it — the usual case for an SSH login outside the `docker` group — the
    /// short ID still identifies the container, and is what `docker ps` prints.
    @Test
    func theShortIDSurvivesARuntimeThatCannotAnswer() async throws {
        let fixture = try FixtureProc()
        try fixture.write(
            pid: 101,
            cgroup: "0::/docker/3f2a1b0c9d8e7f6a5b4c3d2e1f009988776655443322110099887766"
        )
        try fixture.installFakeDocker(
            script: """
            echo "permission denied while trying to connect to the Docker daemon" >&2
            exit 1
            """
        )

        let output = try await fixture.run(pids: [101])

        #expect(output == ["container=101 3f2a1b0c9d8e"])
    }

    // MARK: - Folding it back into the activity rows

    @Test
    func containerNamesReachTheActivityRows() {
        let output = """
        activity=185.4 202 /usr/bin/node
        container=202 web
        activity=42.0 303 /usr/bin/postgres
        activity=12.0 404 /usr/bin/python3
        container=404 batch
        """

        let activities = RemoteOutputParser.parseActivities(output)

        #expect(activities.count == 3)
        #expect(activities[0].containerName == "web")
        #expect(String(localized: activities[0].shortLabel) == "node · web")
        // Not every process is in a container, and the host ones must read
        // exactly as they did before.
        #expect(activities[1].containerName == nil)
        #expect(String(localized: activities[1].shortLabel) == "postgres")
        #expect(activities[2].containerName == "batch")
    }

    /// The reason the container belongs in the consolidation key. Two services
    /// both running `node` used to merge into one row holding their summed CPU,
    /// which named whichever container held the busier process and charged it
    /// for work it did not do.
    @Test
    func identicalProcessesInDifferentContainersStaySeparate() {
        let output = """
        activity=60.0 201 /usr/bin/node
        container=201 web
        activity=40.0 202 /usr/bin/node
        container=202 api
        """

        let activities = RemoteOutputParser.parseActivities(output)

        #expect(activities.count == 2)
        #expect(activities[0].cpuPercent == 60)
        #expect(activities[0].containerName == "web")
        #expect(activities[1].cpuPercent == 40)
        #expect(activities[1].containerName == "api")
    }

    /// Consolidation within one container still has to work, or a container
    /// running four workers would fill the whole list with itself.
    @Test
    func identicalProcessesInOneContainerStillMerge() {
        let output = """
        activity=60.0 201 /usr/bin/node
        container=201 web
        activity=40.0 202 /usr/bin/node
        container=202 web
        """

        let activities = RemoteOutputParser.parseActivities(output)

        #expect(activities.count == 1)
        #expect(activities[0].cpuPercent == 100)
        #expect(activities[0].containerName == "web")
    }

    /// The container is a qualifier, not a kind: work done inside one is still
    /// classified — and still labelled — by what it is.
    @Test
    func aContainerDoesNotReplaceWhatTheProcessIsDoing() {
        let output = """
        activity=185.4 202 /usr/bin/clang++
        context=202 /Users/example/local-code/little-herd
        container=202 build-runner
        """

        let activities = RemoteOutputParser.parseActivities(output)

        #expect(activities.count == 1)
        #expect(activities[0].kind == .compiling)
        #expect(
            String(localized: activities[0].shortLabel)
                == "Compiling Little Herd · build-runner"
        )
        #expect(
            String(localized: activities[0].tooltip)
                .hasSuffix("(container build-runner)")
        )
    }
}

private enum FixtureProcError: Error {
    case shellProducedNothing
}

/// A throwaway `/proc` the shell function can be pointed at, plus somewhere to
/// put a `docker` that answers however the test needs it to.
private struct FixtureProc {
    let path: String
    let binPath: String

    init() throws {
        path = NSTemporaryDirectory()
            .appending("little-herd-proc-\(UUID().uuidString)")
        binPath = "\(path)/bin"
        try FileManager.default.createDirectory(
            atPath: binPath,
            withIntermediateDirectories: true
        )

        // Shadow both runtimes with stubs that answer nothing, so a Docker the
        // developer happens to be running cannot reach into these assertions.
        // A test that wants names installs its own over the top.
        for runtime in ["docker", "podman"] {
            try installStub(named: runtime, script: "exit 1")
        }
    }

    func write(pid: Int, cgroup: String) throws {
        let directory = "\(path)/\(pid)"
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true
        )
        try (cgroup + "\n").write(
            toFile: "\(directory)/cgroup",
            atomically: true,
            encoding: .utf8
        )
    }

    func installFakeDocker(listing: String) throws {
        try installFakeDocker(script: """
        [ "$1" = "ps" ] || exit 1
        cat <<'LISTING'
        \(listing)
        LISTING
        """)
    }

    func installFakeDocker(script: String) throws {
        try installStub(named: "docker", script: script)
    }

    private func installStub(named name: String, script: String) throws {
        let executable = "\(binPath)/\(name)"
        try "#!/bin/sh\n\(script)\n".write(
            toFile: executable,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executable
        )
    }

    /// Runs the shipping shell function, with the fixture's `bin` ahead of the
    /// real PATH so a fake `docker` is found and the developer's own is not.
    func run(pids: [Int]) async throws -> [String] {
        let script = """
        PATH="\(binPath):$PATH"
        export PATH
        \(ContainerAttributionProbe.shellFunction(procDirectory: path))
        printf '%s\\n' \(pids.map(String.init).joined(separator: " ")) | little_herd_containers
        """

        guard let output = await LocalProcessRunner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", script]
        ) else {
            throw FixtureProcError.shellProducedNothing
        }

        return output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }
}
