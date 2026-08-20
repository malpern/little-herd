import Foundation

/// Reads compaction thresholds out of transcripts already on disk.
///
/// The learner watches the context figure fall between two samples, which is
/// cheap and exact and takes as long as it takes: on a model that holds a
/// million tokens, days. Until then a model has no threshold, so no row shows a
/// proportion and no dot ever blinks — the warning shipped and sat dormant,
/// which was checked rather than assumed (`observedContextLimitsV1` was absent
/// from the preferences the day after it shipped).
///
/// Every compaction that has already happened is written down, though. Reading
/// them once at first launch gives the app on day one what watching would give
/// it over a fortnight, and the numbers agree — the thresholds recorded in the
/// handoff were measured exactly this way.
///
/// Measured against this Mac: 130 transcripts, 33 seconds, and the three
/// thresholds it returned — 997,232, 998,120 and 166,702 — are the same numbers
/// a separate scan had already taken by hand. It is not fast, and it does not
/// need to be: it runs once, in the background, off the launch path, and the
/// panel is useful throughout.
///
/// Local only, deliberately. Doing this over ssh for every remote machine means
/// shipping a scanner to each of them and reading tens of megabytes across a
/// network on a schedule; watching costs nothing and gets there eventually.
nonisolated struct CompactionThresholdSeeder: Sendable {
    /// Where Claude Code keeps transcripts, one directory per project.
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".claude/projects")
    }

    /// The largest pre-compaction context seen for each model.
    ///
    /// The maximum, for the same reason the learner takes it: a hand-run
    /// `/compact` fires below the real threshold and never above it, so the
    /// largest observation is the one that is not a manual one. Measured across
    /// this Mac's own transcripts, opus-4-8 shows four compactions near 995,000
    /// and two far below — and the two below are what someone compacting early
    /// looks like.
    static func scan(directory: URL = defaultDirectory) async -> [String: Int] {
        let files = transcripts(in: directory)
        var thresholds: [String: Int] = [:]
        for file in files {
            for (model, peak) in await scanFile(file) {
                thresholds[model] = max(thresholds[model] ?? 0, peak)
            }
        }
        return thresholds
    }

    private static func transcripts(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "jsonl" }
    }

    /// One transcript, streamed.
    ///
    /// Streamed rather than read whole: these files reach tens of megabytes,
    /// and there can be dozens of them. Lines are filtered by substring before
    /// any JSON is parsed, because the overwhelming majority carry neither a
    /// usage block nor a compaction marker and parsing them would be the whole
    /// cost of the scan.
    static func scanFile(_ url: URL) async -> [(model: String, peak: Int)] {
        var found: [(model: String, peak: Int)] = []
        var peak = 0
        var model: String?

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return []
        }
        defer { try? handle.close() }

        do {
            for try await line in handle.bytes.lines {
                let isCompaction = line.contains("\"isCompactSummary\":true")
                guard isCompaction || line.contains("\"usage\"") else { continue }

                if isCompaction {
                    if let model, peak > 0 {
                        found.append((model, peak))
                    }
                    peak = 0
                    continue
                }

                guard let entry = try? JSONSerialization.jsonObject(
                    with: Data(line.utf8)
                ) as? [String: Any],
                    entry["type"] as? String == "assistant",
                    let message = entry["message"] as? [String: Any]
                else {
                    continue
                }
                if let named = message["model"] as? String { model = named }
                guard let usage = message["usage"] as? [String: Any] else {
                    continue
                }
                let total = (usage["input_tokens"] as? Int ?? 0)
                    + (usage["cache_read_input_tokens"] as? Int ?? 0)
                    + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                peak = max(peak, total)
            }
        } catch {
            // A transcript being written while it is read, or one that is not
            // readable at all, is not worth failing a seed over — the rest of
            // the files still have thresholds in them.
            return found
        }
        return found
    }
}
