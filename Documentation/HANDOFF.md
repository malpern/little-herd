# Little Herd — handoff

**State:** `main` is clean and pushed, and carries the `v0.1.22` release plus
edits to this file — no unreleased code, so the last code commit is the tag.
264 tests, all passing. The feed is live and was checked rather than assumed:
the appcast at the `releases/latest` URL names `LittleHerd-0.1.22.zip`, carries
a signature, and the asset returns 200. Installed and running here is 0.1.22,
taken there through Sparkle from 0.1.21 and verified — see below.

Deliberately no commit hash in this paragraph. The previous two sessions each
left one that was stale within the hour, including the one written to correct
its predecessor: a line naming a commit is out of date the moment anything is
committed, this file included. `git log` answers that question and cannot be
wrong; what belongs here is what `git log` will not tell you.

**The Synology is fixed.** Drive 2 was replaced on 17 August 2026 — a WD40EFZZ
(4 TB, CMR) for the WD30EFRX that had shed 231 uncorrectable sectors. Pool
`reuse_1` rebuilt overnight and now reports `normal`, raid status 1, 4/4
devices, every drive at `unc=0`. Time Machine on the mini was paused for the
rebuild and is back on — verified: `AutoBackup = 1`, last backup
2026-08-17 21:54, one running since. The extra 1 TB stays stranded until a second 3 TB drive is
replaced; SHR needs two disks larger than the rest before it can use the space.
All three survivors are the same age and batch as the one that failed.

## What the 0.1.15 → 0.1.21 run did

Started from "write view tests" and became eleven releases. The view work
extracted display decisions out of SwiftUI bodies into `MachinePresentation.swift`,
which immediately exposed two live bugs — the same machine reporting two
different statuses, and a fix that had landed in one surface but not its twin.
Then the audit leftovers, drag affordances, sustained-load alerts, a
sign-in-lost alert, remote CPU measurement, and a Finder-style folder browser
with a Full Disk Access flow.

## Hard-won facts

**Read every field before trusting one.** This bit twice in a day.
`raidType: single` does not mean "no redundancy" — it means one RAID group;
`hasParity: true` and 8.99 TB from 4×3 TB were the tells, and the previous
handoff had it wrong. `up_time: 2043` is hours, not days. Both were arithmetic
mistakes dressed as facts, and both changed the advice completely.

**macOS has no shell-readable CPU counter.** `kern.cp_time` is FreeBSD;
`top -l 1` and `iostat -c 1` report since-boot averages far too coarse to
difference. A remote Mac's CPU therefore comes from `iostat` watching for the
whole sampling interval, which paces the loop — verified live at 1.09 s and
10.08 s.

**`AsyncStream.onTermination` fires on task cancellation, not on `break`.** An
earlier version hung process termination on it and assumed a consumer leaving a
`for await` was enough. It is not, so nothing was terminated and a `du` walked
/System after the app quit. Cancellation now comes from
`withTaskCancellationHandler` as well.

**`du` full-buffers its output to a pipe.** Measured: `du -sk /bin /sbin /usr`
delivered all three lines in the same millisecond; separate invocations
delivered `/usr` 160 ms later. Streaming the reader cannot help if the writer
never writes, so each path gets its own `du` inside one shell command.

**`used = total − available` is right, and the obvious correction is wrong.**
A Mac's startup row is one volume of a container whose siblings are not listed,
so what it reports using is the sealed system alone — 17 GB where the container
holds 945 GB. Believing it reads a nearly full disk as a quarter full.

**`SYNO.FileStation.DirSize` is unusable on this DSM.** It starts a task,
returns an id, then answers 599 — "no such task" — to every status call, on
both API versions, for two shares. Measured against the live NAS.

**This Mac reporting only its startup volume is deliberate, not drift.** It was
listed as an inconsistency to fix and should not have been: enumerating mounted
volumes can raise macOS's network-volume privacy prompt even when network
entries are filtered afterwards, which is why routine sampling stays scoped to
`/` and broader discovery sits behind `NetworkVolumeOnboardingView`. The reason
is in a comment above `MetricsSampler.storageVolumes()`. A remote Mac's `df`
runs under sshd, which already holds those permissions; this Mac's does not.
Practically nothing is hidden — this Mac has one volume plus Recovery, which
both paths exclude.

