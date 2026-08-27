import AppKit
import SwiftUI

/// How much of each provider's AI allowance is left, wherever that readout is
/// asked for — the overview header carries it, and so does the bar above a
/// single machine, so that it does not blink out when you drop into one.
///
/// Its own file because it is a self-contained readout with an appearance
/// nothing else shares: a lit status mark per provider, and glyphs borrowed at
/// runtime from Codex's and Claude's own installed bundles rather than drawn
/// from our asset catalog, which is `NSImage` work with no business sitting
/// inside a view hierarchy.

struct AIUsageLimitsSummary: View {
    let model: AIUsageLimitsModel

    var body: some View {
        AIUsageLimitRows(
            codex: model.codex,
            claude: model.claude
        )
        .fixedSize()
    }
}

struct AIUsageLimitRows: View {
    let codex: AIUsageAvailability
    let claude: AIUsageAvailability

    var body: some View {
        VStack(spacing: 0) {
            AIUsageLimitRow(
                provider: .codex,
                availability: codex
            )
            AIUsageLimitRow(
                provider: .claude,
                availability: claude
            )
        }
    }
}

struct AIUsageLimitRow: View {
    let provider: AIUsageProvider
    let availability: AIUsageAvailability

    /// Asked on each render rather than cached: the answer changes the moment
    /// someone starts or quits CodexBar, and a stale "not running" that offers
    /// to start an app already running is worse than no offer.
    private var offer: CodexBarOffer {
        CodexBarOffer.resolve(
            availability: availability,
            isInstalled: CodexBarSource.isInstalled,
            isRunning: CodexBarSource.isRunning
        )
    }

    var body: some View {
        AIUsageProviderControl(
            provider: provider,
            limit: limit,
            // A reading nobody can see is as useless as no reading, so every
            // state that cannot show a number offers the provider's own usage
            // page instead. Previously only the urgent state was clickable,
            // which left the one case with nothing to show also with nothing
            // to do. The link goes to the provider rather than to CodexBar:
            // Little Herd reads that app but does not recommend it.
            isActionable: isUrgent || limit == nil,
            accessibilityValue: accessibilityValue,
            helpText: helpText,
            offer: offer
        )
    }

    private var limit: AIUsageLimit? {
        availability.limit
    }

    private var isUrgent: Bool {
        limit?.budgetStatus == .urgent
    }

    private var accessibilityValue: Text {
        if let limit {
            Text(
                "\(limit.remainingPercent / 100, format: .percent.precision(.fractionLength(0))) left"
            )
        } else {
            Text("Usage unavailable")
        }
    }

    private var helpText: Text {
        if let limit, let resetsAt = limit.resetsAt {
            if isUrgent {
                Text(
                    "\(provider.displayName): \(limit.remainingPercent / 100, format: .percent.precision(.fractionLength(0))) remaining in the \(limit.windowDescription). Resets \(resetsAt, format: .dateTime.month().day().hour().minute()). Click to open usage and billing."
                )
            } else {
                Text(
                    "\(provider.displayName): \(limit.remainingPercent / 100, format: .percent.precision(.fractionLength(0))) remaining in the \(limit.windowDescription). Resets \(resetsAt, format: .dateTime.month().day().hour().minute())."
                )
            }
        } else if let limit {
            if isUrgent {
                Text(
                    "\(provider.displayName): \(limit.remainingPercent / 100, format: .percent.precision(.fractionLength(0))) remaining in the \(limit.windowDescription). Click to open usage and billing."
                )
            } else {
                Text(
                    "\(provider.displayName): \(limit.remainingPercent / 100, format: .percent.precision(.fractionLength(0))) remaining in the \(limit.windowDescription)."
                )
            }
        } else {
            switch availability {
            case .available:
                Text("\(provider.displayName) usage unavailable")
            case .sourceMissing:
                Text(
                    "\(provider.displayName) usage needs CodexBar, which isn’t installed on this Mac. Little Herd reads it; it can’t measure this itself. Click to see what it is."
                )
            case let .stale(since):
                Text(
                    "\(provider.displayName) usage last updated \(since, format: .relative(presentation: .named)). CodexBar isn’t running, so the figure has stopped moving. Click to start it."
                )
            case .noReading:
                Text(
                    "CodexBar has no \(provider.displayName) reading yet. Click to open usage and billing."
                )
            }
        }
    }
}

struct AIUsageProviderControl: View {
    let provider: AIUsageProvider
    let limit: AIUsageLimit?
    let isActionable: Bool
    let accessibilityValue: Text
    let helpText: Text
    /// What to offer about the source itself, when the number is missing
    /// because of the source rather than because of the vendor.
    var offer: CodexBarOffer = .none

