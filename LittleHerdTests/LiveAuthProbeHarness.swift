import Foundation
import Testing

@testable import LittleHerd

/// Does `AgentAuthVerifier.verify` return, against a real machine?
///
/// **Not part of the suite.** It talks to the mini and spends a model call, so
/// it is gated the way `LiveTransferHarness` is — by an environment variable
/// rather than `.disabled`, so it can still be asked for by name.
///
/// It exists to split one question in two. `little-herd move` hangs at the
/// sign-in probe: main thread parked on its semaphore, every worker idle, no
/// `ssh` in the process tree. Either `verify` itself does not return, or the
/// command's habit of blocking a thread while awaiting it is what stops it.
/// This calls `verify` from a test, where nothing blocks anything, and the
/// answer says which half to fix.
///
///     LITTLE_HERD_LIVE=1 xcodebuild test -scheme LittleHerd \
///       -destination 'platform=macOS' \
///       -only-testing:LittleHerdTests/LiveAuthProbeHarness
@Suite(
    "Live auth probe",
    .enabled(if: ProcessInfo.processInfo.environment["LITTLE_HERD_LIVE"] == "1")
)
struct LiveAuthProbeHarness {
    @Test
    func theProbeAgainstTheMiniReturns() async {
        let install = AgentInstallation(
            provider: .claude,
            version: "live",
            path: "/Users/malpern/Library/Application Support/Claude/"
                + "claude-code/2.1.255/claude.app/Contents/MacOS/claude"
        )
        let started = Date()
        let state = await AgentAuthVerifier.verify(
            install: install,
            isLocal: false,
            host: "malpern@mini",
            identityFile: nil
        )
        let took = Date().timeIntervalSince(started)
        print("=== verify returned \(state) after \(Int(took))s")
        // The probe's own watchdog is 90 seconds, so anything at or beyond it
        // means the watchdog did not fire either — which is the interesting
        // failure rather than a slow machine.
        #expect(took < AgentAuthVerifier.timeout, "the probe outlived its own watchdog")
    }
}
