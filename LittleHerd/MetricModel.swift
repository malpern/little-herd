import Foundation
import Observation

nonisolated struct HistoryPoint: Identifiable, Equatable, Sendable {
    let timestamp: Date
    let value: Double

    var id: Date { timestamp }
}

@MainActor
@Observable
final class MetricModel: Identifiable {
    let kind: MetricKind
    private(set) var value: Double?
    private(set) var auxiliaryValue: Double?
    private(set) var capacity: Double?
    private(set) var history: [HistoryPoint] = []

    var id: MetricKind { kind }

    init(kind: MetricKind) {
        self.kind = kind
    }

    func update(with reading: MetricReading, at timestamp: Date) {
        value = reading.value
        auxiliaryValue = reading.auxiliaryValue
        capacity = reading.capacity

        guard let value = reading.value else { return }
        history.append(HistoryPoint(timestamp: timestamp, value: value))
        if history.count > 60 {
            history.removeFirst(history.count - 60)
        }
    }
}
