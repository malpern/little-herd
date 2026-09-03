# Little Herd — handoff

**State:** `v0.1.60` is released and `main` carries thirteen commits beyond
it, unreleased: the diff window, the progress bar on a card, both context menus
rebuilt in AppKit, and the guide reordered. 627 tests pass on this Mac.

**The transfer is built, wired, and switched off — and the reason it is off
has expired.** `endDrag()` reports an accepted drop, `MonitorModel.beginTransfer`
runs the whole seven-step move, a strip in the header band says which step it is
in and offers to stop it, the card carries a progress bar across its foot, and a
finished transfer opens a window showing the diff that came back.
`DashboardChrome.startsTransfers` is still `false`, and its comment still gives
the reason as *"there is nothing on screen yet to say a transfer is happening,
how far it has got, or to call it off"* — all three of those now exist. **The
next decision on this project is whether to turn that word to `true`**, and
nothing but a live run stands in the way. Development builds rehearse the strip
on a timer instead (`rehearsesTransfers`), which is how the wording and timing
were judged.

**The dashboard follows the website's miniature of it: four metric tabs along
the bottom, and a header that says one thing.** The pull-down they replace is
gone, and so is the AppKit machinery behind it. `Memory` is what `RAM` is
called now.

**The agents ride the animals, and the design is built.** Decided by drawing it
rather than arguing about it — seven placement studies, in
`~/Desktop/little-herd-explorations` on the mini. What ships:

- a deck of agent icons behind each working machine, leaning so more than one
  is visible, with a count when the deck is deeper than three
- **no card around them.** An application icon is already a rounded,
  self-contained mark; a frame around it frames a frame, and a fan of six
  became eighteen edges
- pointing at a machine raises its deck into a row above the herd, larger than
  it rested, and lowers it back to the deck's size when the pointer leaves.
  **The herd used to dim while one machine was read, and no longer does** —
  three animals fading every time the pointer crossed one was a large gesture
  for a small question, and the rise turns out to say whose fan it is on its
  own. Judged by looking, which is the only way this could have been settled
- a session starting raises the deck on its own for a couple of seconds
  *without* dimming the herd: an arrival is news, a pointer is a question
- an agent can be picked up and carried across the herd; an animal that could
  take it lifts to meet you, one that could not does not answer
- more agents than the window holds end on a round `+` that opens that
  machine's AI page

**The deck has since been watched and tuned**, which is what settled the
three constants this file once listed as unjudged. The rise was given mass; the
deck became one object that moves rather than two that swap, which is what
stopped it animating twice and flickering as the pointer crossed a card; and it
comes back down instead of being taken away.

**Asking permission is a setting, off by default**, and its per-machine setter
lives on a machine's AI page. See item 4.

**The website is live** at <https://malpern.github.io/little-herd/>, and the
README is a front door that matches it — the hero is baked from the site's own
art, scrim, and wordmark by `scripts/make-readme-hero.swift`, because a README
has no CSS.

**Four releases went out on 25 August.** 0.1.38, memory pressure: the warning
explains itself and names the application worth quitting, swap is measured on
this Mac and on Linux and reported only while it is being written, hovering a
machine puts that machine in the header, and signing in to a Synology says
*which* check refused the certificate. 0.1.39, destinations: a machine no
longer claims it can sign in, and there is a Check that asks. 0.1.40, the AI
panel: rows led by the agent's own icon with the state as a badge on its
corner, progress shown in the row while the work happens, and finished sessions
no longer a group. 0.1.41: the fix for what 0.1.40 broke — a session no longer
vanishes the moment it answers you — and the removal of the destination
interface, which was a permission and a placement decision for a move that
cannot happen.

**Little Herd is free for now, paid later.** The paid shape stays recorded and
unbuilt; see *The website* below, which is also the material review.

Five releases went out on 20 August, and three of them were fixes for things
the first two shipped:

    0.1.33  destination eligibility
    0.1.34  agent versions per machine
    0.1.35  an empty directory no longer takes a machine off the dashboard
    0.1.36  the per-session CPU meter, working for the first time
    0.1.37  the window stays on screen, with a margin

and one on 25 August:

    0.1.38  memory pressure explains itself, and swap is measured
    0.1.39  a destination says whether it can actually sign in
    0.1.40  the AI panel is rebuilt around what is running
    0.1.41  a session stays visible after it answers; destination UI removed

and four on 26 August:

    0.1.42  Codex sessions renameable; hovered headers removed from every panel
    0.1.43  agent tokens on the CPU screen, and the drag that carries them
    0.1.44  a hover card on a token, and a click that opens the AI page
    0.1.45  the drag asks each machine what it could actually take
    0.1.46  a session that starts says so — which fired essentially never
    0.1.47  the fix for 0.1.46: it now waits for somebody to be looking
    0.1.48  cards open beside their token, and can be dismissed
    0.1.49  the metrics move to tabs along the bottom; agent tokens hidden
    0.1.50  the fix for 0.1.49: the tabs were clipped by the titlebar band

ten more between 27 and 29 August, and six of them are the transfer:

    0.1.51  the window measures itself as content plus titlebar
    0.1.52  the herd holds still as you change metric; backups in the guide
    0.1.53  the tab mark has two levels, and reddens for a machine in trouble
    0.1.54  the agents sit behind the animals, with no card around them
    0.1.55  the deck rises, answers an arrival, and can be carried
    0.1.56  the transfer's constraints written down before anything is built
    0.1.57  the shell taken from a successor; an allowlist was never a fence
    0.1.58  the transfer machinery: departure, pilot, successor, coordinator
    0.1.59  a drop reaches the transfer, with the door held shut
    0.1.60  a strip to watch it and stop it; a machine is an account on a host

and on `main`, unreleased: the diff window that says what came back, a progress
bar across the foot of the card, both context menus rebuilt in AppKit because
SwiftUI drops their icons, Settings saying each thing once, and the guide
reordered to start where a Mac user already is.

**0.1.33 shipped a bug that could take a machine off the dashboard entirely** —
an empty directory aborting the probe under zsh. Nothing in this herd tripped
it, which is exactly why it survived a release. **And the session CPU meter had
been broken since it was written**, in four independent ways; both stories are
in the facts below.

Watched in the running app on 20 August, not only rendered: the Settings
checkbox ticks, persists into `machineConfigurationsV1`, survives a relaunch,
the AI panel's Destinations section appears under a waiting session, and a
machine's AI page lists what it has installed. Doing that found four defects a
green suite and eight renders had all missed — every one is in the facts below.

Eight releases went out on 19 August. **Two of them — 0.1.30 and 0.1.31 — were
published without the features their notes announced**, because a merge failed
silently inside a pipeline; both have been corrected on GitHub and the cause is
in the facts below. Check that a tag contains a commit before believing a
release contains a feature.

**There is a preview harness, and it has earned itself repeatedly.**
`PanelRenderHarness` writes PNGs of real views at their real widths, because
tests run inside the app bundle and `ImageRenderer` can do there what a preview
does in Xcode. It has now caught: a session from last week reading "213h ago";
a sentence wrapping and stranding "has averaged 8%."; a row marked ambiguous
against a row hidden inside a collapsed group; a warning dot that faded to
invisible on a light background; a header number wrapping to two lines; a
context ring drawn in `.secondary`, the same tone as its own track; and two
64-character fingerprints truncating to `Expected aa…bbbbbbbb`, which a passing
test had asserted the presence of for a release and a half. Not one was visible
to a green suite. **Render a view before shipping it.** It now also draws the
three hovered headers at the 68 points the header area gives them, which is
where the CPU one was caught still reporting cores.

Four things it cannot see. It renders neither `ScrollView` nor a lazy stack —
the first version wrapped both, wrote a blank image and reported success — nor
a `Form`, which is why the sign-in sheet renders with a blank band where its
fields are. **A `.borderless` or `.link` button draws as a yellow no-entry
placeholder**, so the Settings rows render with one where the remove button is
and another where the NAS's "Connect…" link is; an ordinary bordered button in
the same suite draws correctly, which is how that was pinned on the style rather
than on the row. And it cannot show a hover state, so anything that appears on
hover has to be checked in the running app: the AI panel's section chevrons are
unverified by eye. Tooltips no longer need the eye — read `AXHelp` off the
running app's accessibility tree instead, which is the same string macOS shows
and can be had for every machine in one command. See the method notes; the
mouse turned out to be the least reliable instrument in the room.

**The Synology hardware is fixed.** Drive 2 was replaced on 17 August 2026 — a WD40EFZZ
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

**App Transport Security decides before your delegate does, and a command-line
probe cannot see it happen.** This is what "Little Herd cannot sign in to the
Synology" was, after an evening of ruling out eight other things. ATS runs its
own system-trust evaluation, and a certificate that fails it is refused *before*
`URLSession` asks the delegate — so `SynologyTrustEvaluator` computed the
correct pin, returned `useCredential`, and was overruled, surfacing as
`NSURLErrorDomain -1200`. The tell was one line in the app's own log,
`ATS failed system trust`, sitting beside a TLS trace that had been read a dozen
times. The fix is in `Info.plist`, with the reason next to it.

The previous session's decisive evidence pointed the wrong way for a reason
worth keeping: **a command-line tool has no `Info.plist`, so ATS never applies
to it.** "The same algorithm works outside the app and fails inside it" was
true, and was not about the algorithm. The instrument that settles this in 34
milliseconds is a test in the hosted bundle — `TEST_HOST` runs the suite inside
the real app, so it inherits the real `Info.plist` — and a sign-in with a
deliberately *wrong* password separates the layers: a working transport answers
`400 Wrong account or password`, and only a TLS failure looks like a TLS
failure. Testing the thing that was broken needed no real credential at all.

Three smaller facts fell out of it, each measured rather than reasoned.
`NSAllowsLocalNetworking` does not cover a tailnet name — `nas.tail9d0bb8.ts.net`
is fully qualified, so it is not "local" to ATS however local it feels. An entry
in `NSExceptionDomains` still binds when `NSAllowsArbitraryLoads` is true, which
is why the update feed keeps the ATS floor while a NAS on any name at all does
not. And the fix this replaces — plain HTTP to port 5000 over the tailnet —
would not have worked: ATS stops `http://` with `-1022` before it leaves the
process, so it needed the same `Info.plist` change anyway, and once that change
exists TLS with first-use pinning works and beats sending a DSM password in
clear.

**A transcript records what a turn used, never what the model allows — so
there is no honest context percentage.** Claude's `.jsonl` carries
`input_tokens`, `cache_read_input_tokens` and `cache_creation_input_tokens`,
which sum to what was in front of the model on that turn, and reading the last
one gives the current context. Nothing anywhere records the limit. A
model-to-limit table was written to turn that into a percentage and thrown
away after measuring: a live session on this Mac was carrying **425,107
tokens**, against a table that would have called the limit 200,000. It was
wrong on the day it was written, in this herd, for the model actually in use.
So the panel shows the number and no bar. If a proportion is ever wanted, the
limit has to come from the user, not from a constant. Codex's rollouts record
no equivalent figure at all, so that field is empty for half the herd — and
empty must stay empty rather than becoming a zero, which would claim an empty
context.

**A session is a process, and its working directory is the only thing tying the
two together.** Nothing in a process list names a session, but a transcript
records the session's `cwd` and `lsof` records the process's, and they match —
verified on this Mac at five processes, five joined, none unmatched. One
`lsof -a -d cwd -p <pids>` covers every session on a machine in about 42 ms, so
ask once rather than once per session, and match on the `claude-code` binary
path rather than the command name or the desktop application answers to
"claude" too. Two sessions started in the same directory cannot be told apart
this way and are given no figure at all: a wrong attribution reads as "this is
the expensive one" and could send someone to move the wrong work.

CPU needs the same treatment a whole machine already gets. `ps` reports a
process's average over its entire life, so a session that worked hard this
morning and has idled since reads as busy; the honest figure is cumulative CPU
seconds differenced across the interval between two samples. One reading yields
no rate rather than a lifetime average dressed as a current one, and a counter
that goes backwards — a restarted process — is not negative work.

**Where a model compacts is measurable, and it is not the model's context
window.** Measured across every compaction in this Mac's transcripts:

    claude-sonnet-4-6   n=4   164,490 … 166,702   spread 1.3%
    claude-opus-5       n=1   998,120
    claude-opus-4-8     n=6   354,689 … 997,232   spread 64%

Sonnet compacts near 165,000 against a 200,000 window — about 82% of it — so
the figure to learn is the *compaction threshold*, and calling it a limit is
the looser word. Opus-4-8's wide spread is the other lesson: four of its six
compactions cluster at ~995,000 and two sit far below, which is what a hand-run
`/compact` looks like. A manual compaction is always *below* the real trigger
and never above, so taking the **maximum** observed converges on the truth and
ignores them — that was reasoning when it was written and is measurement now.

The app learns this by watching the number fall between two samples, which
costs nothing; scanning transcripts for compaction markers would mean reading
38 MB files every ten seconds. Nothing is claimed for a model until a fall has
been seen.

**Usage is a herd reading now, and the machines genuinely disagree.** Codex's
limits live in files, so the same extraction runs over ssh — measured on both
machines the same evening:

    Air    2026-08-14T09:01:59   30%
    mini   2026-08-15T01:34:15   42%

One account, two ages, sixteen hours apart, and the same `resets_at` on both.
The mini is fresher because it runs `emailtriage` twice a day while this Mac
runs Codex when someone opens it — which is the whole argument for reading
every machine rather than the one you are sitting at. The newest wins wherever
it was found. The handoff's old line that "usage is read only from this Mac"
no longer holds for Codex; it still holds for Claude, which has no first-party
source at all.

**Two usage sources, and neither is better — they fail at opposite times.**
Codex's rate limits can be read from its own rollouts *and* from CodexBar's
scrape, and the obvious rule, prefer the first-party file, is wrong. Measured:
the newest populated block in a rollout on this Mac was **five days old and
said 30%**, while CodexBar's copy was a day old and said **100%** — because a
rollout is written when a session runs and this Mac runs Codex occasionally,
whereas CodexBar polls on a timer whenever it happens to be running. Preferring
the file would have replaced a nearly-right number with a badly wrong one.

Take the later of the two and no rule about trust is needed. The rollout needs
no second application and is written the moment a turn ends; the scrape keeps
polling when no session runs at all. Both are then subject to the same
freshness test, because a file written five days ago is five days old whoever
wrote it.

**Codex records more about itself than Claude does, in files already on disk.**
A rollout at `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` carries, per turn:
`turn_context.payload.model`; `token_count.info.last_token_usage.total_tokens`;
**`token_count.info.model_context_window`** — the window stated outright, where
Claude records nothing of the kind and it has to be learned; a `compacted` entry
type, so compaction is marked rather than inferred; and `custom_tool_call`
entries for activity. It names the call and not its purpose, though — every
shell command arrives as `exec` with a block of JavaScript as its argument,
which is why Codex rows say "Running a command" where a Claude row says what
the command was for.

**And the vendor's own rate limits are in there too.** 216 rollouts on this Mac
carry a populated block:

    "primary":{"used_percent":100.0,"window_minutes":10080,"resets_at":1786388138}

That is the same shape CodexBar supplies, first-party, on disk, with no
third-party application in the path — and readable over ssh, which CodexBar is
not, so it would extend usage past "this Mac only". Not wired up: it is a
larger change than the panel work it was found during. See the item in **Next**.

**CodexBar keeps two different things, and the one this app was reading is the
lesser.** `~/Library/Caches/CodexBar/Cache.db` is the `NSURLCache` scrape;
`cost-usage/` is the real store, with per-day per-model token counts in
`claude-v6.json` built by scanning the same `~/.claude/projects/*.jsonl` files
Little Herd already parses. So consumption needs no CodexBar at all. What does
need it is the *limit and reset* half — `codex-account-snapshots.json` carries
`usedPercent`, `resetsAt` and `windowMinutes` from OAuth, which is genuine
vendor state. Claude has no first-party equivalent: `rateLimits` appears in the
transcripts and is `null` in all 1,083 occurrences.

