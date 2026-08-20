import Foundation
import Testing
@testable import LittleHerd

/// Learning how much context a model holds by watching one run out.
///
/// Most of these are about refusing to learn. A limit invented from a
/// misread fall is worse than no limit, because it turns into a percentage
/// that looks measured and is not — which is the exact failure the raw-number
/// design was chosen to avoid.
struct AgentContextLimitTests {
    private func session(
        id: String = "claude:one",
        model: String? = "claude-opus-5",
        tokens: Int?
    ) -> AgentSession {
        AgentSession(
            id: id,
            provider: .claude,
            projectName: "Little Herd",
            state: .active,
            updatedAt: .now,
            progress: nil,
            contextTokens: tokens,
            model: model
        )
    }

    /// The measurement this is all built on, in the shape it was seen in real
    /// transcripts: nearly a million tokens, then almost nothing.
    @Test
    func afallFromFullToNearEmptyIsALimit() {
        var learner = AgentCompactionLearner()
        learner.observe([session(tokens: 996_407)])
        learner.observe([session(tokens: 41_233)])
        #expect(learner.limits.threshold(for: "claude-opus-5") == 996_407)
        #expect(
            learner.limits.fraction(tokens: 498_204, model: "claude-opus-5")
                .map { (($0 * 100).rounded()) } == 50
        )
    }

    /// Nothing is claimed before a fall has been seen. This is the state the
    /// app is in on a fresh install, and it must show a count and no
    /// proportion rather than a proportion of a guess.
    @Test
    func nothingIsClaimedBeforeAFallHasBeenSeen() {
        var learner = AgentCompactionLearner()
        learner.observe([session(tokens: 400_000)])
        #expect(learner.limits.threshold(for: "claude-opus-5") == nil)
        #expect(learner.limits.fraction(tokens: 400_000, model: "claude-opus-5") == nil)
    }

    /// Context wobbles as a turn is assembled. A few percent is not a
    /// compaction and must teach nothing.
    @Test
    func ordinaryWobbleTeachesNothing() {
        var learner = AgentCompactionLearner()
        learner.observe([session(tokens: 500_000)])
        learner.observe([session(tokens: 486_000)])
        #expect(learner.limits.threshold(for: "claude-opus-5") == nil)
    }

    /// A compaction asked for by hand at a small size would otherwise teach
    /// that this model holds very little, and every later session would read
    /// as overflowing. The largest fall wins.
    @Test
    func aHandCompactionDoesNotShrinkAMeasuredLimit() {
        var learner = AgentCompactionLearner()
        learner.observe([session(tokens: 996_407)])
        learner.observe([session(tokens: 40_000)])
        learner.observe([session(tokens: 120_000)])
        learner.observe([session(tokens: 12_000)])
        #expect(learner.limits.threshold(for: "claude-opus-5") == 996_407)
    }

    /// A short conversation ending is not a model running out of room.
    @Test
    func aFallFromASmallContextIsNotCredible() {
        var learner = AgentCompactionLearner()
        learner.observe([session(tokens: 12_000)])
        learner.observe([session(tokens: 900)])
        #expect(learner.limits.threshold(for: "claude-opus-5") == nil)
    }

    /// Two models are measured apart, because they hold different amounts —
    /// which is the whole reason a single table was wrong.
    @Test
    func modelsAreMeasuredSeparately() {
        var learner = AgentCompactionLearner()
        learner.observe([
            session(id: "a", model: "claude-opus-5", tokens: 996_407),
            session(id: "b", model: "claude-fable-5", tokens: 166_702),
        ])
        learner.observe([
            session(id: "a", model: "claude-opus-5", tokens: 30_000),
            session(id: "b", model: "claude-fable-5", tokens: 8_000),
        ])
        #expect(learner.limits.threshold(for: "claude-opus-5") == 996_407)
        #expect(learner.limits.threshold(for: "claude-fable-5") == 166_702)
    }

    /// A session that goes away and comes back must not be compared against a
    /// reading from before it left. That gap is not a fall, and treating it as
    /// one would invent a limit out of an app restart.
    @Test
    func aSessionThatDisappearsIsNotComparedAcrossTheGap() {
        var learner = AgentCompactionLearner()
        learner.observe([session(id: "gone", tokens: 800_000)])
        learner.observe([])
        learner.observe([session(id: "gone", tokens: 5_000)])
        #expect(learner.limits.threshold(for: "claude-opus-5") == nil)
    }

    /// A provider that reports no model cannot be attributed anything.
    @Test
    func aSessionWithNoModelTeachesNothing() {
        var learner = AgentCompactionLearner()
        learner.observe([session(model: nil, tokens: 900_000)])
        learner.observe([session(model: nil, tokens: 1_000)])
        #expect(learner.limits.observed.isEmpty)
    }

    /// Fullness is capped: a session momentarily over the measured figure is
    /// full, not 104% full.
    @Test
    func fullnessNeverExceedsWhole() {
        let limits = AgentCompactionThresholds(observed: ["claude-opus-5": 200_000])
        #expect(limits.fraction(tokens: 260_000, model: "claude-opus-5") == 1)
    }
}

