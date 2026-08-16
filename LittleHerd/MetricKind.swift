import SwiftUI

nonisolated enum MetricKind: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case gpu
    case memory
    case network
    case disk

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .network: "Network"
        case .disk: "Disk"
        }
    }

    var symbolName: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.3.layers.3d"
        case .memory: "memorychip"
        case .network: "arrow.up.arrow.down"
        case .disk: "internaldrive"
        }
    }

    var color: Color {
        switch self {
        case .cpu: .cyan
        case .gpu: .purple
        case .memory: .orange
        case .network: .blue
        case .disk: .green
        }
    }

    var fixedScale: ClosedRange<Double>? {
        switch self {
        case .cpu, .gpu, .memory, .disk:
            0 ... 100
        case .network:
            nil
        }
    }
}

extension DriveHealth {
    /// A healthy drive reads as an ordinary disk row. Only trouble takes on a
    /// colour, so a glance at the pane finds the bad drive rather than a wall of
    /// green.
    var tint: Color {
        switch self {
        case .normal: MetricKind.disk.color
        case .warning: .orange
        case .critical: .red
        case .unknown: .secondary
        }
    }
}