The practical failure is not the mechanism, it is that CodexBar has to be
running. It last wrote at 14:50 and everything was a day stale by evening,
which fails the 15-minute freshness window, so the app showed nothing — and
nothing looks exactly like "no limit". Little Herd starts it now when it is
installed and not running, and names it where a number is missing.

**Only the Air can host a Little Herd session today, and that is the argument
for asking.** Measured 19 August: the mini has seven repositories under
`~/local-code` and Little Herd is not one of them; the linux box has no such
root at all. A destination probe that checked only for an agent and git would
have offered both machines, and a transfer to either would have failed at the
first fetch.

Two details the measuring turned up. A repository's identity is its origin
remote's slug and **not** the directory it sits in — this herd has
`keyboard-newswire` checked out in a folder called `keyboard-wire`. And that
slug has to come from the `[remote "origin"]` section specifically: one
repository here has a remote called `sites-origin`, and reading the first
`url =` in `.git/config` gave it a different identity than git does.

Reading `.git/config` beats asking git, for identical answers: 38 checkouts
took 783 ms through `git remote get-url` and 303 ms read directly, because the
first spawns thirty-eight processes and the second spawns none.

**zsh aborts the whole script on a glob that matches nothing — and this has
now happened twice.** The second time was the checkout scan, which shipped in
0.1.33 globbing `"$root"/*`, so a single **empty** `~/code` on a Mac took the
whole probe down: no sessions, no agent versions, and over ssh no metrics
either, because `SSHCommandRunner` throws on a non-zero exit and the sample is
discarded. **A machine would have read as down because a directory was empty.**
No machine in this herd tripped it — the mini's `~/local-code` has nine entries
and the linux box runs bash, where an unmatched glob is passed through — which
is exactly why it survived a release. There is a test for it now, and it was
watched failing with the glob put back.

Two details for next time. Not every glob here is fatal: the rollout scan's
`ls -t …/*/*.jsonl` sits inside `$(…)`, so the abort kills only that subshell
and the script carries on — measured, and the reason it was left alone. And a
`find` needs its depth measured rather than counted: a checkout's `.git/config`
is **three** levels below the search root, and two and four each find nothing
while failing silently, which looks identical to an account with no
repositories.

**The original of this lesson, which the above repeats.** The agent probe
runs under `/bin/zsh -c`, and a pattern with no matches is a fatal error there
where `sh` would pass it through untouched. A glob added to look for a bundled
agent took out *every session in the AI panel* on any Mac without that bundle —
not just the version it was looking for. The repo's shell tests caught it
immediately, which is exactly what they exist for.

Use `find` instead, which also survives the space in "Application Support" that
any unquoted expansion would not. Watch its `-maxdepth`: the path is five
components below the search root, and four found nothing while failing
silently, which looks identical to "no agent installed".

**A pipeline's exit status is the last command's, so `&&` will not protect
you.** Two releases shipped without the work they announce because of this one
line:

    git merge --ff-only origin/branch | tail -1 && scripts/release ...

The merge failed — `main` had moved and could not fast-forward — and `tail`
exited 0, so the `&&` sailed past it and the release script cut a build from an
unchanged `main`. Nothing in the output said so: the script's preflight checks
that the tree is clean and the branch is `main`, both of which were true, and
its notes come from a file rather than from the diff. 0.1.30 and 0.1.31 both
went out describing a feature they did not contain, and both have since been
corrected on GitHub.

Never pipe a command whose exit status matters. Run it bare and read it, or set
`pipefail`. And treat "the release script succeeded" as evidence about the
script rather than about what is in the build — the only thing that settles
that is asking git whether the commit is an ancestor of the tag.

**A plain `xcodebuild -configuration Release build` produces an app that cannot
launch.** It signs ad hoc, and dyld then refuses to map the bundled Sparkle:
`Library not loaded: @rpath/Sparkle.framework/…`, `mapping process and mapped
file (non-platform) have different Team IDs`. The crash report says "Library
missing", which sends you looking for a file that is sitting right there — the
signature is what is missing, not the framework. To test a Release build without
running `scripts/release`, pass the same identity it does:
`DEVELOPMENT_TEAM=X2RKZ5TG99 CODE_SIGN_IDENTITY="Developer ID Application"
CODE_SIGN_STYLE=Manual`. Worth doing rather than falling back to the Debug
build, because a keychain item's ACL is bound to the signature that stored it —
a DSM password saved by an ad-hoc build is not cleanly readable by the shipped
one.

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

**A Mac agent's credentials decrypt only inside the GUI login session, and the
test that proves it is `security -w`.** Established 18 August 2026 across both
Macs. The `Claude Code-credentials` Keychain item *exists* on the Air and on
mini/clawd, and its **attributes read fine over non-interactive ssh** — so a
`security find-generic-password` without `-w` succeeds there and says nothing
useful. Ask for the secret with `-w` and it is **readable from the GUI session
and blocked over ssh, on both machines**. Checking the wrong one of those two
during this session produced a confident conclusion in each direction before the
distinction turned up; if you test this again, test the secret.

The consequence is a clean split by provider rather than by machine. **Codex is
file-backed** (`~/.codex/auth.json`, mode 600) and was run under `env -i` — no
PATH, no environment at all — reaching the API and failing only on a usage
limit. That is why `emailtriage` runs unattended, and it means Codex transfers
over ssh work today. **Claude Code on macOS is Keychain-backed**, so ssh alone
can never authenticate it there: a transfer to a Mac needs something resident in
the user's GUI login session — a launchd agent, or a tmux server started there —
which is also what a durable successor session needs, since `-p` exits when it
finishes. The linux box is unaffected: its credentials are a file at mode 600
and it runs headless.

**The credential question was measured end to end on 25 August, by running the
agents rather than by reading their credential stores.** Six probes, one per
agent per machine, each asked to reply `AUTH_OK`:

    Air     claude  ✗  "Not logged in · Please run /login"
            codex   ✓  AUTH_OK
    mini    claude  ✗  "Not logged in · Please run /login"       (over ssh)
            codex   ✓  AUTH_OK                                   (over ssh)
    linux   claude  ✗  "OAuth session expired and could not be refreshed"
            codex   ✗  "Your access token could not be refreshed"

**Transfer is not blocked. `ssh openclaw` → `codex exec` → an authenticated
answer is a successor started non-interactively on a remote destination**, which
is the step the whole design rests on, and it works today with no resident
helper, no launchd agent, and nothing installed.

Two corrections to the fact above, both of which matter.

**Being inside the GUI login session is not sufficient for Claude Code on
macOS.** The Air probe ran from a shell spawned by Claude.app itself — the same
login session, the same user — and still got "Not logged in". So the barrier is
not only the ssh boundary. There are *three* Keychain items, not one:
`Claude Code-credentials` and two suffixed `-8f274711` and `-d950d442`, with no
mapping to them found in `~/.claude.json`, `~/.claude/`, or the app's own
`config.json`, and the bundled CLI takes no config-dir flag. Whatever the CLI
looks for, it is not what the desktop app authenticated. **This weakens the
proposed fix** — a launchd agent or tmux server resident in the GUI session was
supposed to solve this, and it may not be enough on its own. Test that
specifically before building on it.

**File-backed does not mean durable.** Both of linux's credential files exist at
mode 600 and both are *expired* — Claude's OAuth session and Codex's access
token each refused to refresh. The mechanism worked and the token had lapsed,
which is a different failure from having no credentials and reads identically
from a distance.

**Eligibility now carries authentication, and there is no cheap way to measure
it.** `codex login status` looks like the answer — it printed "Logged in using
ChatGPT" and exited 0 in 78 milliseconds — on the machine whose token had
refused to refresh ten minutes earlier. It reports that credentials exist,
which was never the question, and Claude Code offers nothing of the kind at
all. The only proof is a request the provider answers; `AgentAuthProbe` asks
for the smallest one there is, and **it is deliberately not part of the
thirty-second sample**, because a monitor that quietly spends the budget it is
reporting on has stopped being a monitor.

`DestinationEligibility.eligible` therefore carries an `AgentAuthState`, and
the affirmative answer stopped overclaiming. It used to read "Can host a
session" on the strength of a binary being present — which is exactly what
linux would have said, with two agents installed and neither able to sign in.
It reads "sign-in not checked" until something checks, and `.signedOut` when a
provider has refused, which is a machine to sign in on rather than one to
install onto.

**What is not built is the caller.** Nothing runs `AgentAuthProbe.command(for:)`
yet — there is no reusable per-machine command runner, only `LocalProcessRunner`
and the ssh invocation buried inside `RemoteMetricsSampler`. The transfer flow
is the natural first caller, since it has to verify the successor before
retiring the source anyway; a manual check in Settings is the other. Until one
exists, every machine reads unverified, which is true.

**No machine in this herd has an agent on the PATH ssh sees, and every one of
them can run both.** Measured 19 August over non-interactive ssh, which is the
only measurement that counts:

    Air     claude 2.1.234   /Users/malpern/Library/Application Support/Claude/claude-code/2.1.234/claude.app/…
            codex  0.148.0-alpha.15   /Applications/ChatGPT.app/Contents/Resources/codex
    mini    claude 2.1.234   ~/.local/bin/claude   (and 2.1.221 in the bundle)
            codex  0.148.0-alpha.9    ~/.local/bin/codex
    linux   claude 2.1.234   ~/.local/bin/claude   (a mise shim)
            codex  0.147.0            ~/.local/bin/codex

`command -v claude` returns nothing on all three. A probe asking the PATH would
report an empty herd and be wrong about every machine in it, which is why the
design resolves an absolute path per account.

This corrects the earlier note that the Air "needs the CLI installed before it
can host a Claude session". It does not: the binary is inside
`/Applications/Claude.app`'s support directory and answers `--version` fine.
What the Air cannot do is *authenticate* — that is the Keychain fact below, and
it is a different problem from having no binary. Version skew is real but
smaller than recorded: Claude is 2.1.234 everywhere now, Codex is three
different builds.

**A mise shim answers `--version` with mise's banner, not the agent's.** On the
linux box both agents are shims, and asking one its version returns
`mise ~/.config/mise/config.toml tools: claude@2.1.234`. Anything parsing that
output has to strip it, or the herd's version column reads as nonsense on one
machine and nobody notices which.

**Usage limits are read only from this Mac, and only through CodexBar.**
`AIUsageLimitsSampler` uses `homeDirectoryForCurrentUser` for both providers;
no remote sampler collects usage at all. Codex comes from CodexBar's
`codex-account-snapshots.json` and Claude from `Library/Caches/CodexBar/Cache.db`
— the latter by scraping that app's HTTP response cache, joining
`cfurl_cache_receiver_data` to `cfurl_cache_response` for a request key ending
`/usage`. That is another app's `NSURLCache` internals, as fragile as the
`.jsonl` parsing above. A 15-minute freshness window drops stale readings, so an
empty usage display means either "no limit" or "CodexBar is not running", and
the interface does not distinguish them.

Because the herd shares one account the local reading *is* the herd's budget, so
this is a smaller gap than it looks. On 18 August the mini's Codex hit its limit
until the following evening with three `emailtriage` slots due — and the app was
not silent, which is the more useful finding: it had been showing an urgent red
LED on the Codex mark the whole time. A six-pixel unlabelled dot in the corner of
a header is the same as silence to the person it is for. That is why the AI
panel's state moved to the leading edge and gained a glyph per state rather than
a colour per state, and it is the reason item 3 checks budget once rather than
per machine.

**A new non-optional key in `MachineConfiguration` would empty a saved herd,
and a default value does not save you.** Measured, because the obvious reading
of the language is wrong: Swift's *synthesised* `Decodable` never consults a
property's default value, so `var mayHostSessions: Bool = false` throws
`keyNotFound` on every machine written before that key existed. The store
decodes entry by entry and keeps out whatever it cannot read — deliberately, so
a machine written by a newer build survives an older one — which turns that
throw into a silently emptied herd on the first launch after an update, for the
one thing the user cannot recover by pointing Little Herd at the network again.
Declare the stored property optional and read it through a computed accessor
that supplies the default. The test that guards this strips the key out of the
encoded form and decodes what is left.

**A column that says one sentence three times is a column people stop reading.**
The destination list renders one row per account with its reason — and before
anyone has ticked anything, every reason is the same, so the first render was
three identical lines of "Excluded here — turn it on in Settings." It says it
once now. This is the third time this panel has been trimmed of a repetition
that a passing suite could not see, after the row disambiguator that marked
every row and the "waiting" label said twice; the rule underneath all three is
that information which does not distinguish one row from its neighbour is not
information.

**No two agents print `--version` the same way, and the fixtures had invented
a fourth shape.** Every one of these was measured by running the command:

    claude  2.1.234 (Claude Code)                       number first
    codex   codex-cli 0.148.0-alpha.15                  name first
    codex   mise …/config.toml tools: codex@0.147.0     a shim's banner

The first fix took the first token, which is right for Claude and gave a
version column reading **`codex-cli`** for Codex — and then, since a token with
no digits in it compares as zero, every real version in the herd looked newer
than it and every Codex row claimed to be behind. The rule is the first token
that *starts with a digit*; the shim's banner is stripped in the probe before
that. Anything unparseable is passed through whole rather than dropped.

Both halves of this were found by looking at the running app, and the same
sentence covers both: the fixtures were written from this file's own version
table rather than from the command's output. **When a fixture and a machine can
disagree, run the command.**

**A session outside a checkout has no destination, and the first version said
it had three.** The panel names the repository the destination list is
answering for, taken from the origin remote's slug — and when a session's
working directory is not a checkout, that is nil and the fall-back was the
project name. Against the real herd it produced "Could take Local Code", which
reads like a repository and is a folder; worse, with no slug the checkout
question is not asked of anybody, so every account came back eligible for work
that cannot travel at all. It now says "Not in a checkout" once, rather than
either lying or vanishing — a section that silently disappears is the false
silence this project keeps having to write tests against.

**macOS only promises that a window's *title bar* stays on screen.** The rest
may hang over the edge, and does: this app's launch splash is its largest
window and is placed relative to wherever the dashboard was last left, so a
dashboard saved near an edge put the splash over it — measured at 92 points
beyond the right of the display. The window is now clamped into the screen's
`visibleFrame` on restore and whenever the bridge computes a frame.

Three things learnt fixing it, each by measuring rather than looking.

**A clamp that moves the window the least distance lands it flush against the
edge**, which is on screen by the arithmetic and still reads as cut off — it
was reported a second time, for the bottom, after the right had been rescued.
The margin is sixteen points and applies to every edge whether or not the
window was over one.

**SwiftUI resizes the window after you have positioned it.** Under
`.windowResizability(.contentSize)` it sizes from the content, keeps the
top-left and grows downward, so a frame set in `applySplashChrome` was correct
and the frame on screen was not. The placement is re-applied once on the next
runloop pass, and that is what actually fixed it.

**Window geometry can be read without screen-recording permission**, which
matters because screen capture stopped working halfway through this and the
numbers were needed anyway. `CGWindowListCopyWindowInfo` reports every window's
bounds; only pixel *contents* are privileged. Comparing those bounds against
`CGDisplayBounds` gives an exact overhang in points, which beats squinting at a
screenshot — and it is how both the bug and the fix were confirmed.

**The session meter was broken in four independent ways, and each one alone
was enough to keep it empty.** Worth listing together, because three releases
went out adjusting the *threshold* while the number behind it could not have
been right:

1. It measured the agent binary rather than the work it starts — about a
   hundredfold too small. Fixed by summing the process tree.
2. A cached reading was scored as a measured zero. The probe refreshes every
   thirty seconds and the sampler runs every ten, so two samples in three
   re-serve the same counter; differencing those wrote a confident 0% over a
   real measurement, on most samples. **An unchanged counter is the absence of
   a reading, not a measurement of idleness.**
