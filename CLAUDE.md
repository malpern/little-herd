# Little Herd — working notes for agents

A macOS menu-bar app that watches a small herd of machines: this MacBook Air, a
Mac mini, a Linux box, and a Synology NAS. Swift/SwiftUI, XcodeGen, Swift Testing.

## Read this first

**`Documentation/HANDOFF.md` is the roadmap and the authority. There is no other
tracker.** It records the current state, the facts that cost hours to learn, and
what is open. Read it before starting work, update it at the end of a session,
and delete items that are done — a handoff nobody trusts is worse than none.

Its **Hard-won facts** section is the decision log and is permanent; **Next** is
the work list and gets pruned. Do not start a second tracker.

## How to work on this, learned expensively

**Verify by running, not by reasoning.** Repeatedly here something obviously
correct on paper was wrong when measured — `raidType: single` does not mean "no
redundancy", DSM's `up_time` is hours not days, `du` full-buffers to a pipe, and
`AsyncStream.onTermination` does not fire when a consumer breaks out of a loop.
Each was caught by running it, and none by thinking harder.

**Break the test before trusting it.** One cancellation test took four attempts;
three passed while proving nothing. Reintroduce the bug and watch the suite fail,
or you do not know what the test covers.

**Look at the UI.** Every visual defect in this project — a folder rendered as
"L", a missing disclosure triangle, a spinner that never moved — was invisible to
a fully green suite. Kill stray instances first; two running at once mislead.

**Ask before anything that touches permissions.** A folder scanner once triggered
a cascade of TCC prompts because a spawned command inherits the app's identity.
Do not add work that walks the filesystem, enumerates volumes, or reads the
keychain without thinking about what macOS will ask the user.

**Commit early and push.** A worktree was once deleted mid-session with
uncommitted work in it.

**Commit messages are prose explaining why, in the codebase's own voice.** Read a
few with `git log` before writing one.

## Do not "fix" these

- **This Mac reports only its startup volume.** Deliberate: enumerating volumes
  can raise the network-volume privacy prompt. The reason is commented above
  `MetricsSampler.storageVolumes()`.
- **`used = total − available` for volume capacity.** The obvious correction
  breaks the common case; the reason is in `StorageVolume.swift`.

## Commands

```sh
xcodebuild test -scheme LittleHerd -destination 'platform=macOS'   # 627 tests
scripts/release <version> --notes-file <path>                      # from clean main
```

`scripts/release` runs tests, notarizes, signs the appcast, publishes, and
verifies the live feed. It takes several minutes — run it in the background.

Note: a bare `ls` returns nothing in non-interactive shells on this machine;
use `/bin/ls`.
