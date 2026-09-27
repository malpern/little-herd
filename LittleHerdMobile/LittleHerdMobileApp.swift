import BackgroundTasks
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
/// hot, what is waiting on you, whether the Linux box is even up — and, now
/// that writes are signed, moving work off the machine that is struggling.
@main
struct LittleHerdMobileApp: App {
    @UIApplicationDelegateAdaptor(HerdAppDelegate.self) private var appDelegate
    @State private var client = HerdClient()
    @Environment(\.scenePhase) private var scenePhase

    static let refreshTask = "com.malpern.LittleHerdMobile.refresh"

    var body: some Scene {
        WindowGroup {
            HerdView(client: client)
                .onAppear {
                    HerdAppDelegate.onToken = { token in
                        Task { await client.registerPush(token: token, environment: PushEnvironment.current) }
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Self.scheduleRefresh() }
        }
        // Not a promise of timing — iOS decides, from how the app is used —
        // but it is how an alert reaches a phone whose watcher has no push
        // key. Each run reads the herd once and says anything new.
        .backgroundTask(.appRefresh(Self.refreshTask)) {
            Self.scheduleRefresh()
            await client.refresh()
            if let snapshot = await client.snapshot {
                await HerdNotifier.shared.observe(snapshot)
            }
        }
    }

    nonisolated static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
