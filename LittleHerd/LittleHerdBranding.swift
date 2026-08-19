import AppKit
import SwiftUI

@MainActor
enum LittleHerdLaunchSplashSession {
    private static var hasPresented = false

    static func claimPresentation() -> Bool {
        guard !hasPresented else { return false }
        hasPresented = true
        return true
    }
}

/// The splash's geometry and timing, shared with the window chrome that frames
/// it so the two cannot drift apart.
enum LittleHerdSplashMetrics {
    /// Read both by the splash view, which clips its own artwork, and by
    /// `DashboardWindowBridge`, which rounds the window. Rounding in only one
    /// of those places is what produced the pale fringe along the curve: the
    /// layer mask antialiased the artwork against an opaque backing, and the
    /// backing showed through as a halo hugging each corner.
    static let cornerRadius: CGFloat = 26

    /// How long the artwork takes to arrive.
    static let entranceDuration: Double = 0.42

    /// How long it stays *after* arriving. The splash used to hold for 1.05
    /// seconds including its own entrance, which left it fully drawn for barely
    /// half a second — long enough to register as a flicker rather than a
    /// greeting.
    static let holdAfterEntrance: Double = 1.0

    /// What the launch flow waits for before dismissing.
    static var minimumDuration: Double { entranceDuration + holdAfterEntrance }
}

struct LittleHerdSplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Image("LittleHerdSplash")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(isPresented ? 1 : 1.025)
                .opacity(isPresented ? 1 : 0)
                .accessibilityHidden(true)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 104)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            LittleHerdSplashCaption()
                .padding(.bottom, 29)
                .opacity(isPresented ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LittleHerdTheme.background)
        .clipShape(
            RoundedRectangle(
                cornerRadius: LittleHerdSplashMetrics.cornerRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
        .onAppear {
            if reduceMotion {
                isPresented = true
            } else {
                withAnimation(
                    .easeOut(duration: LittleHerdSplashMetrics.entranceDuration)
                ) {
                    isPresented = true
                }
            }
        }
    }
}

private struct LittleHerdSplashCaption: View {
    var body: some View {
        VStack(spacing: 3) {
            Text("Little Herd")
                .font(.title2.weight(.bold))

            Text("Your machines, working together.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.86))

            ProgressView()
                .controlSize(.mini)
                .tint(.white)
                .environment(\.colorScheme, .dark)
                .padding(.top, 2)
                .accessibilityLabel("Gathering your machines")
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.32), radius: 3, y: 1)
    }
}

@MainActor
enum AboutLittleHerdPresenter {
    static func present() {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
            .paragraphStyle: paragraphStyle,
        ]
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.linkColor,
            .paragraphStyle: paragraphStyle,
        ]

        let credits = NSMutableAttributedString(
            string: "A friendly system monitor for the machines you use to build.\n\n",
            attributes: bodyAttributes
        )
        credits.append(
            NSAttributedString(
                string: "Micah Alpern\n",
                attributes: bodyAttributes.merging([
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                ]) { _, new in new }
            )
        )
        credits.append(
            NSAttributedString(
                string: "@malpern",
                attributes: linkAttributes.merging([
                    .link: URL(string: "https://twitter.com/malpern")!,
                ]) { _, new in new }
            )
        )
        credits.append(NSAttributedString(string: "  ·  ", attributes: bodyAttributes))
        credits.append(
            NSAttributedString(
                string: "github.com/malpern/little-herd",
                attributes: linkAttributes.merging([
                    .link: URL(
                        string: "https://github.com/malpern/little-herd"
                    )!,
                ]) { _, new in new }
            )
        )

        // Sparkle is MIT licensed, which requires its notice to travel with
        // every copy of the app — not only with the source repository.
        credits.append(
            NSAttributedString(string: "\n\n", attributes: bodyAttributes)
        )
        credits.append(
            NSAttributedString(
                string: "Updates powered by Sparkle, © the Sparkle contributors, MIT licensed.\n",
                attributes: bodyAttributes.merging([
                    .font: NSFont.systemFont(ofSize: 10),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]) { _, new in new }
            )
        )
        credits.append(
            NSAttributedString(
                string: "Full third-party notices",
                attributes: linkAttributes.merging([
                    .font: NSFont.systemFont(ofSize: 10),
                    .link: URL(
                        string: "https://github.com/malpern/little-herd/blob/main/THIRD-PARTY-LICENSES.md"
                    )!,
                ]) { _, new in new }
            )
        )

        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Little Herd",
            .credits: credits,
        ]

        if let applicationIcon = NSApp.applicationIconImage {
            options[.applicationIcon] = applicationIcon
        }

        if let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String {
            options[.applicationVersion] = version
        }

        if let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String {
            options[.version] = "Build \(build)"
        }

        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}
