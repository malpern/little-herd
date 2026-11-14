import Foundation
import Testing

@testable import LittleHerd

/// The install that stays on duty, and how its alerts reach a person.
///
/// **The app could already say a machine was in trouble; it could not say it when
/// nobody was looking.** Alerts fire from whichever install is open, so the moment that
/// matters most — you are away and a disk fills — is the moment nothing is running.
@Suite("The designated watcher")
struct DesignatedWatcherTests {
    @Test @MainActor
    func watcherDeliversAnAlertAndRecoveryAfterTheDashboardCloses() async throws {
        let suite = "LittleHerdWatcherTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: LittleHerdPreferences.alertsEnabledKey)
        defaults.set(true, forKey: LittleHerdPreferences.watchesHerdKey)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let script = directory.appendingPathComponent("notify")
        let output = directory.appendingPathComponent("alerts")
        try """
        #!/bin/sh
        [ -n "$2" ] || exit 1
        printf '%s\\n' "$1" >> \(RemoteShell.quoted(output.path))
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

        let sampler = WatcherTestSampler()
        let model = MonitorModel(
            configurations: [.local(computerName: "Watcher Test")],
            defaults: defaults,
            alerts: MachineAlertCenter { title, body in
                MachineAlertCenter.runAlertCommand(script.path, title: title, body: body)
            },
            makeLocalSampler: { sampler }
        )
        model.activate(.dashboard)
        model.updateWatcherFromPreferences()
        model.deactivate(.dashboard)
        defer {
            defaults.set(false, forKey: LittleHerdPreferences.watchesHerdKey)
            model.updateWatcherFromPreferences()
        }

        let expected = ["Watcher Test is under memory pressure", "Watcher Test memory recovered"]
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        var delivered: [String] = []
        while clock.now < deadline {
            delivered = (try? String(contentsOf: output, encoding: .utf8))?
                .split(separator: "\n").map(String.init) ?? []
            if delivered.count >= expected.count { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(delivered == expected)

        defaults.set(false, forKey: LittleHerdPreferences.alertsEnabledKey)
        model.updateWatcherFromPreferences()
        #expect(model.machines.first?.state == .stopped)
    }

    /// **A machine name is user text and it reaches the command.** "Micah's MacBook Air"
    /// already carries an apostrophe; a name carrying `; rm -rf ~` would too. Passing
    /// arguments rather than building a shell string is what makes that a title instead
    /// of a command.
    @Test
    func thetitleAndBodyAreArgumentsNotAshellString() throws {
        let seen = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watcher-args-\(UUID().uuidString).txt")
        let script = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watcher-\(UUID().uuidString).sh")
        // Writes each argument on its own line, so the test can see how they arrived.
        try "#!/bin/sh\nfor a in \"$@\"; do echo \"$a\"; done > \(seen.path)\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        defer {
            try? FileManager.default.removeItem(at: script)
            try? FileManager.default.removeItem(at: seen)
        }

        let hostile = "Micah’s Mac; rm -rf ~"
        MachineAlertCenter.runAlertCommand(
            script.path, title: "\(hostile) is almost out of space", body: "Disk 98% full.")

        // The process is spawned, so wait briefly for it to land.
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: seen.path), Date() < deadline {
            usleep(50_000)
        }
        let lines = try String(contentsOf: seen, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(lines.count == 2, "exactly two arguments, however hostile the name")
        #expect(lines.first == "\(hostile) is almost out of space")
        #expect(lines.last == "Disk 98% full.")
    }

    /// A command that is not there must not become a second problem. The local
    /// notification has already gone out; a failed hand-off is not worth an alert.
    @Test
    func amissingCommandFailsQuietly() {
        MachineAlertCenter.runAlertCommand(
            "/nonexistent/notify", title: "t", body: "b")
        MachineAlertCenter.runAlertCommand("", title: "t", body: "b")
    }

    /// A command may carry one argument of its own — `notify-push --urgent`, say — and
    /// the title and body still arrive after it.
    @Test
    func acommandMayCarryItsOwnArgument() throws {
        let seen = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watcher-flag-\(UUID().uuidString).txt")
        let script = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("watcher-\(UUID().uuidString).sh")
        try "#!/bin/sh\nfor a in \"$@\"; do echo \"$a\"; done > \(seen.path)\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path)
        defer {
            try? FileManager.default.removeItem(at: script)
            try? FileManager.default.removeItem(at: seen)
        }

        MachineAlertCenter.runAlertCommand("\(script.path) --urgent", title: "T", body: "B")
        let deadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: seen.path), Date() < deadline {
            usleep(50_000)
        }
        let lines = try String(contentsOf: seen, encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(lines == ["--urgent", "T", "B"])
    }

    /// **The three switches are separate keys**, so being the watcher, being quiet, and
    /// alerting at all cannot be conflated — a laptop you are sitting at may reasonably
    /// want to alert even though the mini is on duty.
    @Test
    func thepreferencesAreDistinct() {
        let keys = Set([
            LittleHerdPreferences.alertsEnabledKey,
            LittleHerdPreferences.watchesHerdKey,
            LittleHerdPreferences.alertsSuppressedKey,
            LittleHerdPreferences.alertCommandKey,
        ])
        #expect(keys.count == 4)
    }
}

private actor WatcherTestSampler: LocalMetricsSampling {
    private var samples = 0

    func prime() {}

    func sample() -> SystemSnapshot {
        samples += 1
        return SystemSnapshot(
            timestamp: .now, readings: [:],
            memoryPressure: samples == 1 ? .critical : nil
        )
    }
}
