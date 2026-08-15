import Foundation
import Observation

nonisolated enum TaskTransferStatus: String, Codable, Equatable, Sendable {
    case handingOff
    case arrived
    case failed
}

nonisolated struct TaskTransferEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let provider: AgentTaskProvider
    let title: String
    let source: MachineID
    let destination: MachineID
    let cpuCores: Double
    let status: TaskTransferStatus
    let startedAt: Date
    let updatedAt: Date

    var isValid: Bool {
        source != destination
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && cpuCores.isFinite
            && cpuCores >= 0
    }

    func isPresentable(at date: Date) -> Bool {
        guard isValid else { return false }

        switch status {
        case .handingOff:
            return date.timeIntervalSince(updatedAt) < 10 * 60
        case .arrived, .failed:
            return date.timeIntervalSince(updatedAt) < 8
        }
    }
}

nonisolated enum TaskTransferEventParser {
    static func parse(_ data: Data) -> TaskTransferEvent? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let event = try? decoder.decode(TaskTransferEvent.self, from: data),
              event.isValid
        else {
            return nil
        }
        return event
    }
}

actor TaskTransferEventStore {
    private let url: URL
    private var lastModificationDate: Date?
    private var cachedEvent: TaskTransferEvent?

    init(
        url: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".local/state/little-herd/transfer.json")
    ) {
        self.url = url
    }

    func currentEvent(now: Date = .now) -> TaskTransferEvent? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modificationDate = attributes?[.modificationDate] as? Date

        if modificationDate != lastModificationDate {
            lastModificationDate = modificationDate
            cachedEvent = (try? Data(contentsOf: url))
                .flatMap(TaskTransferEventParser.parse)
        }

        guard let cachedEvent, cachedEvent.isPresentable(at: now) else {
            return nil
        }
        return cachedEvent
    }
}

@MainActor
@Observable
final class TaskTransferMonitorModel {
    private(set) var currentEvent: TaskTransferEvent?

    @ObservationIgnored
    private let store = TaskTransferEventStore()

    @ObservationIgnored
    private var monitoringTask: Task<Void, Never>?

    func start() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [store] in
            while !Task.isCancelled {
                currentEvent = await store.currentEvent()

                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
        currentEvent = nil
    }
}