**TCC attributes a spawned command to the app that spawned it.** A disk scanner
therefore trips a permission dialog per protected folder. Remote machines are
unaffected because their commands run under `sshd`, which already has Full Disk
Access — which is also why tunnelling to localhost is not the answer: it obtains
the same access through a wider door and leaves the door open.

**Sparkle's last mile works, and it has now been watched rather than assumed.**
The installed 0.1.21 was taken to 0.1.22 through **Check for Updates…** on
18 August 2026: the alert rendered its release notes correctly, the download
ran, `Autoupdate` replaced the bundle, and the app relaunched. Verified after
the fact rather than on the strength of the dialog closing — version and build
`0.1.22`/`23`, a *new inode* for the bundle (55445740 → 55613997, so it was
replaced and not patched), the running process started from `/Applications`
seconds later, `codesign --verify --deep --strict` clean, `spctl` reporting
`Notarized Developer ID`, and a stapled ticket that validates.

**`log stream` is how you find out what the app really did.** The update was
driven by clicking the menu item through the accessibility API, because a
menu-bar app's menu is not visible to a filtered screenshot. The click tool then
reported that the click had been *blocked* — and the app updated anyway. AppKit's
own log settled it: `trackMouse send action on mouseUp` at 06:24:13.903, the
download 65 ms later, `Autoupdate` at 06:24:14.8. The click had landed and the
tool misreported it, most likely re-checking the frontmost app after the dialog
closed and the app began relaunching. Do not trust that error against an app
that is quitting; read the log.

**A warning for "Tailscale is not running" would be worse than nothing.** Linux
showed a dash and "3 of 4 live" for about five minutes on 18 August. The box was
fine — the mini pinged it 2/2 at 9.6 ms and the watchdog held `linux.fails: 0` —
while this Mac could not resolve `*.ts.net` at all (`scutil --dns` carried no
resolver for it). Throughout, the Tailscale `IPNExtension` process *was running*,
so a process-presence check would have reported everything healthy during the one
event it exists to catch. What ssh already prints is the honest signal, and
`RemoteUnavailability.nameNotFound` already turns it into "Check whether Tailscale
is connected." It resolved itself with no intervention.

**Neither agent can move a session between machines, and the vendors say so.**
Researched 18 August 2026 against the live CLIs and the docs. Remote Control
connects a phone or browser to a session that **keeps running on its own
machine** — it moves the interface, not the work. Cross-session messaging is
explicitly "a piece of text one Claude writes to another, never conversation
history or files", and the documentation's own instruction is that to move a
conversation you resume it instead. Transcript files are not the answer either:
the entry format is documented as internal and liable to change on any release,
and a hand-copied duplicate makes resume report not-found by design. So a
handoff has to be assembled from supported interfaces — `claude -p --resume <id>
--output-format json`, `codex exec resume <id> --output-last-message` (with
`--output-schema` to force the fields a summary would otherwise skip),
`--session-id` to name the successor before it exists, and `-w/--worktree` to
place it. Note that Little Herd's own agent probe parses those unstable `.jsonl`
files today; that is a known risk, not an oversight.

**An agent cannot authenticate over non-interactive ssh on a Mac.** Measured,
not assumed: `claude -p` on the mini answers `Not logged in · Please run /login`,
there is no `~/.claude/.credentials.json`, and the Keychain is unreadable from
that shell. The linux box has the same credentials in a file at mode 600 and
runs headless fine. Codex is file-backed too (`~/.codex/auth.json`), which is
why `emailtriage` can run unattended. This is the gws Keychain saga a third
time, and it has a hard consequence: **a transfer to a Mac cannot be a bare ssh
command.** It needs something resident in the user's GUI login session — a
launchd agent, or a tmux server already running there — which is also what a
durable successor session needs anyway, since `-p` exits when it finishes.