3. One `AgentCPUTracker` serves the whole herd and is handed one machine's
   sessions at a time. It discarded every entry absent from the list in front
   of it, so each machine's sample threw away the others' history — and a
   reading discarded before its successor arrives can never become a rate.
   With more than one machine configured this alone produced no figure, ever.
4. The floor was 15% of a core, set by estimate against a broken number.

The lesson is not any one of them. It is that a feature nobody had *watched
work* accumulated four faults, and the visible symptom of all four was
identical — an empty column, which reads as a design choice. It was finally
seen to draw on 20 August, holding a core under a session's tree: one green
block of five against a ten-core machine.

**Two instruments lied during that hunt, in the same session.** Several rounds
of "still no meter" were screenshots of an app built **eight hours earlier**
from a different checkout: this repo has worktrees, each has its own
`DerivedData`, and a hardcoded path kept launching the stale one while every
build went to the other. Check `WorkspacePath` in the DerivedData `info.plist`
if a change appears to have no effect. And a diagnostic reported
`** TEST SUCCEEDED **` having executed **zero tests**, because the new test
file was not in the generated project — run `xcodegen generate` after adding
one, and read the executed count rather than the banner.

**`ps` counts living processes only, so a child's CPU vanishes from the tree
the moment it exits — and that is most of what an agent does.** Found while
watching the fixed figure in the running app, which is the only reason it was
found at all. A shell loop was run inside a session's tree for four minutes; it
spawned a short-lived `date` per iteration, and the tree total rose by 16.6
seconds over ninety — 18% of a core, which is the *shell's own* share. Every
child's work evaporated as it exited.

What this leaves is a figure that is honest about **sustained** children — a
long compile, a test run, a `du` over a big tree — and close to blind to a
storm of short ones, which is what ordinary tool use looks like. There is no
per-process accumulator for reaped children exposed by `ps` on either platform,
so no amount of care with the walk recovers it.

Two consequences worth knowing before trusting the number. A large child
exiting between two samples makes the tree counter go *backwards*;
`AgentCPUTracker` already treats a counter that moves backwards as a restarted
process and yields no rate, so the failure is a gap rather than a wrong figure
— the right failure, and another reason the meter can stay empty. And the
30-second gap between samples is itself part of the problem: the shorter the
window, the more likely a child is alive for both ends of it. Sampling the tree
twice a couple of seconds apart *inside* one probe run, and reporting the rate
rather than the counter, would measure what a session is doing now far better
than differencing a 30-second counter — one extra `ps` and a `sleep 2` in a
call that is already being made. Not built; see **Next**.

**A session's CPU figure measures the agent binary and nothing it starts, so
it is roughly a hundred times too small.** Measured on this Mac with a burner
child running under the agent process, over one thirty-second window:

    agent process alone      1.0% of a core
    agent + descendants    101.2% of a core

The probe matches `ps` lines containing `claude-code/`, which is the agent
itself — and an agent mostly waits on a model. Everything that actually costs
the machine is a child: `xcodebuild`, `git`, a test run, a `grep` over a large
tree. Three live sessions here measured 0.9–2.9% across three consecutive
windows while doing real work, and the figure barely moves whatever they are
doing, which makes it close to useless for the question it exists to answer —
*which session is making this machine hot*.

This is why the row meter never appeared. The threshold was blamed first and
lowered from 15% to 5%; that was worth doing and does not fix this, because
the number itself is wrong rather than merely small. See the item in **Next**.

**Validate the instrument, again — the first attempt at that measurement said
1.0% and 1.0%.** A pid-tree walk built an awk alternation from a list with a
trailing space, so the regex ended `|)$`, awk rejected it on the second
iteration, and the walk stopped one level down. It reported the tree as costing
exactly what the agent alone cost, which is a plausible-looking answer and the
opposite of the truth. The rewrite asserts that a known burner child is in the
set before trusting the total; that check is the only reason the second run can
be believed.

**A panel that answers a question nobody asked reads as a complaint.** The
destinations section shipped expanded, so the AI panel carried a standing list
of machines that could *not* take the work — and the first person to see it
read it as the app announcing that it now needed a repository on the other Mac
before it would run. Nothing of the kind is true: `isEligible` is consulted in
three places in the whole app and all three are a text colour or a sort order,
and monitoring has never depended on any of it. The section folds by default
now and its header asks the question — "Where add-secret could go" — rather
than listing the answers unbidden. Worth generalising: this app's readers take
anything permanently on screen as a statement about whether it is working.

**A pinned footer under `MetricDetailPane` does not work, and three attempts
say so.** The installed-agents block wants to stay in view while the sessions
scroll under it — on this Mac the AI pane has two dozen sessions, and anything
below them is as invisible as it was before there was anywhere to put it. Every
way of pinning it left the last line cut off by the window edge: stacked under
the pane in a `VStack`, with `layoutPriority` on the footer, and moved inside
the pane so its own `ScrollView` would yield (with `layoutPriority(-1)` on the
scroll view). Raising the window from 330 to 362 did not help either — the
clip moved with the window, so the scroll view grows to whatever it is given
and the overflow is constant. Three views have to agree about height here:
`MetricDetailPane`, the `maxHeight: .infinity, alignment: .top` frame around
`MachineMetricDetailContent`, and the fixed `dashboardContentSize` table. The
versions sit at the *top* of the scrolling list instead, which is visible on
arrival and cost nothing. Reopen only with a way to test the layout that is
cheaper than a build-and-look each time.

**Any build older than 0.1.33 will quietly drop `mayHostSessionsPreference` if
you run it.** Unknown keys do not fail a `Decodable`, so the older build reads
a machine carrying the new key perfectly well — and then re-encodes it without
the key the next time it persists. The `unreadableEntries` mechanism does not
help here, because it only carries through entries that fail to decode
*entirely*. Harmless, but do not debug a destination setting that "forgot
itself" after someone launched the copy in `/Applications`.

**CodexBar is read, not bundled and not recommended, and that is deliberate.**
Two decisions taken 18 August 2026 so they are not re-litigated. **Do not bundle
it:** it is `com.steipete.codexbar`, another developer's signed application, so
shipping it needs their permission whichever technical route is taken — nesting
keeps their signature and complicates notarisation, re-signing breaks it and
puts their build out under this name. Bundling would also not fix the fragility,
only transfer ownership of it, since the Claude figure is scraped from
`NSURLCache` internals that Apple does not document; and it would pin a pre-1.0
app that is still moving, giving anyone who already runs it two copies competing
for the same caches. **Do not push it in onboarding either:** usage is
enrichment rather than function, asking for a second menu-bar app before the
first has shown value is where people leave, and putting it in the flow would
make Little Herd the thing that vouched for an app it does not control. The
precedent to follow is the one already here — Full Disk Access is asked for at
the point it is needed, not up front.

What that leaves is `AIUsageAvailability`, which says which of four things is
true instead of returning `nil` for all of them, and makes every state that
cannot show a number offer the **provider's own** usage page. Not CodexBar's:
reading an app is not the same as recommending it. Note also that reading
another app's container is impossible under App Sandbox, so this design settles
the Mac App Store question — it is a Developer ID app, on purpose.

**Copying `~/.claude` to another machine resumes fine in the CLI — and is still
the wrong transport.** Researched 18 August 2026 in anthropics/claude-code#69585
(open): a user moved the whole directory to a new machine and `claude --resume`
listed all ~30 historical sessions with correct titles, timestamps, and
branches; two commenters confirm, one with ~50. So the docs' anti-duplicate
guard blocks a second copy on the *same* machine, not a cross-machine move.
Three things keep it from being our transport anyway. Every reported success is
same-username, same-path — this herd is `malpern` on the Air and `clawd` on the
mini, the project directory *name* encodes the absolute path, and every record
embeds a `cwd`. The desktop app indexes none of it: its sidebar trusts only the
`local_*.json` wrappers it wrote itself, and the community workaround is to mint
a fresh session and rewrite the old transcript's session id into it — surgery on
a format the vendor documents as internal and version-unstable, to produce
sessions the left rail cannot see. The summarisation handoff stands.

**Transcripts are durable; indexes are host-local. Never share the state
directory.** openai/codex#30957 (open): `CODEX_HOME` on NFS shared across
several hosts — the obvious shortcut for a herd — corrupts all four WAL sqlite
databases. The recovery path is the lesson: Codex rebuilds by rescanning the
JSONL rollouts, so the transcript is the record and the sqlite is a rebuildable
index. Claude Desktop's `local_*.json` wrappers are the same shape. Carry
transcripts if you must carry anything; never carry or share an index.

