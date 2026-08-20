import Foundation

/// Where the agents are, set against where the load is.
///
/// The app has sampled both of these since the beginning and correlated
/// neither, so "the Air has averaged 94%" lived on one screen and "three
/// sessions are on the Air" on another, as unrelated facts. Neither is worth
/// much alone. Together they are the one sentence that turns a monitor into
/// something that answers *what should I do* — and they are the input any
/// later placement decision needs.
///
/// It says one thing and withholds the rest on purpose. A panel that comments
/// on every arrangement of four machines is a panel people stop reading, and
/// the interesting arrangement is narrow: work piled onto a machine that is
/// saturated while another one sits idle.
nonisolated struct HerdWorkloadInput: Equatable, Sendable {
    let machine: MachineID
    let name: String
    let isLive: Bool
    /// What the CPU has averaged over `SustainedLoad.window`, or nothing when
    /// the history does not reach back far enough to say.
    let sustainedCPUPercent: Double?
    /// Sessions actually working. Waiting sessions are excluded deliberately:
    /// they are blocked on a person and consume nothing, so counting them
    /// would blame them for load they are not causing.
    let activeSessionCount: Int
}

nonisolated struct HerdWorkloadFinding: Equatable, Sendable {
    let busyMachine: MachineID
    let busyName: String
    let busyPercent: Int
    let sessionCount: Int
    let idleMachine: MachineID
    let idleName: String
    let idlePercent: Int

    /// Stated as an observation, not as advice.
    ///
    /// Little Herd does not know whether the idle machine could take this work
    /// — that is the eligibility probe, which is not built — and it does not
    /// dispatch or move anything, which the README promises and this must not
    /// quietly contradict. Within one provider a move buys silicon and not
    /// budget, so a sentence that read as "move it there" would be promising
    /// something neither this app nor that machine can necessarily deliver.
    /// Kept to one line at 300 points. The long-form version wrapped onto a
    /// second line and left "has averaged 8%." stranded there, which spent the
    /// panel's scarcest resource on grammar.
    var sentence: String {
        let sessions = sessionCount == 1 ? "1 session" : "\(sessionCount) sessions"
        return "\(sessions) on \(busyName) (\(busyPercent)%) — \(idleName) is at \(idlePercent)%"
    }
}

nonisolated enum HerdWorkloadReader {
    /// The same threshold the menu bar uses to call a machine busy, so the two
    /// surfaces cannot disagree about what "busy" means.
    static let busyPercent = 80.0
    static let idlePercent = 25.0
    // There is deliberately no separate "is the gap wide enough" rule. One was
    // written, and a test proved it could never fire: busy is at least 80 and
    // idle is at most 25, so any pair that clears both thresholds is already
    // 55 points apart. A guard that cannot bind reads like a safeguard and
    // isn't one.

    static func finding(for inputs: [HerdWorkloadInput]) -> HerdWorkloadFinding? {
        // Only machines that are live and have enough history to have an
        // average at all. A machine whose window is not yet covered is not
        // idle — it is unmeasured, and calling it idle would be a guess
        // dressed as a reading. Same rule as `SustainedLoad`, for the same
        // reason: nothing is claimed for the first few minutes after launch.
        let measured = inputs.filter {
            $0.isLive && $0.sustainedCPUPercent != nil
        }
        guard measured.count >= 2 else { return nil }

        guard
            let busy = measured.max(by: {
                ($0.sustainedCPUPercent ?? 0) < ($1.sustainedCPUPercent ?? 0)
            }),
            let busyLoad = busy.sustainedCPUPercent,
            busyLoad >= busyPercent,
            // Without a session on it, a saturated machine is just a busy
            // machine, which the menu bar already says. The join is only
            // interesting when agent work is what is landing there.
            busy.activeSessionCount > 0
        else {
            return nil
        }

        guard
            let idle = measured
                .filter({ $0.machine != busy.machine })
                .min(by: {
                    ($0.sustainedCPUPercent ?? 0) < ($1.sustainedCPUPercent ?? 0)
                }),
            let idleLoad = idle.sustainedCPUPercent,
            idleLoad <= idlePercent
        else {
            return nil
        }

        return HerdWorkloadFinding(
            busyMachine: busy.machine,
            busyName: busy.name,
            busyPercent: Int(busyLoad.rounded()),
            sessionCount: busy.activeSessionCount,
            idleMachine: idle.machine,
            idleName: idle.name,
            idlePercent: Int(idleLoad.rounded())
        )
    }
}
