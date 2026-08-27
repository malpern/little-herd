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
    /// The metrics with a machine worth looking at, and how badly.
    var alarms: [OverviewMetric: MetricAlarm.Severity] = [:]
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

    /// Said in the label rather than as a hint: a hint is offered once, and
    /// this is the reason to press the tab at all. The levels are named,
    /// because a colour is not a thing VoiceOver can read.
    private func label(for metric: OverviewMetric) -> Text {
        let name = String(localized: metric.title)
        switch alarms[metric] {
        case .critical: return Text("\(name), critical")
        case .warning: return Text("\(name), warning")
        case nil: return Text(name)
        }
    }

    private func tab(_ metric: OverviewMetric) -> some View {
        let isSelected = metric == selection
        return Button {
            onSelect(metric)
        } label: {
            HStack(spacing: 4) {
                Text(metric.title)
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(0.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(
                        isSelected ? LittleHerdTheme.forest : Color.secondary
                    )

                // Beside the word rather than over the corner of the pill: a
                // tab is already a small target, and a mark that overlaps its
                // edge reads as damage to the control rather than as news
                // about what is behind it.
                if let severity = alarms[metric] {
                    Circle()
                        .fill(severity.tint)
                        .frame(width: 5, height: 5)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: HerdRadius.control, style: .continuous)
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
        .animation(.smooth(duration: 0.25), value: alarms)
        .accessibilityLabel(label(for: metric))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
