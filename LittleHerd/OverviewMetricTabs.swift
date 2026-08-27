import SwiftUI

/// The row of metrics along the bottom of the dashboard.
///
/// It replaces a pull-down in the header, and the reason is that a pull-down
/// hides three of its four choices behind a click and a menu that covers the
/// thing you are reading. Four tabs are four words, all of them visible, and
/// the one you are on is a place rather than a value in a control. The design
/// is the site's own miniature of this window, which arrived at the same shape
/// while nobody was defending the pull-down.
struct OverviewMetricTabs: View {
    let selection: OverviewMetric
    let onSelect: (OverviewMetric) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(OverviewMetric.allCases) { metric in
                tab(metric)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(alignment: .top) {
            // A rule rather than a filled bar: the tabs sit on the window's
            // own ground, so a second surface underneath them would be a
            // second colour doing no work.
            Rectangle()
                .fill(Color.primary.opacity(0.09))
                .frame(height: 1)
        }
    }

    private func tab(_ metric: OverviewMetric) -> some View {
        let isSelected = metric == selection
        return Button {
            onSelect(metric)
        } label: {
            Text(metric.title)
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.1)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(
                    isSelected ? LittleHerdTheme.forest : Color.secondary
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LittleHerdTheme.loadTeal.opacity(0.14))
                            // The pill travels between tabs rather than
                            // appearing where it lands, so a glance that
                            // misses the change still sees which way it went.
                            .matchedGeometryEffect(id: "pill", in: pill)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .animation(
            reduceMotion ? nil : .snappy(duration: 0.22),
            value: selection
        )
        .accessibilityLabel(Text(metric.title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
