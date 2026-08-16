import AppKit
import SwiftUI

struct TaskTransferView: View {
    let event: TaskTransferEvent
    let machines: [MachineMonitorModel]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasEntered = false
    @State private var arrivalPulse = false

    var body: some View {
        VStack(spacing: 0) {
            TaskTransferHeader(event: event)

            TransferStage(
                event: event,
                machines: machines,
                hasEntered: hasEntered,
                arrivalPulse: arrivalPulse
            )
        }
        .frame(width: 300, height: 250)
        .background(LittleHerdTheme.background)
        .onAppear {
            guard !reduceMotion else {
                hasEntered = true
                arrivalPulse = true
                return
            }

            withAnimation(.spring(response: 0.54, dampingFraction: 0.82)) {
                hasEntered = true
            }
            withAnimation(
                .easeInOut(duration: 0.75)
                    .delay(0.38)
                    .repeatCount(2, autoreverses: true)
            ) {
                arrivalPulse = true
            }
        }
        .onChange(of: event.status) { _, status in
            if status == .arrived {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    arrivalPulse = true
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(event.title), handing off from \(event.source.displayName) to \(event.destination.displayName)"
        )
    }
}

private struct TaskTransferHeader: View {
    let event: TaskTransferEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: headerSymbol)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(headerColor)

            VStack(alignment: .leading, spacing: 1) {
                Text(headerTitle)
                    .font(.headline.weight(.bold))
                    .tracking(0.45)

                Text("\(event.source.shortName)  →  \(event.destination.shortName)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 68)
        .padding(.horizontal, 16)
    }

    private var headerTitle: LocalizedStringResource {
        switch event.status {
        case .handingOff: "HANDING OFF"
        case .arrived: "HANDOFF COMPLETE"
        case .failed: "HANDOFF FAILED"
        }
    }

    private var headerSymbol: String {
        event.status == .failed ? "exclamationmark.triangle" : "cpu"
    }

    private var headerColor: Color {
        event.status == .failed ? .red : .secondary
    }
}

private struct TransferStage: View {
    let event: TaskTransferEvent
    let machines: [MachineMonitorModel]
    let hasEntered: Bool
    let arrivalPulse: Bool

    var body: some View {
        GeometryReader { geometry in
            let sourcePoint = point(for: event.source, in: geometry.size)
            let destinationPoint = point(for: event.destination, in: geometry.size)
            let capsulePoint = capsulePoint(
                source: sourcePoint,
                destination: destinationPoint
            )

            ZStack {
                transferPath(
                    source: sourcePoint,
                    destination: destinationPoint,
                    capsule: capsulePoint
                )

                machineColumns

                destinationBeam(
                    at: destinationPoint,
                    capsule: capsulePoint
                )

                destinationHalo(at: destinationPoint)

                TransferTaskCapsule(event: event)
                    .frame(width: 208, height: 54)
                    .position(
                        x: hasEntered ? capsulePoint.x : sourcePoint.x,
                        y: hasEntered ? capsulePoint.y : sourcePoint.y - 18
                    )
                    .scaleEffect(hasEntered ? 1 : 0.58)
                    .opacity(event.status == .failed ? 0.62 : 1)
                    .shadow(
                        color: event.status == .failed
                            ? .red.opacity(0.20)
                            : .purple.opacity(0.28),
                        radius: 14,
                        y: 8
                    )
            }
        }
        .frame(height: 182)
        .clipped()
    }

