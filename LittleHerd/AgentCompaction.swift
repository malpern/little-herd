import Foundation

/// Where a model compacts, learned rather than assumed.
///
/// Named for what it measures. This is **not** the model's context window: it
/// is the point at which sessions on that model have actually been seen to
/// compact, which is lower — sonnet-4-6 compacts around 165,000 against a
/// 200,000 window, about 82% of it. For deciding when to start a successor
/// session that is the better number anyway, since what you are racing is the
/// compaction and not the API's refusal. It was called a "limit" first, and a
/// design that only works by saying what it measured cannot afford the looser
/// word.
///
/// A transcript records what a turn used and never what the model allows, so
/// the obvious way to show "83% full" is a table of model names and limits.
/// That table was written and thrown away: a live session on this Mac was
/// carrying 425,107 tokens while the table said its limit was 200,000. It was
/// wrong on the day it was written, for the model actually in use.
///
/// What is true instead is that the limit is *observable*. When a session runs
/// out it compacts, and the context drops from nearly full to nearly empty
/// between one sample and the next. The size just before that fall is the
/// limit, measured on this machine, for that model. Measured across six real
/// transcripts it clusters tightly — 996,407 and 996,878 for one model,
/// 164,490 and 166,408 and 166,702 for another — which is what makes a single
/// observation worth trusting.
///
/// So nothing is claimed until a fall has been seen. Before that the interface
/// shows the count and no proportion, which is the same rule `SustainedLoad`
/// applies to a machine whose history does not yet cover its window: a number
/// that is real, and silence where a guess would go.
nonisolated struct AgentCompactionThresholds: Equatable, Sendable {
    /// The largest pre-compaction size seen for each model.
    ///
    /// The largest rather than the latest, because a compaction can be asked
    /// for by hand at any size. One `/compact` at 40,000 tokens would otherwise
    /// teach the app that this model holds 40,000, and every session after it
    /// would read as overflowing. Taking the maximum means a manual compaction
    /// is ignored once a real one has been seen, and errs toward saying less.
    private(set) var observed: [String: Int]

    init(observed: [String: Int] = [:]) {
        self.observed = observed
    }

    /// A fall has to be steep to count. Context wobbles by a few thousand
    /// tokens as a turn is built, and a slow drift is not a compaction.
    static let fallFraction = 0.55
    /// Below this, a fall says more about a short conversation than about any
    /// limit — and no model worth measuring compacts at thirty thousand.
    static let smallestCredibleThreshold = 30_000

    /// Records a fall if it looks like a compaction. Returns whether it did.
    @discardableResult
    mutating func recordIfCompaction(
        model: String?,
        previousTokens: Int?,
        currentTokens: Int?
    ) -> Bool {
        guard let model, !model.isEmpty,
              let previousTokens,
              let currentTokens,
              previousTokens >= Self.smallestCredibleThreshold,
              Double(currentTokens) < Double(previousTokens) * Self.fallFraction
        else {
            return false
        }
        guard previousTokens > (observed[model] ?? 0) else { return true }
        observed[model] = previousTokens
        return true
    }

    func threshold(for model: String?) -> Int? {
        guard let model else { return nil }
        return observed[model]
    }

    /// How close this session is to compacting, when the model's threshold has
    /// been measured. Nil is not "empty" — it is "not yet known", and the interface
    /// has to say the two differently.
    func fraction(tokens: Int?, model: String?) -> Double? {
        guard let tokens, tokens > 0,
              let threshold = threshold(for: model),
              threshold > 0
        else {
            return nil
        }
        return min(Double(tokens) / Double(threshold), 1)
    }
}

/// Watches every session's context between samples and learns from the falls.
///
/// Keyed by session, because two sessions on one model fall independently and
/// a fall is only meaningful against that session's own previous reading.
nonisolated struct AgentCompactionLearner: Sendable {
    private(set) var limits: AgentCompactionThresholds
    /// When each session was last seen to compact.
    ///
    /// The fall was already being detected in order to learn from it, and then
    /// thrown away. It is worth keeping: a session that compacted a minute ago
    /// has just lost the history it was working from, which is the moment a
    /// person most wants to know — and the moment to start a successor rather
    /// than let the next one chew through it too.
    private(set) var compactedAt: [String: Date] = [:]
    private var lastSeen: [String: Int] = [:]

    init(limits: AgentCompactionThresholds = AgentCompactionThresholds()) {
        self.limits = limits
    }

    /// Feeds a round of sessions in. Returns true when something was learned,
    /// so the caller can persist only when there is a reason to.
    @discardableResult
    mutating func observe(
        _ sessions: [AgentSession],
        at now: Date = .now
    ) -> Bool {
        var learned = false
        var seen: Set<String> = []

        for session in sessions {
            seen.insert(session.id)
            let previous = lastSeen[session.id]
            if limits.recordIfCompaction(
                model: session.model,
                previousTokens: previous,
                currentTokens: session.contextTokens
            ) {
                learned = true
                compactedAt[session.id] = now
            }
            if let tokens = session.contextTokens {
                lastSeen[session.id] = tokens
            }
        }

        // Sessions that have gone are dropped, so a session that reappears
        // after a restart is not compared against a reading from hours ago —
        // which would read as a fall and teach a limit that never happened.
        lastSeen = lastSeen.filter { seen.contains($0.key) }
        compactedAt = compactedAt.filter { seen.contains($0.key) }
        return learned
    }
}

/// Turns cumulative CPU seconds into a share of a core.
///
/// A process's lifetime average is not what anyone means by "is this taxing the
/// machine" — a session started this morning that has been idle since reads the
/// same as one working now. The difference between two readings over the time
/// between them is the real answer, and it costs one stored number per session.
nonisolated struct AgentCPUTracker: Sendable {
    private struct Reading: Sendable {
        let cpuSeconds: Double
        let at: Date
    }

    private var previous: [String: Reading] = [:]

    /// Fills in `cpuPercent` where there is enough history to compute one.
    mutating func rating(_ sessions: [AgentSession], now: Date) -> [AgentSession] {
        var seen: Set<String> = []
        let rated = sessions.map { session -> AgentSession in
            seen.insert(session.id)
            guard let resource = session.resource else { return session }
            defer {
                previous[session.id] = Reading(
                    cpuSeconds: resource.cpuSeconds,
                    at: now
                )
            }
            guard let last = previous[session.id] else { return session }
            let elapsed = now.timeIntervalSince(last.at)
            let burned = resource.cpuSeconds - last.cpuSeconds
            // A restarted process reuses nothing and its counter goes
            // backwards; a zero interval divides by nothing. Neither is a
            // measurement, so neither produces one.
            guard elapsed > 0.5, burned >= 0 else { return session }
            var updated = resource
            updated.cpuPercent = min(burned / elapsed * 100, 100 * 64)
            return session.consuming(updated)
        }
        previous = previous.filter { seen.contains($0.key) }
        return rated
    }
}
