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
    /// Recent history for this pane's metric, drawn under the header.
    ///
    /// The list answers what is using the resource right now; the graph answers
    /// whether that is new. A process holding two cores means one thing on a
    /// flat line and another on a climbing one, and the list alone cannot tell
    /// them apart.
    var series: MetricSeries?
    var summary: Text?
    var emptyMessage: LocalizedStringResource?
    /// What to do about the empty state, when there is something to do.
    ///
    /// A message that names the fix and cannot perform it is a dead end, and
    /// the state with nothing to show is the one most in need of a way forward.
    /// Supplied only where a fix exists — a NAS that has never signed in — so
    /// the ordinary empty states stay plain text with nothing to click.
    var emptyAction: (() -> Void)?
    @ViewBuilder var rows: () -> Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SectionLabel(title: Text(title))

                Spacer(minLength: 8)

                if let summary {
                    summary
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)

            if let series, series.isWorthDrawing {
                MetricSparkline(
                    points: series.points,
                    color: series.kind.color,
                    fixedScale: series.kind.fixedScale
                )
                .frame(height: 40)
                .padding(.bottom, 10)
            }

            if let emptyMessage {
                if let emptyAction {
                    Button(action: emptyAction) {
                        Text(emptyMessage)
                            .font(.caption)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.link)
                    .accessibilityHint(Text("Sign in to DSM"))
                } else {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else {
                // Scrolls, because the window is sized to its content and
                // cannot grow past it: a machine with more volumes, drives, or
                // agent sessions than fit was simply losing the ones at the
                // bottom, with nothing on screen to say so.
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        rows()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // So the last row can be scrolled clear of the metric tabs
                    // below. Without it the list ends flush against their rule
                    // and the final row is cut mid-height with nowhere further
                    // to go, which reads as clipped rather than as scrollable.
                    .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.automatic)
            }
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
    /// The leading mark's size.
    ///
    /// Defaults to what the AI panel leads its rows with, so a process on the
    /// CPU page and a session on the AI page are the same object at the same
    /// weight rather than two sizes of the same idea.
    var leadingIconSize: CGFloat?
    private var iconSize: CGFloat { leadingIconSize ?? HerdIconSize.row }
    /// Draws the provider's own icon instead of a symbol or a bundle icon.
    var provider: AgentTaskProvider?
    let title: Text
    var subtitle: Text?
    var value: Text?
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 7) {
            if let provider {
                Image(nsImage: AgentProviderIcons.icon(for: provider))
                    .resizable()
                    .scaledToFit()
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.22))
                    .accessibilityLabel(Text(provider.displayName))
            } else {
                ApplicationIcon(
                    bundlePath: bundlePath,
                    fallbackSymbol: symbolName,
                    tint: tint,
                    size: iconSize
                )
            }

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
        leadingIconSize: CGFloat? = nil,
        provider: AgentTaskProvider? = nil,
        title: Text,
        subtitle: Text? = nil,
        value: Text? = nil
    ) {
        self.init(
            symbolName: symbolName,
            tint: tint,
            bundlePath: bundlePath,
            leadingIconSize: leadingIconSize,
            provider: provider,
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
    /// Resolves an app by bundle identifier, preferring one that can actually
    /// draw itself.
    ///
    /// `com.anthropic.claude-code` resolves to a helper bundle inside Claude
    /// Code's application-support directory — no `.icns`, no `CFBundleIconFile`,
    /// nothing to draw — so agent rows rendered an empty square while the
    /// lookup was working perfectly. Later identifiers name the real
    /// applications, so a bundle with no icon is passed over rather than
    /// accepted just for matching first.
    static func bundlePath(forAnyOf identifiers: [String]) -> String? {
        var firstResolved: String?

        for identifier in identifiers {
            let path: String?
            if let cached = pathsByBundleIdentifier[identifier] {
                path = cached
            } else {
                path = NSWorkspace.shared
                    .urlForApplication(withBundleIdentifier: identifier)?
                    .path
                pathsByBundleIdentifier[identifier] = path
            }

            guard let path else { continue }
            if firstResolved == nil { firstResolved = path }
            if hasDrawableIcon(atBundlePath: path) { return path }
        }

        // Nothing had an icon: keep the first match so the row at least points
        // at the right application.
        return firstResolved
    }

    /// Deliberately only the bundle's own `.icns`.
    ///
    /// Asking NSWorkspace would answer yes for the icon-less helper too — it
    /// hands back the generic application placeholder, which is a real image
    /// with real representations, and is exactly the empty-looking square this
    /// is trying to avoid.
    private static func hasDrawableIcon(atBundlePath path: String) -> Bool {
        iconFromBundle(atPath: path) != nil
    }

    static func icon(atBundlePath path: String) -> NSImage? {
        if let cached = icons[path], cached != nil { return cached }
        guard FileManager.default.fileExists(atPath: path) else {
            icons[path] = NSImage?.none
            return nil
        }

        // The bundle's own .icns first. `NSWorkspace.icon(forFile:)` resolves
        // these apps correctly from a standalone process — verified, 32
        // representations each — and appears to hand back a generic placeholder
        // inside this one.
        //
        // NOTE: agent rows still render as empty squares with this in place, so
        // the cause is not yet understood and this is not the fix. Reading the
        // bundle is still the better first attempt, and the workspace call
        // remains as a fallback.
        let icon = iconFromBundle(atPath: path)
            ?? nonEmptyWorkspaceIcon(atPath: path)
        icons[path] = icon
        return icon
    }

    private static func nonEmptyWorkspaceIcon(atPath path: String) -> NSImage? {
        let icon = NSWorkspace.shared.icon(forFile: path)
        return icon.representations.isEmpty ? nil : icon
    }

    private static func iconFromBundle(atPath path: String) -> NSImage? {
        let resources = URL(fileURLWithPath: path)
            .appendingPathComponent("Contents/Resources")

        // `CFBundleIconFile` may omit the extension, and apps shipping their
        // icon in an asset catalog name it something else entirely — so fall
        // back to whatever .icns the bundle actually contains.
        var candidates: [String] = []
        if let declared = Bundle(path: path)?
            .object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
            candidates.append(
                declared.hasSuffix(".icns") ? declared : declared + ".icns"
            )
        }
        candidates += (try? FileManager.default.contentsOfDirectory(
            atPath: resources.path
        ))?.filter { $0.hasSuffix(".icns") } ?? []

        for name in candidates {
            let url = resources.appendingPathComponent(name)
            if let image = NSImage(contentsOf: url),
               !image.representations.isEmpty {
                return image
            }
        }
        return nil
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
                // Scaled with the slot rather than fixed at ten points. Only
                // the frame used to grow, so making the rows' icons match the
                // AI panel's left every symbol the same size in a bigger gap
                // — and an application that resolves to a real icon filled it
                // while one falling back to a symbol did not, which read as
                // two different row designs in one list.
                .font(.system(size: size * 0.68, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