    private var machineColumns: some View {
        HStack(alignment: .bottom, spacing: columnSpacing) {
            ForEach(machines) { machine in
                TransferMachineColumn(
                    machine: machine,
                    isSource: machine.machine == event.source,
                    isDestination: machine.machine == event.destination,
                    hasEntered: hasEntered,
                    columnWidth: columnWidth,
                    avatarSize: avatarSize
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var columnSpacing: CGFloat { machines.count <= 3 ? 10 : 4 }
    private var columnWidth: CGFloat {
        let count = CGFloat(max(machines.count, 1))
        let available = 268
            - columnSpacing * CGFloat(max(machines.count - 1, 0))
        return min(68, max(38, available / count))
    }
    private var avatarSize: CGFloat { machines.count <= 4 ? 28 : 23 }

    @ViewBuilder
    private func transferPath(
        source: CGPoint,
        destination: CGPoint,
        capsule: CGPoint
    ) -> some View {
        TransferArc(
            start: CGPoint(x: source.x, y: source.y - 30),
            end: CGPoint(x: destination.x, y: destination.y - 47),
            lift: min(capsule.y + 14, 62)
        )
        .trim(from: 0, to: hasEntered ? 1 : 0)
        .stroke(
            LinearGradient(
                colors: [
                    .green.opacity(0.18),
                    .purple.opacity(0.76),
                    .cyan.opacity(0.58),
                ],
                startPoint: .leading,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
        )
        .shadow(color: .purple.opacity(0.35), radius: 7)
        .animation(.easeOut(duration: 0.62), value: hasEntered)
    }

    @ViewBuilder
    private func destinationBeam(
        at point: CGPoint,
        capsule: CGPoint
    ) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0.84),
                        .cyan.opacity(0.30),
                        .clear,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 24, height: 46)
            .blur(radius: 3)
            .opacity(hasEntered ? 1 : 0)
            .position(
                x: point.x,
                y: (capsule.y + point.y - 54) / 2
            )
            .animation(.easeOut(duration: 0.48).delay(0.22), value: hasEntered)
    }

    @ViewBuilder
    private func destinationHalo(at point: CGPoint) -> some View {
        ZStack {
            ForEach(0 ..< 3, id: \.self) { ring in
                Ellipse()
                    .stroke(
                        Color.cyan.opacity(0.30 - Double(ring) * 0.07),
                        lineWidth: 1.2
                    )
                    .frame(
                        width: CGFloat(42 + ring * 20),
                        height: CGFloat(16 + ring * 8)
                    )
            }
        }
        .scaleEffect(arrivalPulse ? 1.08 : 0.78)
        .opacity(hasEntered ? 1 : 0)
        .position(x: point.x, y: point.y - 54)
    }

    private func point(for machine: MachineID, in size: CGSize) -> CGPoint {
        let machineIDs = machines.map(\.machine)
        let index = machineIDs.firstIndex(of: machine) ?? 0
        let count = CGFloat(max(machineIDs.count, 1))
        let columnCenter = 16 + (size.width - 32) / count
            * (CGFloat(index) + 0.5)
        return CGPoint(x: columnCenter, y: size.height - 24)
    }

    private func capsulePoint(source: CGPoint, destination: CGPoint) -> CGPoint {
        let direction: CGFloat = destination.x >= source.x ? 1 : -1
        let midpoint = (source.x + destination.x) / 2
        let adjustedX = midpoint + direction * 22
        return CGPoint(x: min(max(adjustedX, 100), 200), y: 42)
    }
}

private struct TransferMachineColumn: View {
    let machine: MachineMonitorModel
    let isSource: Bool
    let isDestination: Bool
    let hasEntered: Bool
    let columnWidth: CGFloat
    let avatarSize: CGFloat

    var body: some View {
        VStack(spacing: 5) {
            CompactTransferThermometer(value: liveCPUValue)

            MachineAvatarView(avatar: machine.avatar, size: avatarSize)

            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)

                Text(machine.shortName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
        .frame(width: columnWidth)
        .opacity(columnOpacity)
        .scaleEffect(
            isDestination && hasEntered ? 1.04 : (isSource && hasEntered ? 0.92 : 1),
            anchor: .bottom
        )
        .animation(.easeOut(duration: 0.55), value: hasEntered)
    }

    private var liveCPUValue: Double? {
        machine.state == .live ? machine.cpu.value : nil
    }

    private var columnOpacity: Double {
        guard hasEntered else { return 1 }
        if isDestination { return 1 }
        if isSource { return 0.38 }
        return 0.62
    }

    private var statusColor: Color {
        switch machine.state {
        case .connecting: .orange
        case .live: .green
        case .offline: .red
        case .stopped: .secondary
        }
    }
}

private struct CompactTransferThermometer: View {
    let value: Double?

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0 ..< 10, id: \.self) { position in
                let level = 9 - position
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(
                        level < filledBlockCount
                            ? ThermometerScale.band(forLevel: level).color
                            : LittleHerdTheme.emptyBlock
                    )
                    .frame(width: 30, height: 8)
            }
        }
    }

    private var filledBlockCount: Int {
        ThermometerScale.filledBlockCount(for: value)
    }
}

private struct TransferTaskCapsule: View {
    let event: TaskTransferEvent

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(0.10))
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(.white.opacity(0.72), lineWidth: 1.2)

                Image(nsImage: TransferProviderIcons.icon(for: event.provider))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(
                    "\(event.cpuCores, format: .number.precision(.fractionLength(1 ... 2))) core"
                )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.78))
            }

            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.63, green: 0.32, blue: 0.98),
                            Color(red: 0.28, green: 0.31, blue: 0.96),
                            Color(red: 0.26, green: 0.69, blue: 0.96),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.72), lineWidth: 1)
                }
        }
    }
}

private struct TransferArc: Shape {
    let start: CGPoint
    let end: CGPoint
    let lift: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        let control = CGPoint(
            x: (start.x + end.x) / 2,
            y: lift
        )
        path.addQuadCurve(to: end, control: control)
        return path
    }
}

@MainActor
private enum TransferProviderIcons {
    static let codex = appIcon(
        bundleIdentifier: "com.openai.codex",
        fallbackSymbolName: "sparkles"
    )
    static let claude = appIcon(
        bundleIdentifier: "com.anthropic.claudefordesktop",
        fallbackSymbolName: "brain.head.profile"
    )

    static func icon(for provider: AgentTaskProvider) -> NSImage {
        switch provider {
        case .codex: codex
        case .claude: claude
        }
    }

    private static func appIcon(
        bundleIdentifier: String,
        fallbackSymbolName: String
    ) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        return NSImage(
            systemSymbolName: fallbackSymbolName,
            accessibilityDescription: nil
        ) ?? NSImage()
    }
}
