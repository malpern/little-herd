import SwiftUI

/// The four ways of looking at the herd — the Mac dashboard's bottom tabs.
///
/// **The same four, in the same order, with the same names.** The phone is the
/// Mac's dashboard held in a hand, not a second design, so a person who knows
/// one already knows where everything is on the other. `OverviewMetric` lives
/// in the Mac target alongside the models it lenses; this is its twin for a
/// reader that only has `HerdWire`.
enum HerdLens: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case disk
    case ai

    var id: Self { self }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .disk: "Disk"
        case .ai: "AI"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .ai: "sparkles"
        }
    }

    /// What the thermometer for this lens fills to, 0–100. Memory is the share
    /// of RAM in use; the verdict that matters more is `pressureWord`.
    func value(for machine: HerdWire.Machine) -> Double? {
        guard machine.state == "live" else { return nil }
        switch self {
        case .cpu: return machine.cpuPercent
        case .memory:
            guard let used = machine.memoryUsedBytes,
                  let total = machine.memoryTotalBytes, total > 0
            else { return nil }
            return used / total * 100
        case .disk: return machine.diskUsedPercent
        case .ai: return nil
        }
    }

    /// Memory's percentage is not its signal: a Mac can be calm at 70% and
    /// swapping at 60%. So once pressure leaves normal the figure gives way to
    /// the verdict, as it does in the Mac's column.
    static func pressureWord(for machine: HerdWire.Machine) -> String? {
        switch machine.memoryPressure {
        case "critical": "Critical"
        case "warning": "Warning"
        default: nil
        }
    }

    /// Whether this lens has a machine worth looking at, and how badly — the
    /// mark on its tab. Agrees with what the thermometer paints: only a bar in
    /// its red band raises one, never a merely orange disk.
    ///
    /// AI is the one addition the Mac does not make: a session waiting on you
    /// is the reason the phone exists, so its tab says so.
    func alarm(in snapshot: HerdWire.Snapshot) -> ThermometerBand? {
        switch self {
        case .ai:
            let sessions = snapshot.machines.flatMap(\.sessions)
            let waiting = sessions.contains { $0.needsYou }
            return waiting ? .high : nil
        case .memory:
            let pressure = snapshot.machines.compactMap { machine -> ThermometerBand? in
                guard machine.state == "live" else { return nil }
                switch machine.memoryPressure {
                case "critical": return .critical
                case "warning": return .high
                default: return nil
                }
            }.max()
            return pressure ?? barAlarm(in: snapshot)
        default:
            return barAlarm(in: snapshot)
        }
    }

    private func barAlarm(in snapshot: HerdWire.Snapshot) -> ThermometerBand? {
        snapshot.machines.contains { machine in
            let filled = ThermometerBand.filledBlocks(for: value(for: machine))
            return filled > 0 && ThermometerBand.forLevel(filled - 1) == .critical
        } ? .critical : nil
    }
}

extension HerdWire.Session {
    /// Holding for a person: waiting wants a message, stalled wants a look.
    var needsYou: Bool { state == "waiting" || state == "stalled" }
}

/// The brand palette, read from the same color sets the Mac draws with.
enum HerdTheme {
    static let background = Color("HerdBackground")
    static let forest = Color("HerdForest")
    static let loadGreen = Color("HerdLoadGreen")
    static let loadTeal = Color("HerdLoadTeal")
    static let emptyBlock = Color("HerdEmptyBlock")
}

/// The Mac's thermometer bands: ten blocks, green to red.
enum ThermometerBand: Comparable {
    case calm
    case moderate
    case high
    case critical

    static let blockCount = 10

    /// Any reading at all lights the first block, so a machine barely working
    /// still looks different from one that is not answering.
    static func filledBlocks(for value: Double?) -> Int {
        guard let value else { return 0 }
        return min(max(Int(ceil(value / 10)), 0), blockCount)
    }

    static func forLevel(_ level: Int) -> ThermometerBand {
        switch level {
        case ...3: .calm
        case 4 ... 6: .moderate
        case 7 ... 8: .high
        default: .critical
        }
    }

    var color: Color {
        switch self {
        case .calm: HerdTheme.loadGreen
        case .moderate: .yellow
        case .high: .orange
        case .critical: .red
        }
    }
}

/// Ten stacked blocks, lit from the bottom — the Mac's segmented thermometer.
struct SegmentedThermometer: View {
    let value: Double?
    var blockWidth: CGFloat = 44
    var blockHeight: CGFloat = 9
    var spacing: CGFloat = 3

    var body: some View {
        let filled = ThermometerBand.filledBlocks(for: value)
        VStack(spacing: spacing) {
            ForEach((0 ..< ThermometerBand.blockCount).reversed(), id: \.self) { level in
                RoundedRectangle(cornerRadius: blockHeight * 0.3, style: .continuous)
                    .fill(level < filled
                        ? ThermometerBand.forLevel(level).color
                        : HerdTheme.emptyBlock)
                    .frame(width: blockWidth, height: blockHeight)
            }
        }
        .animation(.smooth(duration: 0.3), value: filled)
        .accessibilityHidden(true)
    }
}

/// The row of lenses along the bottom — the Mac's `OverviewMetricTabs`.
///
/// Four words, all visible, the current one a place rather than a value in a
/// control. It stays under every screen, and pressing it re-lenses whatever
/// is showing instead of throwing you back to the herd, exactly as on the Mac.
struct HerdLensTabs: View {
    let selection: HerdLens
    var alarms: [HerdLens: ThermometerBand] = [:]
    let onSelect: (HerdLens) -> Void

    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HerdLens.allCases) { lens in
                tab(lens)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.09))
                .frame(height: 1)
        }
        .background(HerdTheme.background.opacity(0.94))
        .background(.bar)
    }

    private func tab(_ lens: HerdLens) -> some View {
        let isSelected = lens == selection
        return Button {
            onSelect(lens)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: lens.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 22)
                    .overlay(alignment: .topTrailing) {
                        if let band = alarms[lens] {
                            Circle()
                                .fill(band.color)
                                .frame(width: 7, height: 7)
                                .offset(x: 6, y: -1)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                Text(lens.title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isSelected ? HerdTheme.forest : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(HerdTheme.loadTeal.opacity(0.14))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.22), value: selection)
        .animation(.smooth(duration: 0.25), value: alarms)
        .accessibilityLabel(label(for: lens))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func label(for lens: HerdLens) -> String {
        switch alarms[lens] {
        case .critical: "\(lens.title), critical"
        case .some: "\(lens.title), needs a look"
        case nil: lens.title
        }
    }
}
