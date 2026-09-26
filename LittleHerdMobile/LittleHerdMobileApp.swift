import SwiftUI

/// Little Herd on a phone.
///
/// **It reads; it does not measure.** Everything on screen came from a Mac
/// that is the herd's watcher, over `HerdWire` — the one file this target
/// shares with the Mac app. There is no sampler here and there must not be
/// one: a phone cannot ssh-poll in the background, and a phone that polls in
/// the foreground is a worse watcher than the Mac that already is one.
///
/// **What it is for is the herd, not the sessions.** Remote Control and the
/// Claude app already let you steer a session from a phone, with the
/// filesystem attached. What had no answer was the herd: which machine is
/// hot, what is waiting on you, whether the Linux box is even up. That is the
/// whole screen.
@main
struct LittleHerdMobileApp: App {
    @State private var client = HerdClient()

    var body: some Scene {
        WindowGroup {
            HerdView(client: client)
        }
    }
}
