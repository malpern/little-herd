import Foundation

/// A preferences suite that removes itself when the test is done with it.
///
/// A test that creates a suite and walks away leaves one behind on every run.
/// They are invisible until you go looking: several hundred
/// `LittleHerdTests.<uuid>` domains had accumulated in the real user
/// preferences before anyone noticed.
///
/// Deinit rather than `defer`, so getting the cleanup right is not something
/// each test has to remember.
final class TemporaryDefaults {
    let suiteName: String
    nonisolated(unsafe) let defaults: UserDefaults

    /// A fixed name rather than a fresh UUID.
    ///
    /// cfprefsd writes a domain back out at process exit, after any teardown has
    /// run, so a per-run name accumulates one file every time no matter how
    /// carefully it is removed. Reusing one name bounds that at a single file
    /// that is overwritten, instead of an unbounded pile. Cleared on creation so
    /// each test still starts from nothing.
    init(name: String = "shared") {
        suiteName = "LittleHerdTests.\(name)"
        // A suite name that is unique per instance cannot fail to open, but a
        // test crashing on nil here would be a confusing way to find out.
        defaults = UserDefaults(suiteName: suiteName)
            ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
    }

    deinit {
        // Removing the domain is not enough on its own. Writes reach cfprefsd
        // asynchronously, so one still in flight lands after the removal and
        // recreates the file — which is how several hundred of these
        // accumulated despite tests that looked like they cleaned up.
        //
        // So: flush first, remove, then delete the file if it is still there.
        defaults.synchronize()
        defaults.removePersistentDomain(forName: suiteName)
        // Also drop the suite from the standard search list. Without this the
        // domain stays registered with cfprefsd, which writes it back out when
        // the test process exits — after the file below has been deleted.
        UserDefaults.standard.removeSuite(named: suiteName)
        defaults.synchronize()

        let path = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: path)
    }
}
