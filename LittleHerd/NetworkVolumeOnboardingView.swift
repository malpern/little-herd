import SwiftUI

struct NetworkVolumeOnboardingView: View {
    let isRequesting: Bool
    let onContinue: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LittleHerdOnboardingHero()
                .padding(.top, 16)

            LittleHerdOnboardingBenefits()
                .padding(.top, 14)

            NetworkVolumeNextStep()
                .padding(.top, 12)

            Spacer(minLength: 12)

            NetworkVolumeOnboardingActions(
                isRequesting: isRequesting,
                onContinue: onContinue,
                onNotNow: onNotNow
            )
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LittleHerdTheme.background)
    }
}

private struct LittleHerdOnboardingHero: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: -12) {
                OnboardingAnimal(
                    avatar: .chickLaptop,
                    size: 64,
                    verticalOffset: 7
                )
                OnboardingAnimal(
                    avatar: .calfMini,
                    size: 74,
                    verticalOffset: 0
                )
                OnboardingAnimal(
                    avatar: .oxGPU,
                    size: 64,
                    verticalOffset: 7
                )
            }
            .frame(height: 78)
            .accessibilityHidden(true)

            Text("Put your herd to work")
                .font(.title2.weight(.bold))

            Text("See the load across your Macs, Linux boxes, and AI coding sessions—then pick the right machine for the next job.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 355)
        }
    }
}

private struct OnboardingAnimal: View {
    let avatar: HerdwareAvatar
    let size: CGFloat
    let verticalOffset: CGFloat

    var body: some View {
        Image(avatar.assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .padding(5)
            .background(
                LittleHerdTheme.loadTeal.opacity(0.1),
                in: Circle()
            )
            .overlay(
                Circle()
                    .stroke(.white.opacity(0.85), lineWidth: 2)
            )
            .offset(y: verticalOffset)
    }
}

private struct LittleHerdOnboardingBenefits: View {
    var body: some View {
        HStack(spacing: 8) {
            OnboardingBenefit(
                symbolName: "gauge.with.dots.needle.33percent",
                title: "See load"
            )
            OnboardingBenefit(
                symbolName: "sparkles",
                title: "Find room"
            )
            OnboardingBenefit(
                symbolName: "terminal",
                title: "Follow agents"
            )
        }
    }
}

private struct OnboardingBenefit: View {
    let symbolName: String
    let title: LocalizedStringResource

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.body.weight(.medium))
                .foregroundStyle(LittleHerdTheme.forest)

            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(.white.opacity(0.52), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LittleHerdTheme.forest.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct NetworkVolumeNextStep: View {
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.title3.weight(.medium))
                .foregroundStyle(LittleHerdTheme.forest)
                .frame(width: 32, height: 32)
                .background(
                    LittleHerdTheme.forest.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 8)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Next: include shared storage")
                    .font(.caption.weight(.semibold))

                Text("macOS will ask for network-volume access. Little Herd reads names and available capacity only.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            LittleHerdTheme.forest.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(LittleHerdTheme.forest.opacity(0.08), lineWidth: 1)
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
                .frame(minWidth: 126)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(LittleHerdTheme.forest)
            .keyboardShortcut(.defaultAction)
            .disabled(isRequesting)
        }
    }
}