    var body: some View {
        if offer == .start {
            // A number that stopped moving is fixed by starting the thing that
            // moves it, not by opening a billing page. One click, no dialog:
            // the app is already on this Mac and starting it is undone by
            // quitting it.
            Button {
                CodexBarSource.launchIfNeeded()
            } label: {
                AIUsageProviderStatusMark(provider: provider, limit: limit)
            }
            .buttonStyle(.plain)
            .help(helpText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(provider.displayName))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Start CodexBar to resume usage readings")
        } else if offer == .install {
            Link(destination: CodexBarSource.downloadURL) {
                AIUsageProviderStatusMark(provider: provider, limit: limit)
            }
            .buttonStyle(.plain)
            .help(helpText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(provider.displayName))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Open the CodexBar project page")
        } else if isActionable {
            Link(destination: provider.usageAndBillingURL) {
                AIUsageProviderStatusMark(provider: provider, limit: limit)
            }
            .buttonStyle(.plain)
            .help(helpText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(provider.displayName))
            .accessibilityValue(accessibilityValue)
            .accessibilityHint("Open usage and billing")
        } else {
            AIUsageProviderStatusMark(provider: provider, limit: limit)
                .help(helpText)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(provider.displayName))
                .accessibilityValue(accessibilityValue)
        }
    }
}

struct AIUsageProviderStatusMark: View {
    let provider: AIUsageProvider
    let limit: AIUsageLimit?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AIUsageProviderIcon(provider: provider)

            AIUsageStatusLED(limit: limit)
                .offset(x: 2.5, y: 2.5)
        }
        .frame(width: 18, height: 18)
        .frame(width: 24, height: 24)
        .contentShape(Rectangle())
    }
}

struct AIUsageStatusLED: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let limit: AIUsageLimit?
    @State private var isDimmed = false

    var body: some View {
        statusShape
            .frame(width: 9, height: 9)
            // Follows the window, not a fixed white: this dot sits on the
            // avatar and has to separate from whatever is behind it.
            .background(LittleHerdTheme.background.opacity(0.96), in: Circle())
            .overlay {
                Circle()
                    .stroke(LittleHerdTheme.background, lineWidth: 1.25)
            }
            .scaleEffect(isBlinking && isDimmed ? 0.86 : 1)
            .opacity(isBlinking && isDimmed ? 0.35 : 1)
            .animation(
                isBlinking && !reduceMotion
                    ? .easeInOut(duration: 0.56).repeatForever()
                    : .easeOut(duration: 0.16),
                value: isDimmed
            )
            .animation(.easeInOut(duration: 0.35), value: limit?.remainingPercent)
            .onAppear {
                updateBlinkingState()
            }
            .onChange(of: isBlinking) { _, _ in
                updateBlinkingState()
            }
            .onChange(of: reduceMotion) { _, _ in
                updateBlinkingState()
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statusShape: some View {
        if let limit {
            Circle()
                .fill(statusColor(for: limit.budgetStatus))
        } else {
            Circle()
                .stroke(Color.secondary.opacity(0.42), lineWidth: 1)
        }
    }

    private var isBlinking: Bool {
        limit?.budgetStatus == .urgent && !reduceMotion
    }

    private var statusColor: Color {
        guard let limit else { return .clear }
        return statusColor(for: limit.budgetStatus)
    }

    private func statusColor(for status: AIUsageBudgetStatus) -> Color {
        switch status {
        case .normal: .green
        case .warning: .yellow
        case .critical: .orange
        case .urgent: .red
        }
    }

    private func updateBlinkingState() {
        isDimmed = isBlinking
    }
}

struct AIUsageProviderIcon: View {
    let provider: AIUsageProvider

    var body: some View {
        Image(nsImage: AIUsageProviderIcons.icon(for: provider))
            .resizable()
            .scaledToFit()
            .foregroundStyle(providerColor)
            .frame(width: 14, height: 14)
    }

    private var providerColor: Color {
        switch provider {
        case .codex: .primary
        case .claude: Color(red: 0.91, green: 0.29, blue: 0.16)
        }
    }
}

@MainActor
enum AIUsageProviderIcons {
    static let codex = providerGlyph(
        bundleIdentifier: "com.openai.codex",
        resourceName: "chatgptTemplate@2x",
        fallbackSymbolName: "sparkles"
    )
    static let claude = providerGlyph(
        bundleIdentifier: "com.anthropic.claudefordesktop",
        resourceName: "TrayIconTemplate-Dark@3x",
        fallbackSymbolName: "brain.head.profile"
    )

    static func icon(for provider: AIUsageProvider) -> NSImage {
        switch provider {
        case .codex: codex
        case .claude: claude
        }
    }

    static func icon(for provider: AgentTaskProvider) -> NSImage {
        switch provider {
        case .codex: codex
        case .claude: claude
        }
    }

    private static func providerGlyph(
        bundleIdentifier: String,
        resourceName: String,
        fallbackSymbolName: String
    ) -> NSImage {
        if let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ),
           let bundle = Bundle(url: applicationURL),
           let imageURL = bundle.url(
               forResource: resourceName,
               withExtension: "png"
           ),
           let image = NSImage(contentsOf: imageURL)
        {
            image.isTemplate = true
            return image
        }

        let fallback = NSImage(
            systemSymbolName: fallbackSymbolName,
            accessibilityDescription: nil
        ) ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }
}