**What blocks a Mac from hosting a session is PATH, not version skew.** The Air
runs Claude Code 2.1.229 and resolves neither `claude` nor `codex` from a
non-login shell, because both sit behind mise shims or an app bundle. Meanwhile
three machines run three different versions — 2.1.126, 2.1.229, 2.1.234 — so
skew is the standing condition rather than a cleanup. Both point the same way:
resolve an absolute agent path per machine and probe for the flag you need
(`claude --help | grep -q -- --session-id`), never pin a version.

## Method notes

**Look at it.** Four times in one session something obviously correct on paper
was wrong when run — and every UI defect (a folder named `Library` rendered as
`L`, no disclosure triangle, a spinner that never moved) was invisible to 263
passing tests.

**Break the test to prove it works.** Every substantive rule was verified by
reintroducing the bug and watching the suite fail. Two tests that passed without
proving anything were caught this way: one watched a side effect a killed shell
would not perform, another counted processes with a command containing the
pattern it grepped for.

**Commit early.** A worktree was deleted mid-session with uncommitted work in
it; the files survived only because the directory had not been reaped yet.

## Next

1. **P-core/E-core awareness is blocked, not pending.** Per-core utilisation
   needs root on a remote Mac — `powermetrics` refuses without it, and neither
   `top` nor `iostat` exposes per-core lines. It would work on this Mac and no
   other, which in an app about a herd is an inconsistency rather than a
   feature. Reopen only if a way to get it without root appears.
2. **Say once, at herd level, that names are not resolving — but not yet.**
   When a machine is unreachable the summary line says only `3 of 4 live`:
   `MenuBarStatusSelector.headline` returns `.unavailable(live:total:)`, and
   `MenuBarMachineSnapshot` carries no reason, so the rollup cannot tell "the
   box is down" from "this Mac cannot resolve anything". The per-machine
   tooltip already gets this right via `RemoteUnavailability.nameNotFound`.
   The change would be to thread the reason into the snapshot and, when *every*
   unavailable machine is `.nameNotFound`, say so once — because that is one
   local cause, not several machine outages.

   **Do not build it yet.** It only earns its keep over a set larger than one,
   and that set is one: when `*.ts.net` resolution died here on 18 August, only
   Linux went dark, because the mini and the Synology resolve on the LAN. The
   rule would collapse to "Linux failed to resolve", which is what the tooltip
   already says. Build it when a second machine becomes reachable only over the
   tailnet, and not before.
3. **The AI panel is the next thing to build.** It is the weakest surface in the
   app. Looked at on 18 August with seven sessions in it: every row carries the
   same orange glyph, so the loudest element says nothing; the primary label is
   the project name, which repeated "Clawd" three times and "Little Herd" twice
   and cannot identify a session; only one row showed what it was *doing* while
   the rest fell back to "Mini · 43m ago"; and the list is sorted by recency, so
   six finished sessions carry the same weight as the one that is live. State —
   the most useful thing the app knows — is a ten-pixel glyph in the right
   gutter where waiting and finished look alike. Two defects are visible in the
   same screenshot: a "Choose metric" tooltip stuck over the header, and the
   last row clipped with no scroll affordance.

   Sort by what needs you rather than by when it happened: waiting first, then
   active, then a collapsed count of what finished. `waiting` is the single most
   actionable fact in the model and is currently indistinguishable from done.

4. **Probe destination eligibility, and let the user express intent separately.**
   Capability is measured — an agent binary resolvable over a non-interactive
   ssh shell, git, a checkout of the repo, and remaining budget. Intent is a
   per-machine setting: some machines can host a session and still should not.
   Eligibility is both, and neither substitutes for the other. Default a new
   machine to off and let the probe make the offer.

   Say *which* reason a machine is not a destination, the way
   `RemoteUnavailability` already does for reachability — "excluded here", "no
   agent on the PATH ssh sees", "no checkout of that repo", and "out of budget"
   are four different answers and only the first is a preference. **The NAS is
   never a destination for this herd** — DSM restricts shell access to
   administrators, the login shell is `/bin/sh`, and there is no package
   manager, so it fails the probe on every count. The setting exists so someone
   with a capable NAS can opt in, not as a safety control here; what stops an
   agent running on the Synology is that there is nothing there to run.

   This rung is useful on its own and everything below depends on it.

