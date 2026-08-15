import Foundation
import Testing
@testable import LittleHerd

/// The strings here are what `ssh` actually printed on this machine while the
/// Mac mini was unreachable, rather than paraphrases — the classifier matches on
/// message text, so fixtures invented from memory would prove nothing.
struct RemoteUnavailabilityTests {
    @Test
    func aNameThatDoesNotResolveIsDistinguishedFromAMachineBeingDown() {
        // Exactly what ssh printed when Tailscale was not running, while the
        // machine itself was up and answering on the LAN.
        let unresolved = RemoteUnavailability.classify(
            standardError: "ssh: Could not resolve hostname keypath-lab-mini: nodename nor servname provided, or not known"
        )
        #expect(unresolved == .nameNotFound)

        let down = RemoteUnavailability.classify(
            standardError: "ssh: connect to host 192.168.1.99 port 22: Operation timed out"
        )
        #expect(down == .noAnswer)

        // The distinction is the entire point: these must not collapse together.
        #expect(unresolved != down)
    }

    @Test
    func linuxResolverWordingIsRecognisedToo() {
        #expect(
            RemoteUnavailability.classify(
                standardError: "ssh: Could not resolve hostname mini: Name or service not known"
            ) == .nameNotFound
        )
    }

    @Test
    func theOtherCommonSSHFailuresAreNamed() {
        let cases: [(String, RemoteUnavailability)] = [
            ("ssh: connect to host air port 22: No route to host", .noAnswer),
            ("ssh: connect to host mini port 22: Connection refused", .refused),
            ("malpern@linux: Permission denied (publickey).", .keyRejected),
            ("Host key verification failed.", .hostKeyChanged),
            ("@@@@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @@@@", .hostKeyChanged),
        ]
        for (message, expected) in cases {
            #expect(
                RemoteUnavailability.classify(standardError: message) == expected,
                "\(message) should classify as \(expected)"
            )
        }
    }

    @Test
    func anUnrecognisedFailureKeepsWhatSSHSaid() {
        // Text matching is fragile, so anything unknown has to carry the
        // original through rather than be discarded or guessed at.
        let classified = RemoteUnavailability.classify(
            standardError: "ssh: something entirely new went wrong\nsecond line"
        )
        #expect(classified == .other("ssh: something entirely new went wrong"))

        #expect(RemoteUnavailability.classify(standardError: "") == .other("no error output"))
    }

    @Test
    func monitorErrorsMapToTheirOwnCauses() {
        #expect(
            RemoteUnavailability.classify(RemoteMonitorError.invalidHost("-oProxyCommand=x"))
                == .unusableHostName
        )
        #expect(
            RemoteUnavailability.classify(RemoteMonitorError.invalidOutput)
                == .incompleteOutput
        )
        #expect(
            RemoteUnavailability.classify(
                RemoteMonitorError.commandFailed("ssh: Could not resolve hostname x: nodename nor servname provided, or not known")
            ) == .nameNotFound
        )
    }

    @Test
    func theNameNotFoundDetailPointsAtTheLikelyCause() {
        // This is the case that cost real time: the machine was fine and the
        // Mac reading it had no VPN, so the message has to say so.
        let detail = String(localized: RemoteUnavailability.nameNotFound.detail(host: "keypath-lab-mini"))
        #expect(detail.contains("keypath-lab-mini"))
        #expect(detail.lowercased().contains("vpn") || detail.contains("Tailscale"))
    }

    @Test
    func aMachineGoingOfflineThenLiveClearsTheReason() {
        let machine = MachineMonitorModel(
            configuration: MachineConfiguration(
                id: MachineID("mini"),
                name: "Mac mini",
                shortName: "Mini",
                hostname: "keypath-lab-mini",
                hardwareSummary: "Mac desktop",
                platform: .macOS,
                connection: .ssh,
                avatar: .calfMini,
                identityFile: nil,
                serverNames: [],
                supportsGPU: false
            )
        )

        machine.markOffline(.nameNotFound)
        #expect(machine.state == .offline)
        #expect(machine.unavailability == .nameNotFound)

        machine.apply(SystemSnapshot(timestamp: .now, readings: [:]))
        #expect(machine.state == .live)
        #expect(machine.unavailability == nil)
    }
}
