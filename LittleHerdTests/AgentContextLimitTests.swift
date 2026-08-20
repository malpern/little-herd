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
        var learner = AgentContextLimitLearner()
        learner.observe([session(tokens: 996_407)])
        learner.observe([session(tokens: 41_233)])
        #expect(learner.limits.limit(for: "claude-opus-5") == 996_407)
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
        var learner = AgentContextLimitLearner()
        learner.observe([session(tokens: 400_000)])
        #expect(learner.limits.limit(for: "claude-opus-5") == nil)
        #expect(learner.limits.fraction(tokens: 400_000, model: "claude-opus-5") == nil)
    }

    /// Context wobbles as a turn is assembled. A few percent is not a
    /// compaction and must teach nothing.
    @Test
    func ordinaryWobbleTeachesNothing() {
        var learner = AgentContextLimitLearner()
        learner.observe([session(tokens: 500_000)])
        learner.observe([session(tokens: 486_000)])
        #expect(learner.limits.limit(for: "claude-opus-5") == nil)
    }

    /// A compaction asked for by hand at a small size would otherwise teach
    /// that this model holds very little, and every later session would read
    /// as overflowing. The largest fall wins.
    @Test
    func aHandCompactionDoesNotShrinkAMeasuredLimit() {
        var learner = AgentContextLimitLearner()
        learner.observe([session(tokens: 996_407)])
        learner.observe([session(tokens: 40_000)])
        learner.observe([session(tokens: 120_000)])
        learner.observe([session(tokens: 12_000)])
        #expect(learner.limits.limit(for: "claude-opus-5") == 996_407)
    }

    /// A short conversation ending is not a model running out of room.
    @Test
    func aFallFromASmallContextIsNotCredible() {
        var learner = AgentContextLimitLearner()
        learner.observe([session(tokens: 12_000)])
        learner.observe([session(tokens: 900)])
        #expect(learner.limits.limit(for: "claude-opus-5") == nil)
    }

    /// Two models are measured apart, because they hold different amounts —
    /// which is the whole reason a single table was wrong.
    @Test
    func modelsAreMeasuredSeparately() {
        var learner = AgentContextLimitLearner()
        learner.observe([
            session(id: "a", model: "claude-opus-5", tokens: 996_407),
            session(id: "b", model: "claude-fable-5", tokens: 166_702),
        ])
        learner.observe([
            session(id: "a", model: "claude-opus-5", tokens: 30_000),
            session(id: "b", model: "claude-fable-5", tokens: 8_000),
        ])
        #expect(learner.limits.limit(for: "claude-opus-5") == 996_407)
        #expect(learner.limits.limit(for: "claude-fable-5") == 166_702)
    }

    /// A session that goes away and comes back must not be compared against a
    /// reading from before it left. That gap is not a fall, and treating it as
    /// one would invent a limit out of an app restart.
    @Test
    func aSessionThatDisappearsIsNotComparedAcrossTheGap() {
        var learner = AgentContextLimitLearner()
        learner.observe([session(id: "gone", tokens: 800_000)])
        learner.observe([])
        learner.observe([session(id: "gone", tokens: 5_000)])
        #expect(learner.limits.limit(for: "claude-opus-5") == nil)
    }

    /// A provider that reports no model cannot be attributed anything.
    @Test
    func aSessionWithNoModelTeachesNothing() {
        var learner = AgentContextLimitLearner()
        learner.observe([session(model: nil, tokens: 900_000)])
        learner.observe([session(model: nil, tokens: 1_000)])
        #expect(learner.limits.observed.isEmpty)
    }

    /// Fullness is capped: a session momentarily over the measured figure is
    /// full, not 104% full.
    @Test
    func fullnessNeverExceedsWhole() {
        let limits = AgentContextLimits(observed: ["claude-opus-5": 200_000])
        #expect(limits.fraction(tokens: 260_000, model: "claude-opus-5") == 1)
    }
}
