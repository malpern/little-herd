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

/// Why a provider's usage figure is missing, in terms a person can act on.
///
/// A missing limit is true but useless. Usage that was never available because
/// the app supplying it is not installed, usage that stopped updating because
/// that app is no longer running, and a provider that reports nothing all look
/// identical as `nil` — and the first is what every new installation sees,
/// where naming a tool the user has never heard of as having *failed* is the
/// wrong sentence entirely.
///
/// Little Herd does not read usage from the providers: neither CLI exposes a
/// limit and neither writes one to disk, so the figures come from CodexBar's
/// files. That is a scrape of another app rather than an interface, so being
/// unable to read it is an ordinary state rather than an error.
nonisolated enum AIUsageAvailability: Equatable, Sendable {
    /// A reading recent enough to show.
    case available(AIUsageLimit)
    /// Nothing supplies usage on this Mac; CodexBar is not installed.
    case sourceMissing
    /// The reading exists but has stopped being updated — CodexBar is installed
    /// and not running, or is signed out. Carries when it was last current, so
    /// the interface can say how long ago rather than merely "old".
    case stale(since: Date)
    /// The source is present and current but says nothing about this provider.
    case noReading

    /// The reading when there is one, for the places that only need the number.
    var limit: AIUsageLimit? {
        guard case let .available(limit) = self else { return nil }
        return limit
    }

    /// Decides which of the four a reading is, kept separate from the file
    /// system so it can be tested without one.
    static func resolve(
        limit: AIUsageLimit?,
        sourceInstalled: Bool,
        now: Date,
        freshnessInterval: TimeInterval
    ) -> AIUsageAvailability {
        guard sourceInstalled else { return .sourceMissing }
        guard let limit else { return .noReading }
        guard now.timeIntervalSince(limit.updatedAt) <= freshnessInterval else {
            return .stale(since: limit.updatedAt)
        }
        return .available(limit)
    }
}

@MainActor
@Observable
final class AIUsageLimitsModel {
    private(set) var codex: AIUsageAvailability = .noReading
    private(set) var claude: AIUsageAvailability = .noReading

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
    let codex: AIUsageAvailability
    let claude: AIUsageAvailability
}

actor AIUsageLimitsSampler {
    private let freshnessInterval: TimeInterval = 15 * 60

    func sample(now: Date = .now) -> AIUsageLimitsSnapshot {
        let installed = isSourceInstalled

        return AIUsageLimitsSnapshot(
            codex: availability(readCodexLimit(), installed: installed, now: now),
            claude: availability(readClaudeLimit(), installed: installed, now: now)
        )
    }

    private func availability(
        _ limit: AIUsageLimit?,
        installed: Bool,
        now: Date
    ) -> AIUsageAvailability {
        AIUsageAvailability.resolve(
            limit: limit,
            sourceInstalled: installed,
            now: now,
            freshnessInterval: freshnessInterval
        )
    }

    /// Whether anything on this Mac supplies usage at all.
    ///
    /// Detected from CodexBar's own directories rather than by looking up the
    /// application, which keeps this file free of AppKit and does not care
    /// where the app was installed. Either directory is enough: the two
    /// providers are read from different ones.
    private var isSourceInstalled: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            "Library/Application Support/CodexBar",
            "Library/Caches/CodexBar",
        ].contains { relative in
            FileManager.default.fileExists(
                atPath: home.appending(path: relative).path
            )
        }
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
