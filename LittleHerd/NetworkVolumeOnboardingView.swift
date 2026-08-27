import SwiftUI

/// The one screen that asks the user for something.
///
/// **Rewritten because it was built for the cream window and never adapted.**
/// Its surfaces were literal white at half opacity and its marks were
/// `HerdForest`, a green chosen to sit on paper — so in dark mode the cards
/// became grey slabs and the icons on them all but disappeared. Every fill
/// here is semantic now, and the one green is the mid-tone the thermometer
/// uses, which carries on both grounds.
///
/// It is also shorter. It had a hero, three feature chips, and an explanation
/// card, and the chips said what the sentence above them already said —
/// marketing on a screen whose actual job is to explain a system prompt that
/// is about to appear.
struct NetworkVolumeOnboardingView: View {
    let isRequesting: Bool
    let onContinue: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHerd()
                .padding(.top, 26)

            VStack(spacing: 7) {
                Text("Put your herd to work")
                    .font(.title2.weight(.bold))

                Text("See the load across your Macs, Linux boxes, and the AI sessions running on them — then pick the right machine for the next job.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 330)
            }
            .padding(.top, 18)

            Spacer(minLength: 18)

            NetworkVolumeNextStep()

            NetworkVolumeOnboardingActions(
                isRequesting: isRequesting,
                onContinue: onContinue,
                onNotNow: onNotNow
            )
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LittleHerdTheme.background)
    }
}

/// Three of the herd, overlapping.
///
/// No rings. They were a two-point white stroke, which on the cream ground
/// separated the animals and on the dark one drew three bright circles that
/// were the first thing you saw. A shadow does the same separating and belongs
/// to whatever is behind it.
private struct OnboardingHerd: View {
    var body: some View {
        HStack(spacing: -14) {
            animal(.chickLaptop, size: 66, lift: 8)
            animal(.calfMini, size: 78, lift: 0)
            animal(.oxGPU, size: 66, lift: 8)
        }
        .frame(height: 82)
        .accessibilityHidden(true)
    }

    private func animal(
        _ avatar: HerdwareAvatar,
        size: CGFloat,
        lift: CGFloat
    ) -> some View {
        Image(avatar.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            .offset(y: lift)
    }
}

/// What the next tap will do, which is the reason this screen exists.
private struct NetworkVolumeNextStep: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.title3.weight(.medium))
                // The thermometer's green rather than the wordmark's: this one
                // is a mid-tone and reads on paper and on near-black alike.
                .foregroundStyle(LittleHerdTheme.loadGreen)
                .frame(width: 34, height: 34)
                .background(
                    LittleHerdTheme.loadGreen.opacity(0.12),
                    in: RoundedRectangle(
                        cornerRadius: HerdRadius.surface,
                        style: .continuous
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Next: include shared storage")
                    .font(.callout.weight(.semibold))

                Text("macOS will ask for network-volume access. Little Herd reads names and available capacity only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            .quaternary.opacity(0.5),
            in: RoundedRectangle(
                cornerRadius: HerdRadius.panel,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: HerdRadius.panel, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }
}

private struct NetworkVolumeOnboardingActions: View {
    let isRequesting: Bool
    let onContinue: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Not Now", action: onNotNow)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isRequesting)

            Button(action: onContinue) {
                HStack(spacing: 6) {
                    if isRequesting {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isRequesting ? "Waiting for macOS…" : "Continue")
                }
                .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(LittleHerdTheme.loadGreen)
            .keyboardShortcut(.defaultAction)
            .disabled(isRequesting)
        }
    }
}
