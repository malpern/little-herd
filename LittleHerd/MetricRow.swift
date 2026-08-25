import Charts
import SwiftUI

struct MetricRow: View {
    let metric: MetricModel
    let isSupported: Bool
    let memoryPressure: MemoryPressureLevel?
    var memoryExplanation: String?

    var body: some View {
        HStack(spacing: 8) {
            MetricSymbol(kind: metric.kind, isSupported: isSupported)

            VStack(alignment: .leading, spacing: 1) {
                Text(metric.kind.title)
                    .font(.subheadline.weight(.medium))
                MetricDetail(
                    kind: metric.kind,
                    auxiliaryValue: metric.auxiliaryValue,
                    capacity: metric.capacity,
                    isSupported: isSupported
                )
            }
            .frame(width: 96, alignment: .leading)

            MetricSparkline(
                points: metric.history,
                color: isSupported ? metric.kind.color : Color.gray.opacity(0.35),
                fixedScale: metric.kind.fixedScale
            )
            .frame(minWidth: 48, maxWidth: .infinity, minHeight: 26, maxHeight: 26)

            MetricValue(
                kind: metric.kind,
                value: metric.value,
                memoryPressure: memoryPressure,
                memoryExplanation: memoryExplanation
            )
                .frame(width: 64, alignment: .trailing)
        }
        .frame(height: 48)
        .accessibilityElement(children: .combine)
    }
}

private struct MetricSymbol: View {
    let kind: MetricKind
    let isSupported: Bool

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(kind.color.opacity(isSupported ? 1 : 0.35))
            .frame(width: 27, height: 27)
            .background(
                kind.color.opacity(isSupported ? 0.12 : 0.05),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .accessibilityHidden(true)
    }
}

private struct MetricValue: View {
    let kind: MetricKind
    let value: Double?
    let memoryPressure: MemoryPressureLevel?
    var memoryExplanation: String?

    var body: some View {
        VStack(alignment: .trailing) {
            switch MetricValueDisplay.resolve(
                kind: kind,
                value: value,
                memoryPressure: memoryPressure
            ) {
            case .pressure(let level):
                MemoryPressureSymbol(level: level, explanation: memoryExplanation)
            case .percent(let percent):
                Text(percent / 100, format: .percent.precision(.fractionLength(0)))
            case .bytesPerSecond(let rate):
                let formatted = Int64(rate).formatted(
                    .byteCount(style: .file, allowedUnits: .all, spellsOutZero: false)
                )
                Text("\(formatted)/s")
                    .help("Combined upload and download per second")
            case .unavailable:
                Text("—")
                    .foregroundStyle(.tertiary)
            }
        }
    }

}

extension MemoryPressureLevel {
    /// Shared with the hovered header, which says the verdict in words beside
    /// the symbol and has to agree with it.
    var tint: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }
}

struct MemoryPressureSymbol: View {
    let level: MemoryPressureLevel?
    /// What to say on hover, from `MemoryPressureExplanation`.
    ///
    /// It has to arrive here rather than being set on whatever contains the
    /// symbol: the innermost `.help` owns its own region, so a symbol holding
    /// terse help of its own silently overrides the fuller text a parent
    /// supplies — which is what it did, for as long as both existed.
    var explanation: String?

    var body: some View {
        if let level {
            let hover = explanation ?? String(localized: level.title)
            Image(systemName: symbolName(for: level))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(level.tint)
                .contentTransition(.symbolEffect(.replace))
                .help(Text(hover))
                // The label stays the verdict alone. VoiceOver reads a label
                // every time focus lands on the symbol, and three sentences
                // there would be read on every pass; a hint is offered once.
                .accessibilityLabel(Text(level.title))
                .accessibilityHint(Text(hover))
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Memory pressure unavailable")
        }
    }

    private func symbolName(for level: MemoryPressureLevel) -> String {
        switch level {
        case .normal: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }


}

private struct MetricDetail: View {
    let kind: MetricKind
    let auxiliaryValue: Double?
    let capacity: Double?
    let isSupported: Bool

    var body: some View {
        Group {
            if !isSupported {
                Text("Local only")
            } else {
                switch kind {
                case .cpu:
                    Text("All cores")
                case .gpu:
                    Text("Device activity")
                case .memory:
                    if let auxiliaryValue, let capacity {
                        Text(
                            "\(Int64(auxiliaryValue), format: .byteCount(style: .memory)) of \(Int64(capacity), format: .byteCount(style: .memory))"
                        )
                    } else {
                        Text("Physical memory")
                    }
                case .network:
                    if let auxiliaryValue, let capacity {
                        Text(
                            "↓ \(Int64(auxiliaryValue), format: .byteCount(style: .file))  ↑ \(Int64(capacity), format: .byteCount(style: .file))"
                        )
                    } else {
                        Text("Physical interfaces")
                    }
                case .disk:
                    if let auxiliaryValue {
                        Text("\(Int64(auxiliaryValue), format: .byteCount(style: .file)) free")
                    } else {
                        Text("Startup disk")
                    }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
}

/// The shape a metric has been making lately.
///
/// Shared rather than private: the metric rows draw it small beside each row,
/// and a focused machine's pane draws the same series larger above its list, so
/// that "what is it doing" and "what has it been doing" are answered by one
/// picture rather than two that could disagree.
struct MetricSparkline: View {
    let points: [HistoryPoint]
    let color: Color
    let fixedScale: ClosedRange<Double>?

    var body: some View {
        if points.count > 1 {
            Chart(points) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.22), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Usage", point.value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .chartYScale(domain: chartDomain)
            .accessibilityHidden(true)
        } else {
            Capsule()
                .fill(color.opacity(0.10))
                .frame(height: 2)
                .accessibilityHidden(true)
        }
    }

    private var chartDomain: ClosedRange<Double> {
        if let fixedScale {
            return fixedScale
        }

        let maximum = max(points.map(\.value).max() ?? 1, 1)
        return 0 ... maximum * 1.12
    }
}
