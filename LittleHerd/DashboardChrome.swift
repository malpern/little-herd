import Foundation

/// Parts of the dashboard that are built, working, and deliberately not shown.
///
/// **Both of these are hidden pending a design decision, not abandoned.** The
/// dashboard now follows the shape the website's miniature arrived at — a row
/// of metric tabs along the bottom, and a header that says one thing — and the
/// two pieces below were competing with it for the same edges. Everything
/// behind them still runs: sessions are still sampled, tokens still know which
/// machines could take them, and the usage figures are still read.
///
/// They are flags rather than deleted code because the decision is genuinely
/// open, and because this project has been bitten by the other approach: a
/// thing removed "for now" is a thing rewritten from memory later. Turning
/// either back on is one word, and the tests for what they draw still run.
nonisolated enum DashboardChrome {
    /// The agent tokens and their pads, under each machine on the overview.
    ///
    /// They occupied the band the tab row now sits above, and the two together
    /// made the bottom third of a 324-point window three stacked surfaces.
    /// Where they should live instead is the open question.
    static let showsAgentTokens = false

    /// The per-provider usage marks in the top-right of the header.
    ///
    /// The design puts nothing there, and they were the one part of the header
    /// that was neither a title nor a subtitle — two small glyphs carrying a
    /// third meaning in a corner.
    static let showsUsageMarksInHeader = false

    /// The installed-agents list on a machine's AI page, and the seam headers
    /// that separated it from the sessions.
    ///
    /// Which agents are installed and at which version is a fact about the
    /// machine rather than about the work, and it was the first thing on a
    /// page you open to see what is running. With it gone the page is the
    /// sessions, and needs no headers to say so.
    static let showsInstalledAgents = false
}
