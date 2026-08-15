import Foundation
import Observation
import SQLite3

nonisolated enum AIUsageProvider: Equatable, Sendable {
    case codex
    case claude

    var displayName: LocalizedStringResource {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    var usageAndBillingURL: URL {
        switch self {
        case .codex:
            URL(string: "https://chatgpt.com/codex/settings/usage")!
        case .claude:
            URL(string: "https://claude.ai/settings/usage")!
        }
    }
}

nonisolated enum AIUsageBudgetStatus: Equatable, Sendable {
    case normal
    case warning
    case critical
    case urgent

    static func status(for remainingPercent: Double) -> AIUsageBudgetStatus {
        switch remainingPercent {
        case ...1: .urgent
        case ...10: .critical
        case ...25: .warning
        default: .normal
        }
    }
}

nonisolated struct AIUsageLimit: Equatable, Sendable {
    let provider: AIUsageProvider
    let remainingPercent: Double
    let windowMinutes: Int
    let resetsAt: Date?
    let updatedAt: Date

    var budgetStatus: AIUsageBudgetStatus {
        .status(for: remainingPercent)
    }

    var remainingFraction: Double {
        min(max(remainingPercent / 100, 0), 1)
    }

    var windowDescription: LocalizedStringResource {
        switch windowMinutes {
        case ...300: "5-hour session"
        case 301 ..< 10_080: "\(windowMinutes / 60)-hour window"
        default: "weekly limit"
        }
    }
}

@MainActor
@Observable
final class AIUsageLimitsModel {
    private(set) var codex: AIUsageLimit?
    private(set) var claude: AIUsageLimit?

    @ObservationIgnored
    private let sampler = AIUsageLimitsSampler()

    @ObservationIgnored
    private var monitoringTask: Task<Void, Never>?

    func start() {
        guard monitoringTask == nil else { return }

        monitoringTask = Task { [sampler] in
            while !Task.isCancelled {
                let snapshot = await sampler.sample()
                codex = snapshot.codex
                claude = snapshot.claude

                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }
}

nonisolated struct AIUsageLimitsSnapshot: Equatable, Sendable {
    let codex: AIUsageLimit?
    let claude: AIUsageLimit?
}

actor AIUsageLimitsSampler {
    private let freshnessInterval: TimeInterval = 15 * 60

    func sample(now: Date = .now) -> AIUsageLimitsSnapshot {
        let codex = readCodexLimit()
        let claude = readClaudeLimit()

        return AIUsageLimitsSnapshot(
            codex: freshLimit(codex, now: now),
            claude: freshLimit(claude, now: now)
        )
    }

    private func freshLimit(_ limit: AIUsageLimit?, now: Date) -> AIUsageLimit? {
        guard let limit,
              now.timeIntervalSince(limit.updatedAt) <= freshnessInterval
        else {
            return nil
        }
        return limit
    }

    private func readCodexLimit() -> AIUsageLimit? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(
                path: "Library/Application Support/CodexBar/codex-account-snapshots.json"
            )

        guard let data = try? Data(contentsOf: url) else { return nil }
        return AIUsageLimitsParser.codexLimit(from: data)
    }

    private func readClaudeLimit() -> AIUsageLimit? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Caches/CodexBar/Cache.db")

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            return nil
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT d.receiver_data, CAST(strftime('%s', r.time_stamp) AS REAL)
        FROM cfurl_cache_receiver_data AS d
        JOIN cfurl_cache_response AS r USING(entry_ID)
        WHERE r.request_key LIKE '%/usage'
        ORDER BY r.time_stamp DESC
        LIMIT 1
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(statement, 0)
        else {
            return nil
        }

        let byteCount = Int(sqlite3_column_bytes(statement, 0))
        let data = Data(bytes: bytes, count: byteCount)
        let updatedAt = Date(
            timeIntervalSince1970: sqlite3_column_double(statement, 1)
        )
        return AIUsageLimitsParser.claudeLimit(from: data, updatedAt: updatedAt)
    }
}

nonisolated enum AIUsageLimitsParser {
    static func codexLimit(from data: Data) -> AIUsageLimit? {
        guard let cache = try? JSONDecoder().decode(
            CodexAccountSnapshots.self,
            from: data
        ) else {
            return nil
        }

        return cache.records
            .compactMap { record -> AIUsageLimit? in
                guard let window = blockingWindow(
                    record.snapshot.primary,
                    record.snapshot.secondary,
                    record.snapshot.tertiary
                ) else {
                    return nil
                }

                return AIUsageLimit(
                    provider: .codex,
                    remainingPercent: remainingPercent(from: window.usedPercent),
                    windowMinutes: window.windowMinutes,
                    resetsAt: window.resetsAt,
                    updatedAt: record.snapshot.updatedAt
                )
            }
            .max { $0.updatedAt < $1.updatedAt }
    }

    static func claudeLimit(from data: Data, updatedAt: Date) -> AIUsageLimit? {
        guard let cache = try? JSONDecoder().decode(ClaudeUsageCache.self, from: data)
        else {
            return nil
        }

        let windows = [
            cache.fiveHour.map {
                UsageWindow(
                    usedPercent: $0.utilization,
                    windowMinutes: 300,
                    resetsAt: $0.resetsAt
                )
            },
            cache.sevenDay.map {
                UsageWindow(
                    usedPercent: $0.utilization,
                    windowMinutes: 10_080,
                    resetsAt: $0.resetsAt
                )
            },
        ]

        guard let window = blockingWindow(windows.compactMap(\.self)) else {
            return nil
        }

        return AIUsageLimit(
            provider: .claude,
            remainingPercent: remainingPercent(from: window.usedPercent),
            windowMinutes: window.windowMinutes,
            resetsAt: window.resetsAt,
            updatedAt: updatedAt
        )
    }

    private static func blockingWindow(
        _ windows: UsageWindow?...
    ) -> UsageWindow? {
        blockingWindow(windows.compactMap(\.self))
    }

    private static func blockingWindow(
        _ windows: [UsageWindow]
    ) -> UsageWindow? {
        windows.max {
            if $0.usedPercent == $1.usedPercent {
                return $0.windowMinutes > $1.windowMinutes
            }
            return $0.usedPercent < $1.usedPercent
        }
    }

    private static func remainingPercent(from usedPercent: Double) -> Double {
        min(max(100 - usedPercent, 0), 100)
    }

    private struct CodexAccountSnapshots: Decodable {
        let records: [Record]

        struct Record: Decodable {
            let snapshot: Snapshot
        }

        struct Snapshot: Decodable {
            let primary: UsageWindow?
            let secondary: UsageWindow?
            let tertiary: UsageWindow?
            let updatedAt: Date
        }
    }

    private struct ClaudeUsageCache: Decodable {
        let fiveHour: ClaudeWindow?
        let sevenDay: ClaudeWindow?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }

    private struct ClaudeWindow: Decodable {
        let utilization: Double
        let resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            utilization = try container.decode(Double.self, forKey: .utilization)

            if let resetString = try container.decodeIfPresent(
                String.self,
                forKey: .resetsAt
            ) {
                resetsAt = try? Date(resetString, strategy: .iso8601)
            } else {
                resetsAt = nil
            }
        }
    }

    private struct UsageWindow: Decodable {
        let usedPercent: Double
        let windowMinutes: Int
        let resetsAt: Date?
    }
}