5. **Join activity to metrics — the highest-leverage thing not yet built.** The
   app samples both and correlates neither, so "the Air is at 90% sustained" and
   "three Claude sessions are on the Air" sit on two screens as unrelated facts.
   Saying it once — you are saturating the Air, the mini is idle — is what turns
   a monitor into something that answers "what should I do?", and it is the
   input any placement decision needs. It needs no new architecture.

6. **Transfer a session between machines, at the session level.** Not process
   migration, which is not possible and not wanted: stop the session, have it
   write full context, start a successor on the target that has the repo. It is
   the same thing this file does by hand between sessions, which is the reason
   to trust the shape. Decisions already made: the artifact and any uncommitted
   work travel together on a **transfer branch**, so the target checks out one
   ref and has both, atomically and auditably. The machines share one account,
   so a move rebalances **silicon, not tokens** — say so in the interface rather
   than letting a move be made for a reason it cannot deliver. It is
   machine-to-machine only; the phone starts and watches a transfer but is never
   a destination, because Remote Control already covers steering a session from
   a phone and there is no reason to rebuild it.

   The order matters and is a safety property: quiesce, summarise, verify the
   artifact, start the successor, verify it behaviourally, and **only then**
   retire the source. A half-finished transfer must leave you where you started.
   Only a quiescent session can move safely, which is to say a `waiting` one —
   the same state item 3 is about surfacing.

   Expect the summary to omit what matters least to a model and most to you:
   uncommitted work, background processes (documented as *not* restored on
   resume), and which capabilities the session was leaning on — and capability
   genuinely differs per machine here, as ACCESS.md records for `gws` and
   `emailtriage`. Require those fields rather than hoping for them. Reuse the
   existing `transfer.json` contract and its handoff animation, which are built
   and deliberately carry no prompts, transcripts, or credentials. The mover
   stays outside the app: the README's promise that Little Herd "does not
   dispatch or move tasks itself" is worth keeping.

   The same machinery gives **park** and **fork** nearly free, which is a sign
   the factoring is right.

7. **iOS, scoped to the herd rather than to sessions.** Do not rebuild session
   steering; Remote Control and the Claude app already do it, with the local
   filesystem and MCP servers attached. What has no answer today is the herd:
   which machine is hot, what is waiting on you, what the budget looks like,
   and starting a transfer. Do not sample from the phone either — iOS will not
   ssh-poll in the background. It wants a resident collector on the mini, which
   is the same helper item 6 needs for the Keychain problem and the same one a
   durable successor session needs. Build it once. The model layer is already
   portable — 29 of 48 source files import neither SwiftUI nor AppKit, and
   `MachinePresentation` exists precisely because display decisions were pulled
   out of the view bodies.

8. **Show each machine's agent versions.** Cheap, and skew is invisible today
   while being the standing condition; see the facts above.

## Keeping this file honest

It is the roadmap; there is no other tracker. Update it at the end of a session
rather than writing a fresh one by hand, and delete items that are done — a
handoff nobody trusts is worse than none.

**`CLAUDE.md` at the repo root is what makes this file get read.** Until 18
August 2026 nothing loaded it: an agent found this file only when a human
remembered to say "read the handoff first" in the opening message, which meant
every fact below was one forgotten sentence away from being rediscovered. The
root `CLAUDE.md` is loaded automatically into every session, and `AGENTS.md` is
a symlink to it so Codex reads the same text. Keep it short and keep it a
pointer — it costs context in every session, and a copy of this file there
would rot the moment the two disagree.

**The facts section is the decision log, and it is permanent.** `Next` gets
pruned as work lands; facts do not. That split is why this project needs no
separate ADRs — a second tracker is the thing this file exists to avoid. Where a
decision is about one function, the reason belongs in a comment above it, as it
does for `MetricsSampler.storageVolumes()`; you trip over it there at the moment
you are tempted, which no document achieves.
