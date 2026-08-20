import Foundation

/// Codex's own account limits, read out of the files it already writes.
///
/// Every rollout carries the rate limits the API returned, per turn, in the
/// same `token_count` entry that records the context size:
///
///     "primary":{"used_percent":100.0,"window_minutes":10080,
///                "resets_at":1786388138}
///
/// That is the figure CodexBar exists to supply, first-party and on disk —
/// found populated in 216 rollouts on this Mac. Reading it here removes the
/// app's most fragile dependency for one of its two providers: CodexBar is
/// another developer's application, it scrapes an `NSURLCache`, and it has to
/// be *running* — the day it was not, this Mac showed no Codex limit at all
/// while the weekly window sat at 100% with two hours to go.
///
/// Claude has no equivalent. `rateLimits` appears in its transcripts and is
/// `null` in all 1,083 occurrences here, so CodexBar remains the only source
/// for that half.
///
/// A file also travels where a running GUI app cannot: this is readable over
/// ssh, which is what would finally make usage a herd-wide reading rather than
/// something known only about the Mac you are sitting at.
nonisolated struct CodexRolloutUsage: Sendable {
    /// The blocks the API returns. Both may be present, neither may be, and
    /// which of them is called "primary" is Codex's business rather than a
    /// statement about which one is about to stop you.
    struct Window: Equatable, Sendable {
        let usedPercent: Double
        let windowMinutes: Int
        let resetsAt: Date?
    }

    struct Reading: Equatable, Sendable {
        let windows: [Window]
        let observedAt: Date

        /// The one that will stop you first: the fullest, and on an exact tie
        /// the shorter window.
        ///
        /// The tie-break is copied from `AIUsageLimitsParser.blockingWindow`
        /// rather than reasoned out again, and a test caught them disagreeing
        /// when it was. Which window deserves the tie is genuinely arguable —
        /// a weekly cap at 90% is worse news, a five-hourly one bites sooner —
        /// and exact ties are rare enough that being *consistent* between the
        /// two sources matters more than the answer. One provider reading
        /// differently depending on which file it came from would be a bug
        /// nobody could reproduce.
        var blocking: Window? {
            windows.max {
                $0.usedPercent == $1.usedPercent
                    ? $0.windowMinutes > $1.windowMinutes
                    : $0.usedPercent < $1.usedPercent
            }
        }
    }

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex/sessions")
    }

    /// The most recent reading across the newest rollouts.
    ///
    /// Newest few only. Limits are an account-wide fact, so any session's copy
    /// is as good as another's — what matters is which was written last, and
    /// reading every rollout on the disk to learn one number would cost what
    /// the seeding scan costs, every time.
    static func latest(
        directory: URL = defaultDirectory,
        fileLimit: Int = 6
    ) async -> Reading? {
        var best: Reading?
        for file in newestRollouts(in: directory, limit: fileLimit) {
            guard let reading = await read(file) else { continue }
            if best == nil || reading.observedAt > best!.observedAt {
                best = reading
            }
        }
        return best
    }

    static func newestRollouts(in directory: URL, limit: Int) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return []
        }
        let files = enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
        return files
            .map { url -> (URL, Date) in
                let modified = (try? url.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate) ?? .distantPast
                return (url, modified)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(max(limit, 0))
            .map(\.0)
    }

    /// The last populated block in one rollout.
    ///
    /// Read from the end, because limits are appended and only the newest one
    /// describes now. Lines are filtered by substring before any JSON is
    /// parsed: a rollout is mostly messages and reasoning, and parsing all of
    /// it to find a handful of entries is the whole cost.
    static func read(_ url: URL) async -> Reading? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        var latest: Reading?
        do {
            for try await line in handle.bytes.lines {
                guard line.contains("\"rate_limits\"") else { continue }
                guard let entry = try? JSONSerialization.jsonObject(
                    with: Data(line.utf8)
                ) as? [String: Any],
                    let payload = entry["payload"] as? [String: Any],
                    let limits = payload["rate_limits"] as? [String: Any]
                else {
                    continue
                }

                let windows = ["primary", "secondary"].compactMap {
                    window(limits[$0])
                }
                guard !windows.isEmpty else { continue }
                latest = Reading(
                    windows: windows,
                    observedAt: timestamp(entry) ?? .distantPast
                )
            }
        } catch {
            // A rollout being appended to while it is read is ordinary, and the
            // reading taken before the failure is still the newest one seen.
            return latest
        }
        return latest
    }

    private static func window(_ raw: Any?) -> Window? {
        guard let block = raw as? [String: Any],
              let used = block["used_percent"] as? Double,
              let minutes = block["window_minutes"] as? Int
        else {
            return nil
        }
        return Window(
            usedPercent: used,
            windowMinutes: minutes,
            resetsAt: (block["resets_at"] as? Double).map {
                Date(timeIntervalSince1970: $0)
            }
        )
    }

    private static func timestamp(_ entry: [String: Any]) -> Date? {
        guard let raw = entry["timestamp"] as? String else { return nil }
        // Built here rather than shared: a formatter is not Sendable, and this
        // runs off the main actor. Codex stamps entries with fractional
        // seconds, which the default options refuse outright.
        let formatter = ISO8601DateFormatter()
        if let plain = formatter.date(from: raw) { return plain }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw)
    }
}
