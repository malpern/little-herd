import SwiftUI

/// Says, unmistakably, that this is not the app you installed.
///
/// **Compiled out of Release entirely rather than hidden by a flag.** A runtime
/// check can be got wrong — a preference read the wrong way round, a default
/// that flips — and the failure mode is a shipped build wearing a stripe. This
/// exists only in Debug, so `scripts/release`, which builds Release, cannot
/// carry it whatever anybody sets.
///
/// Drawn as an overlay and never in the layout. This window's height is set
/// from `DashboardMetrics` to the point, and anything that adds to the content
/// pushes the metric tabs off the bottom — which has happened three times and
/// is invisible until somebody looks at the window rather than the tests.
struct DevelopmentBanner: View {
    var body: some View {
        #if DEBUG
        Text("DEVELOPMENT BUILD")
            .font(.system(size: 8, weight: .heavy, design: .rounded))
            .kerning(0.6)
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.84, blue: 0.15),
                            Color(red: 1.00, green: 0.55, blue: 0.10),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            )
            .overlay(Capsule().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.30), radius: 3, y: 1)
            .padding(.top, 3)
            // It must never be the thing a click lands on: this window is
            // small and every point of it is doing something.
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        #endif
    }
}