**`--teleport` is the vendors' own implementation of this design's shape.** A
real flag in 2.1.234, cloud→local only: it verifies you are in the right
repository, fetches and checks out the session's branch, loads the conversation,
and the terminal gets its *own copy* while the cloud session stays intact. Git
as transport, a repo check as precondition, copy-not-move semantics — the
transfer-branch design, shipped by Anthropic for the one direction they support.
No local↔local variant exists; that is the gap this project fills, in the same
shape, so if they ship one the designs converge rather than collide. Session
identity tied to the project path is their known root cause (#41630, auto-closed
by a bot, nothing committed); cross-device sync is open and unshipped on both
sides (#72578 stale; openai/codex#21803 filed 17 August).

**Codex's cloud is visible headlessly; Claude's is not — and listing survives
budget exhaustion.** Measured 18 August: `codex cloud list` from a
non-interactive ssh shell on the mini returned real tasks — title, `[READY]`,
repo, date, diff-presence — *while the account's usage limit was exhausted*,
because listing is not a model request. The whole loop exists non-interactively:
`list`, `status`, `diff`, and `apply`, the last being the vendor's own
cloud→local vehicle. The subcommand is marked EXPERIMENTAL and emits text, not
JSON — probe for it, parse defensively, never load-bearing. Claude has no
headless cloud listing: cloud sessions surface only through Remote
Control-connected sessions, and `--teleport`'s picker is interactive, though
`--teleport <id>` accepts a known session id. Separately and just as useful:
**`claude agents --json` is a sanctioned JSON listing of active local sessions,
and it answered over ssh where authentication does not work** — monitoring works
where hosting does not, so the AI panel gains a stable source for live sessions
to sit beside the fragile `.jsonl` history parsing it uses today.

**A machine addressed by a LAN-only name is indistinguishable from a dead one
the moment you leave the house.** Both of this herd's non-Mac-Air machines were
named this way and both read as "down" from off-site on 18 August while being
perfectly healthy — the mini had been up twelve days, the NAS eighty-seven.
`keypath-lab-mini` and `AlpernServer.local` are mDNS names, not tailnet ones;
the MagicDNS names are `mini` and `nas`. The trap is that this is invisible at
home, where mDNS answers and everything works.

Two details cost the most time. The ssh config carried a fallback meant to use
mDNS "when Tailscale is down", but its guard asked whether `keypath-lab-mini`
resolved — a name MagicDNS never served — so the condition was permanently true
and the fallback fired on *every* connection, working only because Bonjour
happened to catch it. And **Little Herd reaches Macs over ssh but the Synology
over HTTPS**, so repairing `ssh/config` fixed the mini and did nothing at all
for the NAS, whose hostname lives in the app's own configuration.

One consequence worth knowing before renaming anything: the app keys its DSM
password in the keychain as `user@host:port`, deliberately, so two NASes cannot
collide. Renaming the host therefore *signs it out* rather than breaking it —
the credential is orphaned, not wrong, and the fix is to sign in again.

**The innermost `.help` owns its region, so a terse tooltip on a small view
beats the fuller one on its parent.** The memory-pressure symbol carried
`.help(Text(level.title))` — the single word "Warning" — while the column
around it carried a sentence and the list of the heaviest apps. The symbol won,
everywhere they overlapped, which is exactly where a person aims. So the app
had measured which application was holding the memory, written it into a
tooltip, and shown it to nobody. Every surface is now handed one string built
in `MachinePresentation`, which is the only arrangement in which they cannot
disagree.

**macOS does not reclaim swap when the pressure passes, so `used` is a
high-water mark and not a reading.** Measured 25 August: `vm.swapusage` did not
move by a single decimal across a minute in which
`kern.memorystatus_vm_pressure_level` went 2 → 1 → 2. Eleven gigabytes were in
swap the whole time, from some earlier busy hour. Shown as-is it would put a
large permanent unactionable number in front of anyone whose Mac was ever busy,
so `SwapTrend` reports the *direction* — swap written across a window — and
says nothing at all the rest of the time, which is most of the time. Confirmed
in the running app: warning pressure, eleven gigabytes in swap, and the tooltip
does not mention swap, because none of it was written recently.

**Swap is read as a struct on a Mac and as two fields on Linux, and the units
are the trap on both.** `sysctlbyname("vm.swapusage")` returns `xsw_usage`
directly, so there is no `M`-or-`G` suffix to misparse — the string
`sysctl vm.swapusage` prints is for people. Linux takes `SwapTotal` and
`SwapFree` from `/proc/meminfo` in the probe already running, emitting **total
before used** so that `0 0` means no swap configured rather than swap that
happens to be empty. Those are different machines: a box with no swap does not
get slower under pressure, it kills something. Verified against the real Linux
box, which has 41.4 GB configured and none used. A remote Mac is not asked at
all and reads nothing, which is not zero either.

**A machine's pressure verdict is the kernel's only on a Mac.** Everywhere else
it is `MemoryPressureLevel.estimated`, computed here from the available
fraction — under a fifth is a warning, under a tenth is critical. Copy that
says "macOS is compressing and swapping" was therefore wrong in both halves on
a Linux box, and shipped that way for one commit. A Mac is quoted; everything
else is described as the observation it is.

**Little Herd cannot go in the Mac App Store, and this is settled rather than
untried.** The store requires the sandbox, and the sandbox is not a checkbox
here: a child process inherits it, so spawning `ssh` with the user's own
`~/.ssh` config and keys is out, and that is the entire product. So is reading
`~/.claude`, `~/.codex`, and CodexBar's caches, which is the AI panel and the
budget gauges. So is probing Full Disk Access through `TCC.db`. And Sparkle
cannot ship in a store app at all. The temporary-exception entitlements that
nominally cover home-relative paths are vestigial, and "let me read three other
vendors' private state directories" is not a request that gets granted. Even
granted, the result would be a monitor that cannot reach any machine but the
one it runs on. Developer ID plus notarisation is the mainstream path for
utilities of this shape, and `scripts/release` already does the whole of it.

**Killing the local end of an SSH connection does not stop the command on the
far side, and `ssh -tt` is what does.** Measured on the mini 25 August, because
a comment in this repo claimed cancellation and nobody had checked: SIGTERM to
the local client, and the remote loop was **still writing twenty-one seconds
later** and alive when asked. With a forced pseudo-terminal the same test ends
with the last remote write one second *before* the kill and the process gone.
The consequence for anything that starts work on another machine is the sharp
part — a probe that gives up leaves an agent running and spending the account's
budget, while the app reports that nothing happened. The terminal is given to
the authentication probe alone; the sampler runs long shell scripts whose
output a terminal would mangle, and it has nothing to cancel. It costs CRLF
line endings and ssh's parting "Connection to … closed.", both of which are
filtered because neither is the agent speaking.

**An agent's absolute path contains its version and the runtime moves it.**
`claude-code` went 2.1.237 → 2.1.241 during a single session on 25 August and
the old directory went with it, so a path measured minutes earlier was already
wrong. A cached install therefore goes stale silently, and the failure arrives
as an authentication error rather than a missing file unless something looks
for "No such file or directory" — which is why `AgentAuthProbe` does, and
reports it as an install to re-probe rather than an account to sign in to.

**An application bundle that resolves is not an application bundle with an
icon, and `NSWorkspace.icon(forFile:)` never admits it.** Claude rows in the AI
panel drew a blank grey square for months, and the comment above the lookup
blamed a static computed too early in launch. That was not it.
`com.anthropic.claude-code` *does* resolve — to the `claude.app` wrapper inside
Claude Code's support directory, which carries no `CFBundleIconFile` at all. So
reading the bundle rightly declined, `NSWorkspace` answered with the generic
application placeholder, and that is never empty, so the loop returned it and
never reached `com.anthropic.claudefordesktop` and its real icon. **One
identifier with no icon shadowed a good one purely by being listed first.** Ask
every candidate for a real icon before letting any of them answer with a
generic one. Found by drawing the icon at twenty-six points; at fifteen, behind
a hover, nobody had noticed in months.

**"The agent finished its turn" is not "the session is over", and the probe
treated them as the same.** A Claude transcript ending on
`stop_reason: end_turn` — which is every session between your messages — was
classified `completed`, regardless of how recently. That was survivable while
the panel had a Finished group to put it in. 0.1.40 removed the group, and a
session then vanished the moment it answered you, which is the exact moment
somebody looks at the panel. Reported from a screenshot showing "0 active"
beside a session that was visibly working.

A finished turn now reads as **waiting**, which is what it is — waiting for
your next message — and ages into `completed` after two hours. Two rather than
six, set by looking: six put ten rows in the waiting group, several of them
three hours old and one of them the same job twice, refilling a panel that had
just been made lean on purpose. Note the outer bound while reasoning about any
of this: `little_herd_recent_window_ms` is twelve hours, and a transcript older
than that is not reported at all — a first test of the aged case used thirty
hours, got nothing back, and was measuring the wrong window.

**A related sharp edge, not yet fixed.** The active window is two minutes of
transcript mtime, so a session running a single long tool call — a full test
run, a build — stops writing and drops out of `active` while it is working
hardest. Worth a look before anyone trusts the active count.

**A run that stopped mid-tool is not a run waiting for you, and conflating
them fills the panel with rows nobody can act on.** Measured on this herd:
**twenty-eight sessions share the title "Smirk daily snapshot"** — a scheduled
job names every run the same — and **fourteen of them ended inside a tool call
rather than on `end_turn`**. Every one of those read as *waiting*, sat in the
group meant for things that need a person, and could not be dismissed, resumed,
or acted on in any way. `AgentSessionState.stalled` now tells them apart: a
waiting session ended its turn and holds for your next message; a stalled one
was killed, crashed, or its machine slept. Stalled joins the finished pile —
counted in the header, not given a row.

Two things this explains that looked like display bugs. **One title appearing
twice in the panel, once active and once waiting, is two different sessions**,
not one row drawn twice — today's run of a routine and a previous one. And
Little Herd knows nothing about schedules: it reads transcript files, so a
routine is only ever "a lot of sessions with the same name".

**A home directory is not a project.** `lastMeaningfulComponent` answered
"Clawd" for `/Users/clawd`, so six sessions started in one account's home
produced six rows all named after the account the panel was already scoped to.
`projectName(fromWorkingDirectory:)` now returns nil for a two-component
`/Users/x` or `/home/x`, and the session parser substitutes "No project"
rather than dropping the session — which it used to do, because a nil project
name was a hard `guard`.

**Renaming a Claude session from outside it aims at the wrong store, and
Anthropic has declined to consolidate the stores.** Codex has a published
method — `thread/name/set` on its app server, which is what
`AgentRenamer` uses — and Claude has nothing equivalent. The obvious
workaround, appending a `custom-title` line to the transcript, is what the
community `/better-title` skill and `claude-sessions-mcp` both do, and it is
worse than unsupported:

- **The desktop sidebar does not read it.** Titles there come from the app's
  own store, `~/Library/Application Support/Claude/claude-code-sessions/…/
  local_<uuid>.json`, keyed by its own id with `cliSessionId` pointing back at
  the transcript. Checked on this Mac: 197 records, each with its own `title`.
- **Where it *is* read, it expires.** The session list scans only the last
  64 KB of a transcript for `customTitle`, so on a long session the entry is
  pushed out of the window and the title vanishes from `/resume`. Reported from
  the field on the issue below, and this session's own transcript is 38 MB.
- **The divergence is known and closed.** Issue #64304 documents at least three
  title stores that never reconcile and was closed as *not planned*.

**Watch [anthropics/claude-code#33165](https://github.com/anthropics/claude-code/issues/33165)**
— "Allow Claude to rename its own session (programmatic session rename API)",
open, the live thread. What matters is not a rename API in the abstract but a
**single authoritative title store**, or the separate index file that issue
proposes instead of tail-scanning. Until one lands, any implementation aims at
a moving target.

    gh api repos/anthropics/claude-code/issues/33165 --jq '[.number,.state,.title]|@tsv'

Native subscription needs a scope this token does not have; `gh auth refresh -h
github.com -s notifications` once, then subscribing, would do it hands-free.

**An empty `MachineAgentPad` rendered nothing at all, and the code looked
right.** `EmptyView` produces no layout and silently discards the frame
modifiers applied to it, so a pad with no token on it had no size — which meant
that during a drag the machines with *nothing running*, the most interesting
answer to "where could this go", were the only ones that drew no target. A
`Color.clear` behind the content fixes it. Nothing in the source hinted at this;
a render did, after three passes of re-reading correct-looking conditions.

**`DragGesture`'s `location` is in the dragged view's own coordinate space, not
the screen's.** Hit-testing which column a token is over used it as though it
were a displacement, so a token sitting perfectly still already read as twenty
points along and the column under the pointer disagreed with the column being
offered for the entire gesture. Use `translation`, which is the same quantity in
every coordinate space. `HerdColumns` now owns that arithmetic and is tested.

**`withAnimation` around a drag's release is the classic source of a jump.** It
animates *toward* a target that the next gesture immediately overwrites, so a
token grabbed again while it is still springing home snaps. An implicit
`.animation(_:value:)` on the offset retargets from the on-screen value instead,
which is what interruptibility actually means.

**A dashed edge means "something could go here", so a refusal must not have
one.** The first pass gave `available` and `refused` the same dashed grey
silhouette and tried to separate them with fill opacity. The two states a person
most needs to tell apart looked like the same box, and no colour tuning fixes
that while the shape still says yes.

**A `.help` string was the wrong container for the most interesting thing on
the dashboard.** A tooltip is one run of plain text, so a session's name and
what it is doing had to be flattened into one line at one weight, several
sessions became a bulleted list nobody could scan, and macOS decided when it
appeared. `MachineAgentCard` is a real view in a popover instead. Its hover
timing is deliberately asymmetric — a delay in, none out — because a matching
delay on the way out parks a card over the machine you were reaching for.

**A view that lays out columns from a hard-coded window width goes on carving
up the old window after the window grows.** `CPUOverviewView` divided a literal
`300`; widening the window to 324 would have left the right margin twice the
left, and nothing would have failed. Its width is a parameter now.

**Opening a machine's AI page takes two changes, not one.** The machine detail
screens are lensed through whichever overview metric is current, so setting
`selection = .machineMetric(id)` alone lands on a page about CPU. `showAgents`
moves the lens as well, and is tested from another machine's page — the case
that would break if it only nudged the metric.

**Sizing a window for its content is arithmetic, and the extra height all lands
in one place.** `CPUOverviewView` fills its frame with `.top` alignment, so
every point added to the window's height becomes a gap under the pads rather
than being shared out. The first guess added 32 points and left a visible
trough; the answer was the amount the pads actually cost minus the slack that
was already there.

**A feature can ship, pass its whole suite, and fire never.** The arrival
announcement was guarded on the dashboard being the *focused* window at the
instant a session began. Sessions are started from a terminal, so it never was
— from outside, indistinguishable from nothing having shipped, and the user
said so. Worse, the guard sat *before* the watch, so while unfocused the
arrival was not even recorded: the bookkeeping that tells a new session from
one already passed over was gated on somebody happening to be looking.
**Presentation guards go after the bookkeeping, never in front of it.** Every
test passed throughout, because every test was about the watch and none was
about when the view is allowed to speak.

**A `Binding` whose getter reads two sources and whose setter writes one cannot
be dismissed.** The card was presented on `isHovering || announcing != nil`
while dismissal cleared only the first, so clicking away did nothing until the
timer ran out. Both reasons are one value now (`AgentCardVisibility`), and
letting go clears whichever it was.

**Swift does not warn about an unused `private` type.** 139 lines of hover-row
views survived the removal of the hovered headers with zero callers and a clean
build. Nothing but a deliberate search finds these — the same blind spot that
let `HoveredMachineMetricHeader` sit unwired from the first public commit.

**A grep that returns zero uses may mean the thing does not exist.** A review
here reported dead code that was never written: the count was zero because the
name matched nothing at all, and it read as "declared and unreferenced". Check
that a symbol exists before reporting it as unused.

**The window draws under its own titlebar, and SwiftUI still insets the content
by 32 points.** Both are true at once, which is the trap: `fullSizeContentView`
makes the frame height equal the content height, so nothing in the window code
adds a titlebar — and the view inside is pushed down regardless, with whatever
does not fit cut off the bottom. It has clipped this dashboard twice, first
taking the machine names off the overview and then the metric tabs. It is
`DashboardMetrics.titlebarInset` now, and the overview's height is written as
its content plus that band.

**`ImageRenderer` has no safe area, so a render can fit perfectly while the
window clips.** That is how the tabs shipped cut in half: the height was
measured from a picture that could not lose the 32 points the window loses. The
composite render applies the inset itself now. **A render is a model of the
window, not the window.**

**A size that was arrived at by looking at the running app already contains the
band.** Adding the inset to the two machine screens would have made them both
32 points too tall — the same mistake in the opposite direction, avoided only
because their provenance was written down.

**`str.replace` on a pattern that no longer matches is a silent no-op.** An
edit to hide the agent tokens did nothing at all, because a refactor had
renamed the property it matched on, and the build stayed green because the code
was untouched. The render caught it. **Assert the match before editing.**

**A locally built Release is not a substitute for a release, and it fails in a
way that shows nothing.** Xcode ad-hoc signs a local Release build, but the
vendored Sparkle framework keeps its Developer ID team signature — and dyld
refuses to map a framework whose team differs from the process, so the app dies
during launch with no window, no alert and no console output the user would
see. The crash report says `Library not loaded: @rpath/Sparkle.framework`, with
the real reason buried at the end of a long "tried:" list: *different Team
IDs*. Re-signing the framework, its XPC services, the updater and the app
ad-hoc makes it launch, and breaks Sparkle for good — an ad-hoc build cannot
validate the feed's artefacts. **To put a build on a machine, cut a release.**

**`scripts/release` can fail spuriously at the Gatekeeper check, and takes the
evidence with it.** A run notarized *Accepted*, then died on
`spctl -a -t install` not reporting `source=Notarized Developer ID`; the same
command against the previously published build passed, which ruled out the
check being wrong on this OS. Re-running with identical inputs succeeded. The
work directory is cleaned up on failure, so diagnosis after the fact is not
possible — **before assuming an artefact is bad, test the check against the
last good release, then simply run it again.** A half-run also leaves
`LittleHerd/Info.plist` stamped at the new version, which the next run's
preflight rejects as a dirty tree: `git checkout` it first.

**A deck stacked squarely behind an animal has no depth, and there was nowhere
for it to peek.** Two things the sketches could not show, because in a sketch
nothing is behind anything and there is always space above. Squared up, the
animal hides every card but the top one and one session looks like four — the
cards have to lean. And the thermometer runs down to the animal's head, so the
first build sat the deck on the lowest blocks, the ones that are always lit;
the bars now give up that clearance for every machine, so they stay one height
across the herd.

**A fan cannot live inside the column it belongs to.** A column is sixty-odd
points and a fan of six is most of the window, so drawn inside one it is
clipped by its own machine and the arithmetic that keeps it on screen has
nothing to measure against. It is an overlay on the herd — which is also the
only place that knows which machine is being pointed at, and so the only place
that can dim the others.

**A raised deck has to hide its resting copy.** Obvious once seen and invisible
until then: the first build drew both, so the same agent appeared twice, once
peeking and once above. The deck *is* what rose.

**Hover does not fire in this app unless its window is active.** Twice working
hover looked broken under synthetic events because the window had not been
clicked first. Click, then move, before concluding an `onHover` is wrong.

**A session was moved between machines by hand, and it worked.** Transfer spike
1, 27 August: a brief written on the Air, carried on a branch, picked up by a
successor started non-interactively on the mini, completed, verified, committed
and pushed back with no person in the loop. The brief is kept at
`Documentation/transfers/spike-1.md` and the work it produced is in `main`.
Three of the design's assumptions now have evidence rather than argument.

**A written brief is enough.** No transcript, no serialised session: the
successor read one markdown file, found the right test file, matched the shape
of an existing test and wrote a correct one — and its commit message is in this
codebase's voice because the brief told it to read `git log` first. This is the
bet the whole design rests on and it holds.

**But delivery is gated by permissions, and the gate is invisible until you hit
it.** Started with `--permission-mode acceptEdits`, the successor did the work
and then could not finish: every form of `xcodebuild test`, and `git add`,
`git log`, even `/bin/ls`, returned "requires approval", while reads were
allowed and no interactive approver existed. It stalled having silently done
the work. **A successor must be started with permission to build, test and
push, or the move cannot complete** — and a transfer feature that starts them
the obvious way will look like a hang. Re-run with `bypassPermissions` it
finished in one turn, which is a decision the design has to make deliberately:
that flag is an agent running unrestricted commands on another machine.

**Two smaller things the spike measured.** The mini has no `timeout` binary —
zsh with no coreutils — so any wrapper shelling out with one fails there. And
`/opt/homebrew/bin/codex` is broken under a non-interactive shell
(`env: node: No such file`) while `~/.local/bin/codex` works, which is the
"absolute paths, never the PATH" rule the app already follows, confirmed again.

**SwiftUI's `.contextMenu` throws away icons on macOS.** It takes a `Label`
with an image, compiles, and the system draws text only — so the animal never
appeared in a machine's menu and neither did the symbols beside SSH and Screen
Sharing. The build was green and the source read correctly, which is the worst
combination: a context menu is not drawn until it is opened, so the render
harness could not have caught it either. It was found by somebody opening the
menu and photographing it. Both menus are built in AppKit now, and the SwiftUI
versions were deleted rather than left beside them — two descriptions of one
menu is how the fan and the resting deck came to disagree earlier the same
evening, and here the dead one is the one that reads correctly.

**`NSMenuItem.image` then drew nothing either, and the answer was to stop using
it.** A unit test builds the same menu the view builds and confirms every animal
and symbol resolves and that the items carry them — so the images were set and
something between there and the screen discarded them. Rather than keep guessing
at why, the icon also goes into the title as a text attachment, which is drawn
as part of the string and does render. The image slot is still set, harmlessly,
in case it starts working.

**An AppKit layer over the herd will take the mouse from the SwiftUI views
underneath, and what is underneath is the agent drag.** The host view claims
right-clicks and nothing else: `hitTest` reads the event being dispatched and
returns `nil` for anything that is not one. Verified by hand — the icons are
there *and* an agent still drags between machines — because a layering change
had already broken the drag once that evening.

**A machine with agents had no context menu at all, and a machine without one
did.** The fan's hover column spans its animal on purpose, so that reaching for
a card does not lose the pointer; that column is therefore the view a
right-click over the animal lands on, above the machine's own overlay. A machine
with no agents draws no fan, so it worked — the machine most worth
right-clicking was the only one that could not be. **A bug that spares the empty
case is a bug that will be found by a user**, because the empty case is what a
developer tests with.

**A progress bar has to be weighted by how long each step takes, not by how many
there are.** Six equal segments put the fill at a third for the whole of the
agent's work — often most of a transfer, sometimes half an hour of it — then
run through the last four in a moment. A bar that stands still for thirty
minutes and then leaps looks stuck at exactly the point the thing is working
hardest. The weights are deliberately rough and the tests assert the *shape* —
the agent and the tests own most of the width, the bookkeeping either side is a
sliver — rather than the numbers.

**These icons carry their own padding, so the frame's edge is not the art's
edge.** A bar aligned to the bottom of the frame straddled the card instead of
sitting on it. Found by drawing it over stand-in blocks rather than by reasoning
about it, which is also how its first position — floating above the card, over
whatever thermometer segment happened to be behind — was found to be wrong.

**A diff of transferred work must start at the commit the source pushed, not at
the branch's parent.** The branch carries the departure too — the brief, and
whatever was uncommitted when the session left — so diffing from the parent
presents all of that as the agent's work. It is read on the machine the work
came *from*, with local git: that machine has the repository and is where
somebody is sitting, and the destination may be asleep by the time anybody
looks. `--numstat` rather than `--stat`, because the latter draws a bar chart
that would have to be un-drawn to get the numbers back — and, verified against
real git rather than remembered, a path with spaces survives while a binary file
comes back as `-\t-\tpath` and must not be read as zero lines changed.

**A control whose backend you do not want firing yet can still be used, and
should be.** A drop in a development build walks a transfer through its phases
on a timer: no runner, no connection, nothing pushed, compiled out of Release
rather than switched off in it. Successive rehearsals end differently on purpose
— landing, then a red check, then an agent that gave up — because an interface
that always succeeds only ever shows the easy state. The test hands the
coordinator a runner that fails outright if it is ever called, so a rehearsal
that quietly began doing something real would not pass. **This is the honest
alternative to judging a live control from a screenshot of it.**

**An indeterminate `ProgressView` renders as a prohibition sign under
`ImageRenderer`** and is an ordinary spinner in the app. One more thing the
harness cannot draw; the transfer strip's five states were drawn there and that
one was checked live.

**`-only-testing` with a bare Swift Testing function name runs nothing and
reports success.** `-only-testing:LittleHerdTests/SuiteName/testName` matches no
`@Test` — the parentheses are part of the identifier — and `xcodebuild` then
exits `** TEST SUCCEEDED **` having executed zero tests. Three mutation runs
"passed" this way on 3 September, including one against a canary that returned
a fixed string before running anything at all, which is how it was caught.
**Filter at the suite level, or read the ✔ lines** — a run that names no test is
a run that did nothing. The suite-level form (`…/AgentAuthVerifierTests`) works.

**A new source file is invisible until `xcodegen` runs, and the error blames the
wrong file.** `project.yml` globs `LittleHerd` and `LittleHerdTests` while the
generated `LittleHerd.xcodeproj` is checked in, so a branch that adds a file
without regenerating compiles for its author — whose Xcode regenerated locally —
and for nobody else. It surfaces as `Cannot find <NewType> in scope`, pointed at
the file that *uses* the type rather than the one that is missing, which reads
like a typo or a missing import. PR #1 sat as a draft in this state.

**Some bugs cannot reproduce inside the test runner, and a test written for the
symptom will pass for ever.** The verifier closes standard input because an
agent that finds an open one waits on it. Two attempts to test that passed with
the behaviour deleted: timing the call proves nothing because a runner's stdin is
already at EOF, and asking the child whether it sees the null device proves
nothing because `xcodebuild` hands the *test process* `/dev/null` too — so
inheriting and setting are the same descriptor. The test only became real once it
put a pipe on descriptor 0 for the duration of the call. **When the environment
already satisfies the property, assert against an environment that does not.**

**A view rendered below its own declared minimum silently loses the part that
overflows.** `TransferDiffView` declares `.frame(minHeight: 420)` and two new
failure states were drawn at 300, which put the entire header — title, the
sentence saying what became of the work, and the branch name — off the top of
the image, leaving a page that looked deliberately sparse rather than clipped.
Nothing failed; the harness wrote a PNG and reported success. **Render at the
size the view asks for**, and when a render looks emptier than the code reads,
suspect the frame before the content.

**A test can encode the bug it is standing next to.** `TransferStripTests`
required `couldNotStart`'s detail to contain "nothing was changed" — which is
true of one of that result's three causes and false of the two that leave work
on a branch. Fixing the sentence turned the suite red, and the correct response
was to change the assertion, not the sentence. Worth pausing on whenever a
green suite resists a change that is obviously right: **the test may be
asserting the defect.** It now checks that the other two states do *not* say it.

## Method notes

**Subagents in worktrees branch from what is pushed, not from what is in front
of you.** Two agents split the review work on disjoint files, and both worktrees
were cut from the last release commit rather than from local `HEAD` — so a
change committed minutes earlier was absent from both, and merging their work
nearly reverted it. It surfaced only because the merged file was diffed against
the pre-split original rather than eyeballed. **Diff the merge, and check your
own recent commits survived it.**

**Four bugs in one afternoon, none of them findable by the suite, all of them
found by asking what the code did to another machine.** Stdin inherited instead
of closed, so a remote agent sat waiting on an EOF that never came. No watchdog,
so one probe held a test for ten minutes. Silence read as a refusal, so a killed
process looked like a signed-out account. And a cancellation that cancelled
nothing. The pattern is worth naming: **every one of them lived in the layer
that talks to the outside world, and that layer had no tests** — the pure logic
beside it was covered, verified by breaking it, and correct throughout.

**A fixture can lie twice in one day, and it looks exactly like a bug in the
code.** Both times a render was missing something, the first instinct was to
change the view, and both times the view was right. Once the growth evidence
could not survive `apply`, which recomputes it; once the callback had been
given to the folded fixture rather than the expanded one. Before editing a view
because a render is missing something, check that the fixture asked for it.


**Verify the instrument before believing it, again — this time the instrument
was a mouse.** Synthetic hovering produced the tooltip once and then stopped
producing it at all, through a fresh launch and the identical sequence. Nothing
was wrong with the app: printing the string showed it correct and non-empty.
Reading **`AXHelp` off the live accessibility tree** settles it in one command,
is the same text macOS shows, and can be read for every machine at once —
`AXUIElementCreateApplication(pid)` and walk the children. Prefer it to
screenshotting a tooltip. SwiftUI's `.onHover` is a different mechanism and
does respond to synthetic movement, so the hovered header could be checked the
ordinary way.

**A fixture can lie about the thing it is fixing.** The first render of the
hovered memory header came out with no leak dot beside the application that was
climbing, and the layout looked guilty because an icon had just been added to
that row. The dot was moved and a justification written for why its new place
was better. It was the fixture: `MachineMonitorModel.apply` **recomputes**
growth evidence from `MemoryGrowthDetector`'s own history, so a single snapshot
cannot carry one however plainly it is written in. Feed it a real climb —
eight samples across 105 seconds, since the detector wants 90 seconds and seven
readings — and the dot is there, and always was. A layout was very nearly
rearranged to fix a bug in a test, with a plausible reason attached.

**Dead code is invisible to every other rule in this file.**
`HoveredMachineMetricHeader` had no call site from the first public commit
until 25 August. Nothing rendered it, so nothing checked it, so it quietly kept
a convention the rest of the app had abandoned: its CPU rows still reported
cores (`0.5c`) long after every other surface moved to a share of the whole
machine. Wiring it up is what exposed that. Before adding a surface, check
whether one was already built and forgotten.


**Look at it.** Four times in one session something obviously correct on paper
was wrong when run — and every UI defect (a folder named `Library` rendered as
`L`, no disclosure triangle, a spinner that never moved) was invisible to 263
passing tests.

**Two menu-bar icons are indistinguishable, so "kill stray instances first" is
not tidiness.** A fixed build was launched beside the installed one and the
report came back that the bug was still there — with a real TLS error, from a
real app, in the log. It took attributing the failure to a PID to see that
every one of them came from the *other* copy, which had no fix in it and looked
exactly the same in the menu bar. Testing a build that is not the only one
running is testing nothing, and the person clicking cannot be expected to tell
them apart. Quit everything, launch one, and say which one is up.

**Validate the instrument before believing what it says.** Silence from an
`NSLog` added to a delegate read as proof the delegate was never called; the
instrumentation had silently vanished from the source, so the silence proved
nothing, and the delegate had been running correctly the whole time. Note also
that `grep` and `strings` on the built binary find *none* of its known string
literals, so neither can tell you whether a build contains a change — check by
running the build, not by reading it.

**Render it and open the file.** `PanelRenderHarness` exists so that "look at
it" costs one test run instead of a launch, a menu click, and a screenshot that
cannot see a menu-bar window. It caught itself before it caught anything else:
the first version wrapped the panel's real `ScrollView` and lazy stack, neither
of which `ImageRenderer` lays out, so it wrote a blank image and passed. Both
are why the rows now live in `AIAgentPanelContent` and the stack is eager.

**Break the test to prove it works.** Every substantive rule was verified by
reintroducing the bug and watching the suite fail. Two tests that passed without
proving anything were caught this way: one watched a side effect a killed shell
would not perform, another counted processes with a command containing the
pattern it grepped for.

A third joined them on 19 August, and it is the subtlest of the three. A test
named "an unmeasured machine is not called idle" **passed with that rule
deleted**, because an optional unwrap a few lines further down produced the same
answer by accident — two machines were not enough to tell the implementations
apart, and it took a third to separate them. Note what the real rule was
preventing: not a false claim but a *false silence*, a true and useful sentence
withheld because an unmeasured machine sorted below a real one. Absence of
output is the hardest failure to write a test against, and the easiest to
mistake for correctness.

**A guard that cannot bind is not a safeguard.** The same hour produced a
"is the gap wide enough" rule that could never fire: the two thresholds it sat
behind already guaranteed a gap half again as large. It read like caution and
was dead code, and only writing a test for it made that visible. Deleted rather
than kept, because a condition nobody can trigger still has to be understood by
everyone who reads it.

**A test that measures the machine is not testing your code.** The cancellation
test above counted every `sleep` on this Mac and compared the total before and
after, so its result depended on whatever else happened to be running, and it
allowed the kill a fixed two seconds. It failed a release on a loaded machine
and passed four quiet runs of the same commit — the worst possible signal, since
the obvious reading is that the code is broken. Watching only its own child (a
sleep of a duration nothing else would use) and waiting for the process to go
rather than assuming how long that takes fixed both halves, and made it ten
times faster as a side effect: nothing sleeps two seconds to see what happened.

The same test also has to prove its subject existed. The version before this one
would have passed had the process never spawned at all — which is the fourth
variant of that mistake this one test has produced, and they are all recorded
above it in the source.

**Commit early.** A worktree was deleted mid-session with uncommitted work in
it; the files survived only because the directory had not been reaped yet.

## Next

**The website promises "Put your herd to work", and on 29 August the hedge
came off it.** The hero used to carry the clause *"Little Herd watches;
choosing the machine is still yours"*, which this file called load-bearing and
told nobody to trim. It is gone, deliberately: every verb in the hero is
present tense and it says *move work to the machine that's free* outright.
**That is a promise the code can keep and the shipped build does not**, because
`DashboardChrome.startsTransfers` is `false`. Either that word changes or the
sentence has to come back — and the first is the right answer, because the
three things the flag was waiting for all exist now.

The three items that were the critical path are essentially closed, and what
replaced them is one decision and its consequences:

- **Item 1, the tokens and their drag.** Done. `showsAgentTokens` is on, the
  deck has been watched and tuned, and the carry reports an accepted drop.
- **Item 4, what a destination has to be asked.** Done, all three parts: the
  account-level answer (`sshUser`), the setter (the per-machine allowance on
  the AI page), and the grant bound to a host. What remains under it is several
  accounts on one host, which is a model change rather than a gap.
- **Item 5, the transfer itself.** Built, run end to end on real machines, and
  wired to the drop. What is left is turning it on, and the interface work that
  turning it on makes urgent.

The fourth is **done as of 3 September: a session that fails to arrive says
so, and says where it got to.** It turned out to be a sentence rather than a
mechanism. `couldNotStart` read *"It never started, so nothing was changed
anywhere"* for all three of its causes, and one of those is a departure that
fully succeeded with the destination refused — while the diff window prints
that line directly above the branch name, so it denied that anything had
happened above the evidence that it had. `agentFailed` ended *"Nothing was
pushed"*, false for the same reason: the departure pushes before the agent is
asked for anything.

`TransferRemnant` now carries what survives on the source, derived by
`TransferPilot.Failure` from its own case, because where a run stopped is what
decides it: the branch is created by the last command of the capture chain, so
anything at or before it made nothing, a failed push leaves a branch on one
machine, and every later failure is looking at a branch that is already out.
The window draws the branch name only when there is a branch — it is selectable
text somebody will paste into a shell.

**The source session was never at risk and still is not.** Nothing in a
transfer retires it, so "leave you where you started" already held for the
session itself; the branch was the only part that varied, which is why it is
the only part drawn.

1. ~~The agents' design, and judging how it feels.~~ **Done.** Built in
   `v0.1.55` and tuned by watching it since; what the watching taught is in the
   facts. The numbering below is the file's rather than a priority, so this
   entry stays as a marker instead of renumbering everything that points at it.

2. **P-core/E-core awareness is blocked, not pending.** Per-core utilisation
   needs root on a remote Mac — `powermetrics` refuses without it, and neither
   `top` nor `iostat` exposes per-core lines. It would work on this Mac and no
   other, which in an app about a herd is an inconsistency rather than a
   feature. Reopen only if a way to get it without root appears.
3. **Say once, at herd level, that names are not resolving — but not yet.**
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

   **A first real case arrived on 1 September, and it argues for different
   wording rather than for building this.** The mini's Tailscale tunnel stopped
   while the machine stayed powered on, logged in, and answering ssh on the LAN.
   Little Herd reported it offline for a day and was right to: its probe genuinely
   could not reach it, because the app addressed the machine by a tailnet name and
   the laptop's ssh fallback to the LAN was guarded on whether that name
   *resolved* — and MagicDNS keeps serving the address of a node that has been
   offline for days. Fixed in `dotfiles`, not here.

   **What is ours is the sentence.** The classification was right — `.noAnswer`,
   since the name resolved and nothing replied — but its detail reads *"Likely
   asleep or off the network"*, and the machine was neither. It was awake, on the
   network, and reachable at a different address. That is a confident wrong
   diagnosis rather than an unhelpful one, and it sent the question to a person
   rather than answering it. Worth rewording to name what was observed instead of
   guessing at the cause; **do not add a reachability sweep to make the guess
   better**, because probing every other route to a machine is a fair amount of
   work to improve one tooltip, and this app already declines to enumerate
   volumes for a smaller reason.
4. **Destination eligibility is measured, and it has a caller now.**
   Every account reports which agents it can run and where, and which
   repositories it has checked out keyed by the origin remote's slug.
   `DestinationEligibility` answers with one of six things, `AgentAuthProbe`
   and `AgentAuthVerifier` can ask a provider whether it will actually answer,
   and `MachineConfiguration.mayHostSessions` records intent.

   **The two surfaces that showed all this were removed on 25 August, and what
   replaced them is not a redraw of either.** A checkbox in Settings and a
   Destinations section in the AI panel were a permission and a placement
   decision for a move that could not happen. What draws the eligibility now is
   the thing it was written for: `AgentDropEligibility` answers the drag, so a
   machine that could not take the work does not lift to meet you, and **Move
   To** on an agent card lists every machine with the unable ones greyed and
   the reason beside them. That last is the part a drag cannot do — a drag
   refuses in silence, which had somebody asking whether transfers were
   switched on at all.

   **The permission has a setter again, and it ships with its own switch.**
   `MachineDestinationAllowance` on a machine's AI page is the one control that
   makes "ask before a machine can take work" usable, and it is drawn only when
   that setting is on. The two arrive together on purpose: `mayHostSessions`
   defaults to *off*, so turning the setting on while nothing could set it
   would refuse the whole herd with no way back — a default outliving its
   control. Note also that the toggle writes through to the store rather than
   to the model, because the model's own setter changes memory and nothing
   else, and a permission forgotten on the next launch is the one failure a
   permission must not have.

   **Asking at all is off by default, and that is an accident boundary rather
   than a security one.** With `requiresDestinationApproval` off — the shipped
   default — `mayHostSessions` is not consulted and any machine that *could*
   run the work will take it. Little Herd reaches these machines over the
   user's own SSH keys, so a transfer starts nothing they could not start from
   a shell themselves.

   **What is genuinely still unwired is `DestinationRoster`**, which nothing
   outside its own file mentions: every caller assembles its own
   `[DestinationAccount]` from the machines it already has. That is the state
   `HoveredMachineMetricHeader` was in for months before anybody noticed, so it
   is written down here rather than left to be rediscovered — either something
   uses it or it goes.

   **Budget is not one of the reasons.** The machines share one account, so an
   exhausted limit cannot be escaped by choosing a different destination —
   check it once, before offering a move at all. **The NAS is never a
   destination here**: DSM restricts shell access to administrators, the login
   shell is `/bin/sh`, and there is no package manager. It reads "not measured"
   rather than "no agent", because Little Herd runs no probe on it and never
   asking is not the same as being told no.

   **The grant is bound to a host now, and that half is done.** A permission
   used to be keyed on `MachineID` alone — minted at discovery and never
   changing — while `hostname` beside it is an ordinary editable field, so an
   entry re-pointed at another box carried an approval given to the old one.
   The host it was granted for is recorded, a mismatch reads as not permitted,
   and a grant made before this existed is honoured as it stands, because
   invalidating every permission somebody already gave would be a worse answer
   than trusting them.

   **The account is done.** `MachineConfiguration` carries an optional
   `sshUser`, and `sshDestination` composes it with the hostname wherever the
   app talks to a machine — one place, because several call sites and one of
   them forgetting is a machine sampled as the wrong account without saying so.
   A configuration with no account recorded still means what it always meant,
   so nothing already saved changed.

   Two parts were easy to miss and both were needed for the field to be worth
   anything. **The store deduplicated on hostname alone**, so the mini's second
   account could never be added — the field would have existed and been
   unusable by exactly the person who wanted it; it matches on host *and*
   account now. And **the composed destination still has to pass
   `SSHHostName`**, which exists because a name starting with a dash is read by
   `ssh` as an option: a hostile account name is refused rather than sent.

   This is what made a drag onto the mini refuse for want of a checkout that
   was sitting on the machine the whole time — under `malpern`, while Little
   Herd was looking at `clawd`.

   **The next piece is several accounts on one machine, and listing the host
   twice is not it.** Adding the mini a second time works and was tried: two
   entries, two animals, two sets of eligibility. It is wrong on three tabs out
   of four. CPU, memory and disk belong to the **host** — two entries read the
   same silicon twice, count the same memory pressure twice, and make the
   header say five machines where there are four. Only the AI tab benefits,
   because sessions, agents, checkouts and credentials are the things that are
   genuinely per-account.

   So the model is one machine per host, with accounts as a property of it:

   - **Metrics are sampled once**, from whichever account can reach the host.
   - **Sessions are sampled per account and merged**, each tagged with the
     account it belongs to, so one animal's deck can carry agents from several
     logins — which is what the machine is actually doing.
   - **Eligibility asks whether *any* account here has the checkout**, and the
     transfer picks that account rather than making somebody choose the right
     animal.
   - **A transfer targets a machine *and* an account.** `Transfer` and
     `TransferAssembly` both grow a field.

   The cost is honest: the sampler runs one shell script that does metrics and
   sessions together, so the session half has to become per-account while the
   metrics half stays single — and that script is the part where a mistake
   makes a machine read as down. A day rather than an afternoon.

   The `crab-mini` avatar was added for the two-entry version and is kept: it
   is the right icon the day a machine needs distinguishing for a reason that
   is not an addressing bug.

   **Cloning a missing repository is deliberately not the answer to that, and
   is worth having later.** When a destination genuinely lacks the repository,
   the tempting fix is to have the drag clone it. Rejected as an automatic
   step: a clone is minutes and gigabytes on somebody else's disk, chooses a
   location nobody was asked about, needs credentials there for a private
   repository, and turns a small gesture into machine setup. Worse, it would
   have hidden the bug above by making a *second* copy of a repository that
   already existed.

   The shape worth building, when it is wanted: the refusal becomes an offer —
   "Mini does not have little-herd — set it up?" — confirmed once, with the
   destination path visible, after which drags to that machine simply work.
   An offer, never a side effect.

5. **Transfer a session between machines, at the session level.** **A spike
   has now done this by hand — see the facts above — so the open questions are
   narrower than they were.**

   **Read this before building any of it: the shape the spike used is unsafe,
   and it is the obvious shape.** The successor was told *"read this file and
   carry out the work it describes"*, and then given permission to run
   anything. That converts repository content into commands on another machine,
   which moves the trust boundary from *who can ssh to my machines* to *what is
   in a branch* — and not only the brief, since a successor reads `CLAUDE.md`,
   source comments and fixtures while working. Anyone who can write to the
   repository can run commands on every machine that starts a successor. On a
   private repo with one writer that is theoretical; as a shipped feature it is
   the whole security model.

   Six constraints, each answering a specific way the spike could have been
   turned against the herd. **Two of them carry most of the weight — never
   auto-merging, and bounding what a successor may run — because those survive
   the cases the others do not cover.**

   - **No `bypassPermissions` in the product.** The default (`acceptEdits`) is
     too tight to finish a move and the bypass is too loose to ship; the
     product has to define the middle — the build command, and `git` limited to
     the transfer branch.
   - **The brief carries data; Little Herd supplies the imperatives.** A fixed
     schema — task, repository, branch, verification command — rendered into a
     prompt the app owns, rather than prose a successor is told to obey.
   - **Authenticate the brief with git's own SSH commit signing**, so a pushed
     branch is not automatically an instruction. `gpg.format=ssh`, sign the
     commit that introduces the brief, verify it on the destination against an
     allowed-signers file. Every machine already has a per-link ssh key and a
     documented way to distribute one, so this needs no new secret and no new
     format — a bespoke HMAC would mean another key in sops and another thing
     to get wrong.

     **The launcher verifies, not the agent.** This inversion is the whole
     difference between security and the appearance of it: a successor asked to
     check its own brief will be told by an unsigned brief not to bother, and
     will comply, because the file *is* the instruction. Verification happens
     before the agent starts and an unverified brief means it never starts.

     **And signing alone is the trap.** It answers *who wrote this* and answers
     it well; it says nothing about *what this can do*. It does not cover the
     repository the successor reads while working — `CLAUDE.md`, source
     comments, fixtures, none of which are in the brief — it authenticates
     origin rather than intent, so a compromised source machine signs hostile
     briefs perfectly, and a signed brief can still simply be wrong, which is
     the likelier failure. It is also the control that most resembles security
     from a distance, which makes it the one most likely to be shipped by
     itself. The two below are worth more.
   - **The brief must be asked for as prose, not as instructions.** What a
     departing session writes is read by the successor as data, so a handoff
     phrased as commands would be an injection written by your own session —
     the one source nobody would think to distrust.
     `TransferDeparture.briefRequest` therefore asks for a *description of
     work* and says why. It also asks specifically for what the diff cannot
     show: what was tried and abandoned, what looked right and was not. That
     is the part of a session that dies with it, and carrying it is the point
     of the whole feature.

   - **A session's project directory is the resolved path.** The transcript
     for a session started in `/tmp/resume-test` lives under
     `~/.claude/projects/-private-tmp-resume-test`. Anything deriving a
     session from a working directory has to resolve symlinks first.

   - **`--disallowedTools` is variadic and ate the prompt.** The first real
     transfer failed instantly with *"Input must be provided either through
     stdin or as a prompt argument"* — the flag consumed `Bash`, `WebFetch`,
     `WebSearch` **and** the trailing prompt, leaving no positional argument.
     Reordering only moves the problem to whatever ends up last, so the prompt
     now goes in on **standard input**, which is better anyway: the brief is
     off the command line entirely, a stronger form of what the base64 staging
     was reaching for. A pipe also reaches EOF, which is what the agent needs.
     Every unit test passed while this was broken; nothing but a real run
     could have found it.

   - **A test can be green on every machine you run it on and red on the one
     that matters.** `machineCanBeRemovedFromTheHerd` and
     `machineConfigurationStorePersistsDynamicMachines` passed here and failed
     on the mini, on a pristine checkout. The cause: an empty
     `MachineConfigurationStore` seeds itself with
     `MachineConfiguration.local()`, whose default name is **the computer's
     own**, and `add` treats a same-named machine as a duplicate. The mini's
     ComputerName is literally "Mac mini", so the fixture named "Mac mini" was
     deduped away and never added. This laptop is called "air".

     Fixed: the seeded machine is injectable and every test store now takes
     `.testLocal`, a fixture with a name nothing else uses. Verified by running
     the suite on the mini — 579 passing there, where two failed before.

     **Why this one is worth remembering.** The destination's test run is what
     decides whether transferred work is delivered, so a check that fails for
     a reason belonging to the machine rather than the work would refuse good
     work and blame the successor for the name of the Mac it landed on.
     Anything host-derived in a fixture is a test that only happens to pass.

   - **A transfer carries the whole dirty tree, including scaffolding.** The
     first run sent a temporary test harness to the mini along with the work,
     and it was that file which turned the check red. This is the intended
     behaviour — uncommitted work travels — but it means whatever is lying
     around in the checkout goes too, and it will be somebody's stray notes or
     a scratch file with a token in it eventually.

   - **`-tt` makes git narrate.** The forced terminal that gives us
     cancellation also makes `fetch` emit its progress meter, so a transcript
     is mostly `Receiving objects: 51%…`. Pass `--quiet` on the fetch before
     showing a transcript to anybody.

   - **The departure must not touch the working copy, and every obvious way
     of doing it does.** `checkout -b` moves the checkout somebody is looking
     at. `git add -A` rewrites their index — measured: a tree with a modified
     tracked file, a staged addition and an untracked file comes back with all
     three staged, so a deliberate staged/unstaged split is destroyed as a
     side effect of dragging an icon. `stash` mutates a stack shared with
     every worktree of that repository. The version that works assembles the
     tree in a scratch index — `GIT_INDEX_FILE` + `read-tree HEAD` + `add -A`
     + `write-tree` + `commit-tree` + `branch -f` — and was verified against
     real git: `git status` byte-identical afterwards, HEAD unmoved, and the
     branch carrying all three files. Git objects are immutable, so every step
     is an addition and a failure half-way leaves only unreferenced objects.
   - **Cancelling a transfer only reaches the other machine because of
     `-tt`.** Measured both ways on the mini: a remote `sleep` started over
     `ssh -tt` is gone four seconds after SIGTERM to the local `ssh`; the same
     command over `ssh -T` is still running with the same pid. Without the
     forced terminal, calling off a transfer kills the local end and leaves the
     agent working on somebody else's Mac, spending tokens on an answer nobody
     is waiting for. This is the same finding that put `-tt` on the
     authentication probe, and it is now load-bearing in a second place.
   - **A tool allowlist does not bound a successor, and the shell has to go
     instead.** Measured on the mini rather than assumed, after this file spent
     a day claiming otherwise. `--allowedTools "Bash(git status:*)"` is
     *additive*: a session given it ran `whoami` on the first ask.
     `--disallowedTools "Bash"` does remove the shell. Denying `Bash` while
     allowing one pattern does not hand the pattern back — deny wins and
     nothing runs. So the flags offer all of the shell or none of it, plus a
     deny-list you have to have thought of, and a deny-list you enumerate is
     not a boundary. The successor therefore gets **no shell at all** and only
     edits files; Little Herd runs the build, the test and the git afterwards
     from commands it owns. A hostile brief's best outcome is edits on a branch
     nobody merged. This was the one control everything else was stacked on,
     and it was the one thing never run.

     Denying the shell is also not enough on its own: `Read` plus `WebFetch`
     exfiltrates without one. Both network tools are denied too — but note
     that this is the enumerated deny-list again, one rung up, and it will be
     wrong the same way the moment a tool is added. **The durable boundary is
     environmental, not a flag**: a dedicated account that owns nothing, the
     same shape as `linux-restic` on the NAS. Treat the flags as depth.
   - **Never execute a path the destination reported.** `AgentInstallation.path`
     is parsed out of the remote probe's own output, so a compromised or
     spoofed machine chooses the binary the transfer will run on it. Resolve
     from an allowlist of known locations on the destination and check the
     signature. The app only displays this today; a transfer makes it an
     execution primitive handed over by the destination.

   - **Signing was replaced by a pinned commit, and the parameter that stood
     in for it is gone.** `plan()` now takes `expectedCommit` — the full sha
     the source machine has just pushed — and refuses anything that is not
     forty hex characters, because a ref name is not a pin: "main" is
     satisfied by whatever main happens to be when the fetch lands. The
     destination checks `rev-parse FETCH_HEAD` against it before an agent
     reads a line, and builds the worktree from the sha rather than from
     FETCH_HEAD so a race between the two commands substitutes nothing.
     Verified against real git: correct sha proceeds, wrong sha refuses and
     leaves no worktree behind. What this answers is not *who wrote this* but
     *is this the thing I was just sent* — the branch is data, and the drag,
     arriving over authenticated ssh, is the instruction.
   - **Run in a fresh worktree**, not the user's working copy, so a bad brief
     cannot quietly amend real work.
   - **Every agent-reported string is display data forever.** Session titles,
     project names and activity phrases come from transcripts on machines that
     may have been reading untrusted material. They already reach a person's
     eye; they must never reach a prompt undelimited.

   **The spike demonstrated the injection path by using it.** That was an
   acceptable trade for a measurement on machines we own, and it is not an
   acceptable shape for the feature.

 What it settled: a written brief is enough, and the
   successor needs permission to build and push.

   **Since then the machinery has been built, and none of it has run as one
   motion.** Keep those two sentences together — every piece below is measured
   on its own, and no transfer has yet gone source → destination → branch end
   to end. Treat "tested" here as "each part was broken on purpose and the
   suite noticed", not as "this works".

   Built and individually verified:

   - `TransferEligibility` — whether a session can be lifted at all. Waiting is
     ready; active is waited for rather than refused; finished has nothing in
     flight; **stalled is refused loudly**, because a session that stopped
     inside a tool call is exactly the one that cannot say where it got to.
   - `TransferDeparture` — brief (via `--resume`, so it is the session's own
     account of itself) then a branch built in a scratch index. See the
     working-copy fact above.
   - `TransferPilot` — the join. One value crosses: the sha the source pushed.
   - `SuccessorLaunch` → `SuccessorRun` → `SuccessorExecutor` → `SuccessorSSH`
     — plan, commands, ordering under failure, and the wire.
   - `TransferCoordinator` — lifecycle, and finished transfers survive a closed
     panel so a red run is not lost silently.

   Wired since, and this is where the item now stands:

   - **The drop calls it.** `endDrag()` reports an accepted drop and
     `MonitorModel.beginTransfer` assembles and runs the move — a deck drag
     moves the session its badge was already standing for, a card carried out
     of the fan moves that one. The view reports and does not act: what is
     possible needs every machine's checkouts and agents, and a run outlives
     the window that started it, so neither belongs in a gesture handler.
   - **The interface is built.** `TransferStrip` stands in for the overview
     header — in the band rather than above it, because this content is sized
     to the point and anything that grows it pushes the metric tabs off the
     bottom, three times so far. It names which of the eight phases is running,
     offers to stop a live one and to dismiss a finished one, and those are
     deliberately two controls rather than one label changing: stopping work on
     another machine and clearing a row you have read should not be one
     mis-click apart. The card carries a progress bar across its foot, and
     `TransferDiffScene` opens a window on what came back.
   - **What is left is one word.** `DashboardChrome.startsTransfers` is still
     `false`, and its comment still says the reason is that nothing on screen
     says a transfer is happening, how far it has got, or lets you call it off.
     All three exist. **Turn it on, watch a real move, and this item closes** —
     and the site's hero, which no longer hedges, becomes true.
   - ~~The first real end-to-end run.~~ **Done. A full transfer completed
     green on 27 August**, source → mini → branch → back:

     ```
     departure   dirty tree captured, source byte-identical, pushed a763e35
     worktree    pin verified on the mini
     agent       one file, 11 lines, exactly the brief — with no shell
     check       580 tests passed on the mini
     delivery    a763e35..2037752 pushed to the transfer branch
     cleanup     worktree gone, prompt gone
     ```

     **The earlier runs on the same day are the more useful record.** They
     found four things, all above: the variadic flag that ate the prompt (a
     real bug, now fixed), the non-hermetic check (a real design problem, open),
     the whole-tree capture, and the git narration. What worked: the departure
     built a branch from a dirty tree and left the source byte-identical, the
     pin verified on the destination, the agent did exactly the brief **with no
     shell**, and when the check went red the delivery correctly did not run —
     the remote branch stayed where the departure left it. The last unexercised step — asking a *live* session to hand
     over — was then run separately on the mini and works. A real session was
     started, given a small task, and resumed with
     `TransferDeparture.briefRequest`; it wrote a handoff that described the
     work in prose, distinguished what it had verified by reading from what it
     had not run, flagged that the tree was dirty before it began — and, asked
     what it had learned that the code does not show, **said it had nothing
     rather than inventing a lesson.** That last part is what "write only what
     you actually know" was for, and it is the failure mode this prompt was
     most likely to have.
   - Verifying the successor behaviourally before retiring the source, and what
     a half-finished move looks like on screen.

   Not process
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
   which the AI panel now sorts to the top and labels, so the sessions that
   could move are the ones you see first.

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

   **Cross-vendor handoff is the same protocol and the one move that buys
   tokens.** Adopted 18 August. A Codex session out of budget hands off to
   Claude by the identical seven steps — the successor command differs, nothing
   else — and it is the payoff of choosing a plain-markdown briefing over
   transcripts, which are vendor-locked. This amends the budget rule: within a
   provider a move rebalances silicon only; across providers it is the one move
   that changes the budget, so budget is herd-level *per provider* and provider
   is part of placement. The trigger is the sharp part: **summarising costs
   tokens on the source vendor, so at 0% a session cannot write its own
   briefing** — the mini's Codex proved it today. `AIUsageBudgetStatus` already
   fires at 25/10/1% with `resetsAt` beside it: at critical, always prepare the
   briefing (park is cheap and needs no destination); then `resetsAt` decides —
   reset soon, park and wait; reset tomorrow with work due, offer the move.
   **Automate the offer and the preparation, never the move** — the signal is
   CodexBar's scrape, and eligibility gains one probe: capability parity, since
   the tools a session leaned on may not exist on the other vendor.

6. **iOS, scoped to the herd rather than to sessions.** Do not rebuild session
   steering; Remote Control and the Claude app already do it, with the local
   filesystem and MCP servers attached. What has no answer today is the herd:
   which machine is hot, what is waiting on you, what the budget looks like,
   and starting a transfer. Do not sample from the phone either — iOS will not
   ssh-poll in the background. It wants a resident collector on the mini, which
   is the same helper item 3 needs for the Keychain problem and the same one a
   durable successor session needs. Build it once. The model layer is already
   portable — 64 of 103 source files import neither SwiftUI nor AppKit, and
   `MachinePresentation` exists precisely because display decisions were pulled
   out of the view bodies. The proportion has held as the app has doubled,
   which is the part worth checking rather than the count.

7. **Agent versions are measured; nothing draws them any more.**
   The AI page used to list what a machine had installed, above the sessions,
   with the path it was found at and — when another account had a newer copy —
   which one and what version. `DashboardChrome.showsInstalledAgents` is now
   `false`: which agents are installed is a fact about the machine rather than
   about the work, and it was the first thing on a page you open to see what is
   running. The probe still reads it, and the transfer needs it, so this is
   measurement without a display rather than dead code.

   What is still missing is seeing the herd at once. Today you learn that the
   Air is on Codex `0.148.0-alpha.15` and the mini on `alpha.21` by visiting
   two pages and remembering. That is enough to answer "is this machine
   behind", which was the complaint; it is not enough to answer "how many
   builds is this herd running". Worth doing only if the answer would change
   something.

8. **Attribute a session's CPU to its whole process tree, not its agent
   binary.** The measurement is in the facts above: 1.0% against 101.2% for the
   same session in the same window. Today the panel can say a machine is at
   94% and cannot say which session is doing it, which is the question the
   figure was added to answer.

   **The walk is built and the figure is now a share of the machine**; the
   floor is 2% of it, set from measurement. What is *not* solved is that `ps`
   sees only living processes, so short-lived children contribute nothing —
   the fact above has the numbers. The remaining work is to sample the tree
   twice inside one probe run, a couple of seconds apart, and report the rate
   instead of the counter. That costs one extra `ps` and a `sleep 2` in a call
   already being made, and it is the only approach that catches a child which
   lives and dies between two thirty-second samples.

   Two things settled along the way. Memory is deliberately **not** summed
   across the tree — resident size double-counts every shared page — so it
   stays the agent's own. And whether Xcode's compilation lands inside the
   session's tree is **still unverified** after four attempts: one sample
   caught `swift-frontend` at 97% CPU with a parent that was not `xcodebuild`,
   and the process was gone before it could be traced to a root.

9. **A cloud column in the AI panel — source-only, native vehicles.** Adopted
   18 August. Show cloud work beside the machines (the Herdware set already
   holds an unused `owl-cloud.png`) and move it down with the vendors' own
   commands, never our protocol: `codex cloud apply` and `claude --teleport`.
   Little Herd's contribution is the placement decision — which machine
   receives it — which is the eligibility probe again, plus one natural
   extension: the Codex task names its repo, so the probe checks the
   destination has that checkout. The two vendors get honestly different
   treatment, per the facts above: Codex cloud tasks are *rows* (headless
   `list`/`status` work today, even at 0% budget); Claude cloud is an
   *affordance* ("pull a session by id onto…"), because nothing can enumerate
   it from here. Say so in the interface rather than pretending parity.
   Local→cloud stays out entirely — that is the vendors' own button.

10. **Local models are blocked, not pending.** Considered and deferred
    18 August. No herd machine runs a model server; the linux box is an AMD
    APU with integrated graphics; the best local-model host owned is the M5
    Air — the machine transfers exist to unload. A briefing written for a
    frontier successor would swamp a small local model, and Claude cannot even
    reach one without `ANTHROPIC_BASE_URL`, which forfeits Remote Control.
    Reopen when a real runner exists on a herd machine *and* there is a
    concrete reason — offline or privacy, not symmetry. Frame it then as a
    degraded park, not a peer destination.

11. **The website is built and live** at <https://malpern.github.io/little-herd/>,
    served from `main` by GitHub Pages, with a wordmark, hero art, and a
    download. The README carries the same hero, baked into a single file by
    `scripts/make-readme-hero.swift` because a README has no CSS. **The one
    piece still stale is the dashboard screenshot in the README**, which
    predates the agent tokens; recapturing it needs the app running plus
    screen-capture access. What follows is the decision record behind the site,
    kept because the paid shape is still unbuilt.

    **Free for now, and the plan is settled.** Decided 26 August. The question the last
    handoff called the one a website cannot be written without — charge or
    not — is answered **free for now, paid later**. The page gets a download
    button and tells the truth today; it does not promise a purchase that
    nothing can yet fulfil. The paid shape recorded below survives unchanged
    and is what drops in when it is built, so the layout reserves a place for
    a price block rather than being redrawn around one.

    Two more decisions came with it. The site is **hand-written static HTML
    and CSS in `site/`, published to GitHub Pages by an Action** — no
    framework, because a one-page marketing site with a build step is a second
    thing to maintain and this repo already has `scripts/release` to keep
    honest. A custom domain is a DNS change later, not a rewrite. And the art
    direction is a **dark forest-green hero over a light body**: the splash
    art full-bleed on the evergreen ground, then the page turns to the app's
    own cream for the feature sections so the screenshots read cleanly.

    **The app already ships the site's palette, and it should be used rather
    than sampled from the art.** `LittleHerd/Assets.xcassets` holds the
    authority: `HerdBackground` `#FBF8F1` light and `#1D1C1A` dark,
    `HerdForest` `#134F3C`, `HerdLoadGreen` `#1F9E52`, `HerdLoadTeal`
    `#1A9C8A`, and the alert red at `#E84A29` in `DashboardView.swift:1706`.
    A site built from those tokens matches the screenshots exactly; one built
    by eyedropping the splash art will not, and the mismatch shows worst
    precisely where a screenshot meets the page.

    **What the material review found.** The assets are strong and the words
    are not. The splash art, the app icon, and the twelve-avatar Herdware set
    are finished, on-brand, and better than most indie Mac sites open with —
    the Herdware sheet in particular is a section of the site that already
    exists as an image. What is missing is everything verbal: there is no
    tagline, no wordmark, no favicon, no social preview image, and no line
    anywhere that says what this is to someone who has not read the source.
    `README.md` is the only prose and it is engineering prose — accurate,
    thorough, and organised around how the app works rather than what it is
    for. It opens with bundle identifiers and preference-key migration. None
    of it can be lifted onto a marketing page.

    **The positioning to write to.** Every other monitor watches one machine;
    this one watches the herd, and it is the only one that can say which AI
    agent is running where. That is the whole pitch and the order matters —
    the herd first, because it is the category, and the agents second, because
    it is the thing nothing else does. The audience owns a laptop, a mini, a
    Linux box, and a NAS, and has lately started running Claude and Codex
    across all of them. Say "no agent to install on the other machines" early;
    for this audience it is a feature and a relief, not a footnote.

    **The hero art exists.** `DesignAssets/little-herd-site-hero-source.png`
    is a wide 1536x1024 recomposition of the splash scene with a calm dark
    left third to set a headline and a button over, and
    `little-herd-social-card-source.png` is that same image centre-cropped to
    the 1.91:1 Open Graph wants, so the two cannot drift. Both were made with
    the OpenAI images API from the existing art as reference; the recipe, the
    working key, and a rejected variant that invented an Apple-like mark on a
    laptop screen are in `little-herd-site-hero-prompt.md`. Generated art gets
    looked at at full size before it goes near the page.

    **The wordmark is drawn** — "Little Herd" in Gabarito 600, outlined to SVG
    paths so no webfont ships, with the tittle of the *i* replaced by the app's
    green status dot. That is the one place the mark says what the product
    does, and the letter already had a dot. `scripts/make-wordmark.swift`
    reproduces it byte-for-byte; the reasoning, the five faces that were
    compared, and the generated alternative that lost are in
    `DesignAssets/little-herd-wordmark.md`. Still not drawn: a favicon, which
    is a reduction of the existing app icon rather than new art.

    **The copy is drafted and lives in `site/COPY.md`.** It is the source the
    page quotes rather than a suggestion — headline, six sections, both CTAs,
    and the reasoning for each, including which alternatives lost and why. The
    facts in it were checked against the app rather than against the README:
    macOS 15.0 and a universal binary come from `project.yml` and `lipo`. Its
    voice section is four rules, each one a thing the first draft got wrong;
    the load-bearing one is that the animals supply the warmth, so the prose
    can stay dry. Whimsical art plus whimsical writing is twee, and the
    audience that owns four computers leaves.

    **Two sections now run a live recreation of the window rather than a
    screenshot** (`site/demo.js`): the CPU overview, and the AI panel that had
    no picture at all. Hover puts a machine in the header, the tabs walk the
    four metrics, and sessions arrive and finish on their own. It is captioned
    as a recreation and the numbers are invented. **If the real panel changes
    shape, this is a second place that has to change with it.**

    **The site no longer shows the hovered header, because the app no longer
    has it.** The section built around it is gone, so is its screenshot, and
    the live panel now demonstrates the thing that replaced it: click a machine
    to open it, with the metric picker coming along so a lens change keeps you
    on that machine. A third instance opens on a machine's Disk page, volumes
    and all, including the shared-container row. **The README is still stale on
    this, in two places** — it says hovering a row replaces the stable header
    with that agent's machine and plan step, and it describes the per-provider
    budget gauges in the header, which `showsUsageMarksInHeader` turned off.
    Both are the same edit: the header says one thing now, and the four metric
    tabs are what changed underneath it.

    **The site is reframed around the herd, and there is a second page.**
    Decided 26 August. The word was decoration — used constantly, never taught —
    so the hero now sells the practice and the download is the second call to
    action. `site/herd.html` is a finite **ten**-step guide: Universal Control,
    Screen Sharing, Tailscale, **Sunshine and Moonlight**, SSH config, Homebrew
    and a Brewfile, tmux, **Herdr** (<https://github.com/herdrdev/herdr>, an
    agent multiplexer — it shows agents on one machine, which is the complement
    to seeing them across all of them), Time Machine to a NAS, and
    Healthchecks.io. Little Herd is the payoff and is not one of the ten, which
    is what makes the rest of it believable.

    **Sunshine and Moonlight were added on 2 September, at 4.** Screen Sharing
    at 2 is the right answer for one button in one dialog and the wrong one for
    working on a Linux box: VNC sends pictures of a screen, and a desktop you
    cannot drag a window on is one nobody uses. Sunshine sends video encoded by
    the graphics chip already in the machine. It sits after Tailscale by the
    ordering rule — it needs software on both ends and a pairing step, so it
    comes after the two that install nothing — and that placement also puts its
    most important trap one step after the thing that makes the trap easy to
    obey. **Its traps are measured on a machine that has been running it**, not
    taken from documentation: a host with no monitor attached has no screen to
    send and streams a black rectangle while reporting itself healthy, and the
    settings page answers on every network the machine is on while being the
    page that controls its screen. The startup log's `[wlgrab] Could not
    initialize display` line is noise — it tries capture backends in order and
    narrates the ones it rejects — and is called out as such so nobody hunts a
    fault that is not there.

    **It is the only step with no screenshot, deliberately.** Both halves of the
    tool put a real machine name on screen, the lab that stages these shots runs
    macOS guests only, and a redacted shot would be the single one here that was
    — so it goes without rather than break the rule that every shot is staged.

    **The order is what it pays back, not what it depends on, and it was got
    wrong twice.** The first order was a build order wearing a reader's
    clothes — reach, connect, tools — which put SSH keys and file permissions
    at step three, the most technical thing on the page offered as the price of
    admission. Reordering by payback put Tailscale first, and that was still
    a build order: it opens by asking somebody to install a mesh VPN and make
    an account on every machine before they have seen any of this do anything
    for them. **It now widens instead** — Universal Control across a desk,
    screen sharing across a house, Tailscale across the world — so nothing is
    installed until step three, by which point there is a reason to want it.
    Universal Control is the least technical of the nine and the most niche
    (two Macs, one desk), which is why it opens rather than being buried.

    **Two lines were lies the moment the order changed, and both were caught by
    reading the rendered page rather than by moving the entries.** Tailscale
    opened with "this one is first because everything below it assumes you can
    reach the machine at all" — true when it was first — and Universal Control
    sent the reader to "the step above" for something that had moved below it.
    **A step that names its position is a step that will be wrong**; say what a
    thing adds, not where it sits.

    **The last two were added because the first six do not survive being left
    alone.** Backup and alerting are what decide whether a herd is still there
    in a month, and a guide that stops at "you can reach everything" teaches the
    half that is fun. Pi-hole was considered for a ninth and deliberately is
    not one: it is a job you give a machine rather than a thing that makes
    machines work together, so it sits in a closing aside with its own video and
    an explicit note saying why it is not a step.

    **Ten steps in one column read as ten identical blocks, so they are
    three acts** — Get to them (four), Work on them (four), Keep it alive (two)
    — declared once in `ACTS` in `build.py`, which fails the build if a step is
    missing from one. That grouping is load-bearing in three places: the
    contents list, the act headings, and the sticky bar.

    **The intro is prose and does not count the steps for itself, so it goes
    stale silently.** It read *"Eight things turn a pile of computers into a
    herd"* while there were nine, and said they go in that order *"because each
    one assumes the last"* — the build order the reordering deliberately
    replaced. Both were fixed on 2 September. The count also appears in the meta
    description and the Open Graph one, which is three places prose has to agree
    with `STEPS`; nothing checks it.

    Every step carries its trap, and the traps are the whole reason to read it
    rather than any other tutorial. **They are generalised, not copied:** the
    lessons come from a real setup, the hostnames, addresses, accounts and
    topology of that setup stay private, and nothing in the guide names a
    machine that exists. Keep it that way.

    Two pages meant the stylesheet had to leave `index.html` — it is
    `site/style.css` now, and the wordmark symbol is `site/wordmark.svg`
    referenced by `<use>`, with `build-preview.py` folding both back inline for
    the Artifact.

    **The pages are generated, and hand-editing one is a CI failure.**
    `site/_src/build.py` renders `index.html` and `herd.html` from partials plus
    `site/_src/steps.py`; both carry a do-not-edit banner and the Pages workflow
    runs `build.py --check` before it will publish. `steps.py` is the single
    source for the eight guide steps *and* the eight homepage cards, so the two
    pages cannot disagree about what a tool is called or where it links.

    Still no framework, and the decision was re-examined rather than assumed:
    Astro would be the answer at five pages or a blog, plain Vite would buy
    nothing here. That note lives in `site/_src/README.md`.

    **One trap in the builder, because it silently shipped a broken page.** The
    body slice runs `</header>` → `<footer>`, and `<script src="demo.js">` sits
    *after* `</footer>` — so the first build dropped it, killing all three live
    panels while every page still rendered perfectly and the source diff looked
    like an entity change. Anything after the footer has to be declared in the
    `scripts` slot. It was caught by diffing the *rendered* output — text
    length, link count, element ids — not the source.

    **The guide's screenshots come out of a disposable VM, and that route is
    the answer to the TCC problem below.** The repo is a `vm-lab` tenant
    (`.vm-lab.tsv`, `artifact_expect` "Little Herd.app"), so a macOS 27 guest
    with `--desktop` gives a clean machine with Peekaboo and TCC already
    granted, and nothing has to happen on the real screen. Four shots ship —
    ssh, brew, tmux, Finder's Connect to Server — every one **staged, not
    scrubbed**: invented hostnames in a machine that has nothing real in it.

    Two lessons cost an afternoon each. **`--macos 15` silently gets a stock
    Cirrus image** with no Peekaboo and no TCC; the desktop branch of
    `base_for()` is gated on 26 or 27, so the flag is the fix, not the lab.
    And **identity leaks three separate ways into a terminal screenshot**: the
    known-hosts warning printed the address, the prompt printed the lab account
    because the override only applied to the outer shell, and Terminal composed
    the account into its own title bar. Pre-seed the host key, set `PROMPT` in
    the guest's `.zshrc`, crop the chrome, and **OCR the result** — all four
    were checked that way rather than by eye.

    **Code on the page is highlighted at build time**, by a small shell and
    `ssh_config` tokeniser in `build.py` emitting six classes
    (`t-cmd`, `t-flag`, `t-path`, `t-key`, `t-val`, `t-cmt`). A runtime
    highlighter would be an external script, and the Artifact preview's CSP
    blocks those — so the choice was a build step or nothing.

    **Every step carries a video, and the count is the honest one.** Eleven
    links: BarTech TV on Universal Control, 9to5Mac on screen sharing,
    Tailscale's own introduction, gotbletu on Sunshine and Moonlight, Learn
    Linux TV on the ssh config, DevOps Toolbox on dotfiles, typecraft on tmux
    and on Herdr, SpaceRex backing a Mac up to a Synology, Techno Tim on Uptime
    Kuma, and Crosstalk Solutions on Pi-hole in the aside. **Restricting
    the search to two named creators was the wrong constraint** — it left five
    steps bare, including the one specifically asked for — so the rule is now
    whoever made the best one. Every id is verified against **YouTube's oembed**
    for its real channel and title rather than trusted from a search result, and
    two that looked perfect were dropped once their descriptions were read: "The
    Perfect Home DNS Flow" is DNSimple and auto-SSL rather than Pi-hole, and
    "Stop Using Tailscale" argues against the tool its step recommends. **A link
    that turns out to be neither is worse than no link.**

    Sunshine's choice went the same way and is worth recording because the
    obvious pick lost twice over. NetworkChuck's is by a wide margin the
    most-watched video on this subject and is out for the reason already
    standing against Tech Gear Talk — the card renders a title verbatim, and
    that one shouts. AgileDevArt's is the best match on substance (49K views,
    and a description that is specifically low-latency *desktop* streaming
    rather than gaming) and dates itself in its own title, which a page written
    two years later has to display. gotbletu's has 4.7K views and a description
    of two bare links, and is the only one of the four whose title names remote
    desktop — which is what the step is about. **Descriptions are not fetchable
    by tooling**: YouTube renders them in script, so `WebFetch` returns the
    footer and oembed carries only channel and title. They have to be read in a
    browser, and this is the step where that was worked out.

    Universal Control's is the third instance and the first where the *shipped*
    link was wrong: the step is headed "two Macs" and carried Apple's own video,
    which is titled "on Mac and iPad" and demonstrates exactly that — the one
    illustration on the step showed the pairing the step is not about. Two
    better-known candidates lost for recorded reasons. Stephen Robles' "My
    Ultimate Dual Mac Workflow" is the trap again — perfect title, and a
    description that is iCloud Drive and Final Cut sync with no mention of
    Universal Control. Tech Gear Talk's is the stronger video on the merits, and
    its title shouts in capitals; **the card renders a title verbatim**, so on a
    page that does not raise its voice that is a layout fact rather than a
    quibble.

    **Each step also offers a prefilled ChatGPT prompt** via `chatgpt.com/?q=`
    — undocumented but long-established — kept to a few hundred characters
    because a long query string risks being cut by a WAF on the way. The button
    carries OpenAI's mark, rebuilt from the Wikimedia SVG as one petal and five
    `<use>` rotations so it takes `currentColor` and themes with the page. Their
    guidelines permit referential use on two conditions this meets: it must not
    imply endorsement, and it must not be more prominent than our own mark.

    **A sticky bar names where you are in the guide**, revealed once the
    contents list scrolls away and hidden again past the last step — the page is
    13,000px and nothing answered "where am I" for any of it. It ships `hidden`
    and `site/guide.js` reveals it, which is deliberate: the contents list is
    the navigation that survives scripting being off.

    **It shows the eight numbers, and that was chosen over the alternative
    twice.** Sticky-in-flow was tried first because it needs no script to
    appear, and looked wrong at rest — directly under the contents it was a
    second, terser copy of the same eight items. Then the numbers were replaced
    with the three act names, on the argument that a number is a legend you
    decode against a contents list that has scrolled away; **that shipped and
    was reverted on sight** (PRs 30 and 31). Words read more easily and navigate
    more coarsely, and the coarser version was the one that felt wrong on the
    page. The argument is not gone, only outvoted by looking at it.

    **The highlight is measured, not observed.** An `IntersectionObserver` on
    the steps answers "is this on screen", which is the wrong question when
    every step is taller than the window — the answer is regularly "none" or
    "two". The observer is only a signal that the answer may have changed; the
    decision is the last step whose top has passed under the bar, which settles
    ties in reading order. **A background tab gets no animation frames**, so a
    scroll while hidden would leave the highlight unpainted until the reader
    scrolled again; `demo.js` learned that same lesson here first, and there is
    now a note in each pointing at the other.

    **The guide is one column, and was briefly two.** The sidebar used the width
    a 40rem measure leaves empty at desktop, which was optimising for wasted
    pixels rather than for reading. A guide is read rather than scanned, and the
    empty right-hand side is what a comfortable measure costs.

    **Measure narrow layouts with the rules forced on at a wide window.**
    Headless Chrome floors its layout viewport at 500px, so measuring at a
    phone-sized window returns numbers that mean nothing — it reported the same
    overflow before a change as after it, which is the only reason the numbers
    were not believed.

    **Open on the site: the homepage has two download buttons, ~7,500px apart,
    and nothing between them.** A reader convinced in the middle has nowhere to
    click.

    **Screenshots of the app are still not taken, and the obstacle is TCC —
    but the VM lab above is now a route around it.**
    `screencapture -l` (which `scripts/capture_app_window.swift` uses) and
    `screencapture -R` are both refused outright on this machine — "could not
    create image from window" and "could not create image from rect" — while a
    plain full-screen `screencapture` succeeds and returns real content. So
    the fallback is a full grab cropped to the window rect, and **that crop
    came back solid black with the diagnosis unfinished**: the full frame had
    content, so it is the crop that is wrong, most likely the scale factor,
    since `NSScreen.screens[0]` need not be the display that was captured and
    this Air runs a scaled resolution. Anyone picking this up should verify by
    looking at the cropped image, not at its dimensions — the first attempt
    reported a perfectly plausible 600x656 at 2x and was entirely black.

    **Item 8 (cloud) is the only Coming soon section left.** Item 4 graduated on
    29 August: moving work is claimed in the present tense, the pill and the
    tinted ground are gone, and the hero says it outright. **That is ahead of
    the app by one boolean** — `DashboardChrome.startsTransfers` is still
    `false`, held until the progress and cancel controls exist — so the page
    and the build have to be brought level, and the site is the side that
    cannot be quietly walked back.

    The wording is **"move work", never "move a session"**: a session is what
    the machinery moves, work is what the reader is afraid of losing.

    What survives from the original decision is the shape. A section sits on
    tinted ground behind a pill with every sentence future tense until it
    ships, and both sections carry their constraints rather than only the
    upside — "silicon, not tokens", the phone never being a destination, the
    vendors' own commands. Those limits are the most credible thing in the
    section; a roadmap that lists only upside reads as a wish, and losing the
    pill is not a licence to lose them. **If either item changes shape, the
    page is a second place that has to change with it.**

    When transfer ships, watching stays the headline and moving becomes a
    strong section rather than the thesis — watching is the everyday use and
    the reason it lives in the menu bar, and the product should not collapse if
    a transfer proves finicky in practice.

    **The app screenshots were refreshed on 27 August** — `dashboard`,
    `ai-panel` and `add-machines` in `Documentation/Screenshots`. For a menu-bar
    app the screenshots *are* the site, so when they next need retaking: render
    the panels with `PanelRenderHarness`, but check the hero shots in the
    running app, because the harness draws no `ScrollView`, no lazy stack, no
    `Form`, no hover state, and turns a `.borderless` button into a yellow
    placeholder.

    **Still owed: dark-mode versions.** `HerdBackground` has a dark variant, so
    the app can supply screenshots that sit on the evergreen hero without
    fighting it, which the cream ones do.

    **The paid shape, unchanged and not yet built.** Distribution is Developer
    ID and notarisation, because the store is closed to this app for good (see
    the facts above) and `scripts/release` already does the whole job. Payment
    goes through a **merchant of record** — Lemon Squeezy or Paddle — which
    takes a cut and absorbs VAT and sales-tax filing, the genuinely miserable
    half of selling software alone. The licence key lives in the **Keychain**,
    reusing `KeychainSecret` *including its lesson*: it deletes and re-adds
    rather than updating, because updating preserves the first build's access
    list, and for a licence key that means every paying customer locked out by
    a Sparkle update. Activation is two REST calls and no SDK; put the host in
    `NSExceptionDomains` so it keeps a real ATS floor while the NAS does not.

    **Trial: 14 days, calendar, from first launch, stated plainly.** Not 7 — a
    monitor's value is ambient and someone who installs on a Friday never
    really tries it. Not 30 — long enough to be forgotten, and the point of a
    first paid product is to learn whether anyone converts. The clever version,
    starting the clock on the second machine added, was considered and
    rejected: it is a rule nobody can reason about, and it leaves a permanent
    free tier for one-machine users by accident. Keep the start date in the
    Keychain beside the licence so it survives a reinstall, and stop there —
    the repo is public and anyone determined can compile the check out.

    **Enforcement: degrade, never disable.** After the trial Little Herd keeps
    monitoring *this* Mac and stops sampling remote machines. That line is the
    product's own argument stated as a paywall — local monitoring is a
    commodity, the herd is what nothing else does — and it leaves a working app
    in the menu bar, which is permanent quiet marketing. **An unlicensed remote
    machine must not read as `Unavailable` and must not take the red dot.**
    Showing a licensing state as an outage would send someone SSH-ing into a
    machine that is perfectly fine, which is the most expensive false signal
    this app could emit; it needs its own vocabulary, visibly not an error.
    Nagging is one quiet permanent signal — days remaining in Settings and the
    panel footer, colour only in the last three days — and never a modal.
    **Fail open**: activate once, cache, re-validate weekly, and never let a
    network failure downgrade anyone. A monitor that locks up when the network
    is flaky breaks exactly when you wanted to look at it. Licence per person
    with about three activations, not per monitored machine — charging per
    watched machine taxes the behaviour the product exists to encourage.

    The licence itself still needs explaining wherever it appears —
    `FSL-1.1-MIT`, source-available, MIT after two years — and a badge will
    not do it. One sentence in plain words, on the page and in the README.

12. **Swap is read on two machines of four.** This Mac and Linux report it;
    a remote Mac is not asked, and the Synology is not either. The remote-Mac
    half is a line in `macOSCommandTemplate` plus a parser for the string form
    of `vm.swapusage`, which unlike the local struct has an `M`-or-`G` suffix
    and wants a test of its own. DSM already parses `avail_swap` in
    `SynologyDSM.swift`; whether it also reports a total is unchecked, and
    available without total is half a reading. Neither is urgent: the tooltip
    mentions swap only while swap is being written, so a machine that is not
    asked simply says nothing, which is what it should say.

13. **The verifier is ahead of the thing that needs it, and the I/O half of it
    has no tests.** Written 25 August, and worth being honest about. Its pure
    parts — `AgentAuthProbe`, the eligibility states, the presentation — are
    covered and were verified by breaking them. `AgentAuthVerifier`,
    `ProbeWatchdog`, `runCapturingAll` and `runLocally` are referenced by no
    test at all, and that is roughly a hundred and ninety lines of process and
    concurrency plumbing in which **four bugs were found by running it and
    none by the suite**: stdin inherited rather than closed, no watchdog at
    all, silence read as a refusal, and a cancelled probe that did not stop
    the work it started.

    That last one is the shape of the risk. The comment claimed cancellation
    and the code did not do it, and only an experiment against another machine
    said so. If more is built here, build it a test harness first — a fake
    agent script that can be made to hang, refuse, or answer is most of one.

    **The harness exists now, and the local half is covered.**
    `AgentAuthVerifierTests` is ten tests driving real subprocesses, built on
    3 September. No abstraction was needed: `AgentAuthProbe.command` quotes
    `install.path` into `/bin/sh`, so an `AgentInstallation` pointed at a
    script is a real agent doing whatever the script says. Each test was
    checked by breaking what it covers — deleting the null-device stdin
    reddens one, discarding standard error reddens three, and removing the
    SIGKILL escalation leaves the child alive through SIGTERM with the read
    blocked for the full thirty seconds.

    **`SSHCommandRunner.runCapturingAll` is still untested**, and that is the
    remaining half: it needs a live host, and pointing it at `localhost` would
    test this Mac's sshd rather than the runner. The watchdog underneath it is
    shared with the local path and is now covered, which is the part that had
    the bugs.


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
