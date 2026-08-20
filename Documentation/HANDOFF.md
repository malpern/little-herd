# Little Herd — handoff

**State:** `v0.1.32` is released, installed in `/Applications`, and running.
Two commits sit ahead of it on `claude/roadmap-3-4-6`: the destination-capability
probe and the checkout probe. 367 tests pass.

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
to a green suite. **Render a view before shipping it.**

Three things it cannot see. It renders neither `ScrollView` nor a lazy stack —
the first version wrapped both, wrote a blank image and reported success — nor
a `Form`, which is why the sign-in sheet renders with a blank band where its
fields are. And it cannot show a hover state, so anything that appears on hover
has to be checked in the running app: the AI panel's section chevrons and every
tooltip are unverified by eye.

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

**zsh aborts the whole script on a glob that matches nothing.** The agent probe
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

## Method notes

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
3. **Finish destination eligibility: the intent half, and saying it.**
   The measured halves are done and on the branch. Every account now reports
   which agents it can run and where — no machine in this herd has one on the
   PATH ssh sees, and all three can run both from absolute paths — and which
   repositories it has checked out, keyed by the origin remote's slug. The
   facts above carry the numbers.

   What is left is the part that is a choice rather than a measurement.
   `MachineConfiguration` needs a per-account "may host a session" setting,
   defaulting to **off**, and the interface has to say *which* reason a machine
   is not a destination — "excluded here", "no agent", "no checkout of that
   repo" have three different fixes and only the first is a preference.
   `DestinationEligibility` already models this and reports intent before
   capability on purpose; nothing displays it yet.

   **A destination is an account, not a machine.** The mini has `clawd` and
   `malpern`, and everything deciding whether a session can land is per-user:
   the home directory and so which repos exist, the agent install, the
   credentials, and the GUI login session the Keychain fact turns on. That last
   point may invert the obvious choice — `malpern` is the account logged in
   graphically, so it, not the automation account, is where a Claude session
   can authenticate. `MachineConfiguration` refuses a second entry with the
   same hostname, so this needs an account-qualified `MachineID`, which costs
   the published `transfer.json` contract nothing since `MachineID` wraps a
   `String`.

   **Budget is not one of the reasons.** The machines share one account, so an
   exhausted limit cannot be escaped by choosing a different destination —
   check it once, before offering a move at all. **The NAS is never a
   destination here**: DSM restricts shell access to administrators, the login
   shell is `/bin/sh`, and there is no package manager. The setting exists so
   someone with a capable NAS can opt in, not as a safety control.

4. **Transfer a session between machines, at the session level.** Not process
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

5. **iOS, scoped to the herd rather than to sessions.** Do not rebuild session
   steering; Remote Control and the Claude app already do it, with the local
   filesystem and MCP servers attached. What has no answer today is the herd:
   which machine is hot, what is waiting on you, what the budget looks like,
   and starting a transfer. Do not sample from the phone either — iOS will not
   ssh-poll in the background. It wants a resident collector on the mini, which
   is the same helper item 3 needs for the Keychain problem and the same one a
   durable successor session needs. Build it once. The model layer is already
   portable — 29 of 48 source files import neither SwiftUI nor AppKit, and
   `MachinePresentation` exists precisely because display decisions were pulled
   out of the view bodies.

6. **Show each machine's agent versions.** Cheap, and skew is invisible today
   while being the standing condition; see the facts above.

7. **A cloud column in the AI panel — source-only, native vehicles.** Adopted
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

8. **Local models are blocked, not pending.** Considered and deferred
    18 August. No herd machine runs a model server; the linux box is an AMD
    APU with integrated graphics; the best local-model host owned is the M5
    Air — the machine transfers exist to unload. A briefing written for a
    frontier successor would swamp a small local model, and Claude cannot even
    reach one without `ANTHROPIC_BASE_URL`, which forfeits Remote Control.
    Reopen when a real runner exists on a herd machine *and* there is a
    concrete reason — offline or privacy, not symmetry. Frame it then as a
    degraded park, not a peer destination.

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