/// Keeping the moment a session compacted, not only the fact that it did.
struct CompactionNoticeTests {
    private func session(id: String = "claude:one", tokens: Int?) -> AgentSession {
        AgentSession(
            id: id,
            provider: .claude,
            projectName: "Little Herd",
            state: .active,
            updatedAt: .now,
            progress: nil,
            contextTokens: tokens,
            model: "claude-opus-5"
        )
    }

    /// The fall was already being detected in order to learn from it, and then
    /// discarded. A session that just compacted has lost the history it was
    /// working from, which is the moment to start a successor.
    @Test
    func theMomentOfCompactionIsKept() throws {
        var learner = AgentCompactionLearner()
        let start = Date(timeIntervalSinceReferenceDate: 5_000)
        learner.observe([session(tokens: 996_407)], at: start)
        #expect(learner.compactedAt.isEmpty)

        learner.observe(
            [session(tokens: 40_000)],
            at: start.addingTimeInterval(10)
        )
        #expect(
            learner.compactedAt["claude:one"] == start.addingTimeInterval(10)
        )
    }

    /// Ordinary work is not a compaction, so nothing is stamped for it.
    @Test
    func nothingIsStampedWithoutAFall() {
        var learner = AgentCompactionLearner()
        let start = Date(timeIntervalSinceReferenceDate: 6_000)
        learner.observe([session(tokens: 500_000)], at: start)
        learner.observe(
            [session(tokens: 512_000)],
            at: start.addingTimeInterval(10)
        )
        #expect(learner.compactedAt.isEmpty)
    }

    /// A session that goes away takes its stamp with it, so a returning session
    /// is not announced as having just compacted an hour after it did.
    @Test
    func aDepartedSessionKeepsNoStamp() {
        var learner = AgentCompactionLearner()
        let start = Date(timeIntervalSinceReferenceDate: 7_000)
        learner.observe([session(tokens: 996_407)], at: start)
        learner.observe(
            [session(tokens: 30_000)],
            at: start.addingTimeInterval(10)
        )
        #expect(!learner.compactedAt.isEmpty)

        learner.observe([], at: start.addingTimeInterval(20))
        #expect(learner.compactedAt.isEmpty)
    }

    /// The threshold is named for what it measures. Sonnet compacts near
    /// 165,000 against a 200,000 window — calling that figure the model's limit
    /// would be the looser word this design cannot afford.
    @Test
    func theMeasurementIsAThresholdNotAWindow() {
        let thresholds = AgentCompactionThresholds(
            observed: ["claude-sonnet-4-6": 165_556]
        )
        #expect(thresholds.threshold(for: "claude-sonnet-4-6") == 165_556)
        #expect(thresholds.threshold(for: "claude-opus-5") == nil)
        #expect(
            thresholds.fraction(tokens: 165_556, model: "claude-sonnet-4-6") == 1
        )
    }
}

/// Codex says what its models hold; Claude does not.
struct DeclaredWindowTests {
    /// Until a Codex session has been watched compacting, the window it
    /// declares is the only ceiling there is — and it is a real one, written
    /// into every rollout as `model_context_window`.
    @Test
    func aDeclaredWindowIsUsedWhenNothingHasBeenMeasured() {
        let thresholds = AgentCompactionThresholds()
        #expect(
            thresholds.fraction(
                tokens: 129_200,
                model: "gpt-5.6-sol",
                declaredWindow: 258_400
            ) == 0.5
        )
    }

    /// Once a compaction has been watched, that wins. It is where sessions
    /// actually compact, which is below the window — measuring beats being
    /// told, and the app is about to stop being told anyway when the next
    /// model arrives.
    @Test
    func aMeasuredThresholdBeatsADeclaredWindow() throws {
        let thresholds = AgentCompactionThresholds(
            observed: ["gpt-5.6-sol": 200_000]
        )
        let fraction = try #require(
            thresholds.fraction(
                tokens: 100_000,
                model: "gpt-5.6-sol",
                declaredWindow: 258_400
            )
        )
        #expect(fraction == 0.5)
    }

    /// Claude declares nothing, so an unmeasured Claude model still says
    /// nothing rather than guessing.
    @Test
    func nothingDeclaredAndNothingMeasuredStaysSilent() {
        let thresholds = AgentCompactionThresholds()
        #expect(
            thresholds.fraction(tokens: 400_000, model: "claude-opus-5") == nil
        )
    }
}
