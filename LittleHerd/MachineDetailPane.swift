import AppKit
import SwiftUI

/// The shared shape of every focused-machine pane.
///
/// All four metrics answer the same question — *what is this machine doing with
/// this resource* — so they are built from one section header and one row
/// rather than four bespoke layouts. That is the macOS inspector idiom: a quiet
/// label with the headline figure on the right, then rows of glyph, name, and a
/// right-aligned value in monospaced digits so the numbers line up as they
/// change.
struct MetricDetailPane<Rows: View>: View {
    let title: LocalizedStringResource
    var summary: Text?
    var emptyMessage: LocalizedStringResource?
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .tracking(0.35)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                if let summary {
                    summary
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)

            if let emptyMessage {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    rows()
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }
}

/// One line of a pane. `accessory` carries anything that needs to sit beside
/// the value — a leak warning, a pressure symbol — without every caller
/// growing its own layout.
struct MetricDetailRow<Accessory: View>: View {
    let symbolName: String
    var tint: Color = .secondary
    /// When this resolves to an installed app, its icon leads the row instead
    /// of `symbolName`.
    var bundlePath: String?
    let title: Text
    var subtitle: Text?
    var value: Text?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 7) {
            ApplicationIcon(
                bundlePath: bundlePath,
                fallbackSymbol: symbolName,
                tint: tint,
                size: 14
            )

            VStack(alignment: .leading, spacing: 0) {
                title
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let subtitle {
                    subtitle
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 6)

            accessory()

            if let value {
                value
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension MetricDetailRow where Accessory == EmptyView {
    init(
        symbolName: String,
        tint: Color = .secondary,
        bundlePath: String? = nil,
        title: Text,
        subtitle: Text? = nil,
        value: Text? = nil
    ) {
        self.init(
            symbolName: symbolName,
            tint: tint,
            bundlePath: bundlePath,
            title: title,
            subtitle: subtitle,
            value: value,
            accessory: { EmptyView() }
        )
    }
}

/// Real app icons for the memory list.
///
/// The bundle path comes from the sampled process, so it resolves for anything
/// installed on this Mac — including apps sampled on a remote Mac, which
/// usually live at the same path. Anything else (command-line tools, Linux)
/// falls back to the row's glyph.
///
/// Icons are cached because the panes redraw on every sample; misses are cached
/// too, so a missing bundle is not stat'd every few seconds.
@MainActor
enum ApplicationIconCache {
    private static var icons: [String: NSImage?] = [:]

    private static var pathsByBundleIdentifier: [String: String?] = [:]

    /// Resolves an app by bundle identifier, for callers that know what app
    /// they want rather than where it lives.
    static func bundlePath(forAnyOf identifiers: [String]) -> String? {
        for identifier in identifiers {
            if let cached = pathsByBundleIdentifier[identifier] {
                if let cached { return cached }
                continue
            }
            let path = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: identifier)?
                .path
            pathsByBundleIdentifier[identifier] = path
            if let path { return path }
        }
        return nil
    }

    static func icon(atBundlePath path: String) -> NSImage? {
        if let cached = icons[path] { return cached }

        let icon: NSImage? = FileManager.default.fileExists(atPath: path)
            ? NSWorkspace.shared.icon(forFile: path)
            : nil
        icons[path] = icon
        return icon
    }
}

struct ApplicationIcon: View {
    let bundlePath: String?
    let fallbackSymbol: String
    var tint: Color = .secondary
    var size: CGFloat = 14

    var body: some View {
        if let bundlePath, let icon = ApplicationIconCache.icon(atBundlePath: bundlePath) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            Image(systemName: fallbackSymbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size)
                .accessibilityHidden(true)
        }
    }
}
