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
    /// **Whether a drop actually starts a transfer.** On, as of 3 September.
    ///
    /// It was false while there was nothing on screen to say a transfer was
    /// happening, how far it had got, or to call it off. All three exist: the
    /// strip stands in for the header, the card carries a progress bar, and a
    /// finished transfer opens a window on what came back.
    ///
    /// **The note that used to sit here said it was "one word to turn on", and
    /// that was wrong three times over.** Turning it on meant first making this
    /// Mac able to take part at all, fixing a worktree that transferred its
    /// parent's tree, giving the departing session permission to write the
    /// brief it is asked for, and four more found the same way. Every one of
    /// them was invisible to a green suite and obvious within a minute of
    /// running the thing. If this is ever switched back off, do not assume the
    /// road back is short.
    ///
    /// What earned the change: a red transfer that stopped at the check with
    /// the branch exactly where the departure left it and no delivery
    /// attempted, and a green one that landed with the successor's commit on
    /// the branch and nothing left behind on the destination.
    static let startsTransfers = true

    /// **Rehearsal: a drop drives the interface and touches nothing.**
    ///
    /// Development builds only, and deliberately so — it exists to answer
    /// whether the transfer strip reads well, which is a question about
    /// wording and timing rather than about machines. A rehearsed transfer
    /// runs no commands, opens no connection, and pushes nothing; it walks the
    /// phases on a timer so the row can be watched and stopped.
    ///
    /// It is the honest way to exercise an interface whose backend you do not
    /// want firing yet: the alternative is judging a live control by looking
    /// at a screenshot of it.
    static let rehearsesTransfers: Bool = {
        #if DEBUG
        true
        #else
        false
        #endif
    }()

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
