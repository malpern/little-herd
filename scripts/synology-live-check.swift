import Foundation

// Drives the real SynologyDSMClient against a live NAS: TLS challenge, sign-in,
// both reads, sign-out — plus the refuse path with a deliberately wrong pin.
// Host and account are substituted in by scripts/synology-live-check.
//
// The password is read by running sops here, so it never appears in an argument
// list, an environment variable, or on screen.
func password() -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c",
        "SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt "
        + "sops -d \"$HOME/dotfiles/secrets.env\" "
        + "| grep '^SYNOLOGY_PASSWORD_HOME=' | cut -d= -f2-"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let secret = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return secret.isEmpty ? nil : secret
}

final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var failures = 0
    func check(_ label: String, _ condition: Bool) {
        print("  \(condition ? "PASS" : "FAIL")  \(label)")
        if !condition { lock.withLock { failures += 1 } }
    }
    var count: Int { lock.withLock { failures } }
}
let tally = Tally()
func check(_ label: String, _ condition: Bool) { tally.check(label, condition) }

let endpoint = SynologyDSMEndpoint(host: "__HOST__", username: "__ACCOUNT__")
guard let secret = password() else {
    print("could not decrypt the password"); exit(2)
}

print("== real client against the live NAS ==")
let client = SynologyDSMClient(
    endpoint: endpoint, pinnedCertificate: nil, passwordProvider: { secret }
)

do {
    let storage = try await client.storage()
    let volumes = SynologyDSMParser.storageVolumes(from: storage)
    let drives = SynologyDSMParser.drives(from: storage)
    check("signed in and read storage", true)
    check("volumes parsed", !volumes.isEmpty)
    check("volume named readably", volumes.allSatisfy { !$0.name.hasPrefix("volume_") })
    check("capacities sane", volumes.allSatisfy { $0.totalBytes > 0 && $0.availableBytes <= $0.totalBytes })
    check("drives parsed", !drives.isEmpty)
    for volume in volumes {
        print("    volume \(volume.name) \(String(format: "%.1f", volume.usedPercent))% used, health=\(volume.health.map(\.rawValue) ?? "nil")")
    }
    for drive in drives {
        print("    \(drive.name) health=\(drive.health.rawValue) unc=\(drive.uncorrectableSectors) temp=\(drive.temperatureCelsius.map { String(Int($0)) } ?? "-")")
    }

    let utilization = try await client.utilization()
    let cpu = SynologyDSMParser.cpuReading(from: utilization)
    let memory = SynologyDSMParser.memoryReading(from: utilization)
    check("cpu reading in range", (cpu?.value).map { $0 >= 0 && $0 <= 100 } ?? false)
    check("memory reading in range", (memory?.value).map { $0 >= 0 && $0 <= 100 } ?? false)
    print("    cpu=\(cpu?.value ?? -1)%  memory=\(memory?.value ?? -1)%")

    let fingerprint = await client.observedCertificate
    check("certificate fingerprint recorded", fingerprint?.count == 64)
    print("    pin=\(fingerprint ?? "nil")")
    await client.signOut()
    check("signed out", true)
} catch {
    check("live read succeeded (got \(error))", false)
}

print("== a pin that does not match must be refused ==")
let pinned = SynologyDSMClient(
    endpoint: endpoint,
    pinnedCertificate: String(repeating: "0", count: 64),
    passwordProvider: { secret }
)
do {
    _ = try await pinned.storage()
    check("mismatched pin refused", false)
} catch let error as SynologyDSMError {
    if case .certificateChanged = error {
        check("mismatched pin refused with certificateChanged", true)
    } else {
        check("mismatched pin refused with certificateChanged (got \(error))", false)
    }
} catch {
    check("mismatched pin refused (unexpected \(error))", false)
}

print("== a wrong password must read as DSM refusing, not a transport failure ==")
let wrong = SynologyDSMClient(
    endpoint: endpoint, pinnedCertificate: nil,
    passwordProvider: { "almost-certainly-not-the-password" }
)
do {
    try await wrong.signIn()
    check("wrong password rejected", false)
} catch let error as SynologyDSMError {
    if case .api(let code, let detail) = error {
        check("DSM error code \(code)", code == 400 || code == 407)
        print("    detail: \(detail)")
    } else {
        check("expected a DSM api error, got \(error)", false)
    }
} catch {
    check("expected a DSM api error, got \(error)", false)
}

print(tally.count == 0 ? "\nALL CHECKS PASSED" : "\n\(tally.count) CHECK(S) FAILED")
exit(tally.count == 0 ? 0 : 1)
