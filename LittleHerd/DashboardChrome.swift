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
    /// **Whether a drop actually starts a transfer.** Off, and this one is
    /// not a design question: everything behind it works and has run end to
    /// end on real machines, but there is nothing on screen yet to say a
    /// transfer is happening, how far it has got, or to call it off.
    ///
    /// A drag is a small gesture and easily made by accident. Starting an
    /// agent on another Mac, and pushing a branch, with no visible answer is
    /// the kind of thing that is only discovered later — so the wiring is
    /// complete and this stays false until the progress and cancel controls
    /// exist. It is one word to turn on.
    static let startsTransfers = false

    /// The agent tokens and their pads, under each machine on the overview.
    ///
    /// They occupied the band the tab row now sits above, and the two together
    /// made the bottom third of a 324-point window three stacked surfaces.
    /// Where they should live instead is the open question.
    static let showsAgentTokens = true

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
