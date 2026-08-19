# Little Herd — handoff

**State:** the last release is `v0.1.24`; the Synology sign-in fix below is
committed and unreleased, so there is code ahead of the tag for the first time
in a while. 271 tests, all passing. The feed is live and was checked rather than assumed:
the appcast at the `releases/latest` URL names `LittleHerd-0.1.24.zip`, carries
a signature, and the asset returns 200. 0.1.23 added the four-state usage display, 0.1.24 the splash timing, size and
corner, and a sign-in message that signs you in. Sparkle's own path from 0.1.21
to 0.1.22 was watched end to end — see below.

Deliberately no commit hash in this paragraph. The previous two sessions each
left one that was stale within the hour, including the one written to correct
its predecessor: a line naming a commit is out of date the moment anything is
committed, this file included. `git log` answers that question and cannot be
wrong; what belongs here is what `git log` will not tell you.

**The Synology sign-in was App Transport Security, and it is fixed and
verified.** The NAS has been `nas` / `100.102.192.34` since 18 August, with key
expiry disabled and a 2048-bit certificate replacing the 1024-bit one from 2015;
none of that was ever the problem. ATS was refusing the certificate before
`SynologyTrustEvaluator` was consulted — the fact below has the whole shape of
it. Proved from inside the app with the real DSM account: sign-in succeeds, and
`SYNO.Storage.CGI.Storage` comes back with Volume 1 and all four drives —
`sdb` now the WD40EFZZ, every one `normal` at `unc=0`, 27–29 °C — against a
recorded pin of `5a9996474975067b06779b8694dea6d744236612f7810f9f213705d38c42a099`.
The credential is `SYNOLOGY_PASSWORD_HOME` in sops; a test can decrypt it in
process, but sops needs `SOPS_AGE_KEY_FILE` set explicitly or it cannot find the
age key from inside a GUI app. **What remains is one click, not a question:**
the credentials sheet has to be filled in once by hand so the keychain gains
`malpern@nas.tail9d0bb8.ts.net:5001` and routine sampling has a password to
read.

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

**What blocks a Mac from hosting a session is PATH, not version skew — and on
the Air there is no CLI to find at all.** Its Claude Code runs *inside*
`/Applications/Claude.app`; there is no binary, no mise shim, and nothing
bundled, so the Air needs the CLI installed before it can host a Claude session.
Codex is the opposite and already usable: the binary ships inside
`/Applications/ChatGPT.app/Contents/Resources/codex`, which is exactly why the
design resolves an absolute path per machine rather than probing `PATH` — no
amount of PATH repair finds a binary inside an app bundle. The mini→Air ssh link
was also missing its key entirely (`id_ed25519_air` did not exist on clawd,
despite ACCESS.md describing it); it was created and authorised on 18 August and
the link now works. Meanwhile
three machines run three different versions — 2.1.126, 2.1.229, 2.1.234 — so
skew is the standing condition rather than a cleanup. Both point the same way:
resolve an absolute agent path per machine and probe for the flag you need
(`claude --help | grep -q -- --session-id`), never pin a version.

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
a header is the same as silence to the person it is for. That is the case for
item 4 in one image, and the reason item 5 checks budget once rather than per
machine.

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

**Validate the instrument before believing what it says.** Silence from an
`NSLog` added to a delegate read as proof the delegate was never called; the
instrumentation had silently vanished from the source, so the silence proved
nothing, and the delegate had been running correctly the whole time. Note also
that `grep` and `strings` on the built binary find *none* of its known string
literals, so neither can tell you whether a build contains a change — check by
running the build, not by reading it.

**Break the test to prove it works.** Every substantive rule was verified by
reintroducing the bug and watching the suite fail. Two tests that passed without
proving anything were caught this way: one watched a side effect a killed shell
would not perform, another counted processes with a command containing the
pattern it grepped for.

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
3. **The sign-in sheet hides the reason it failed.**
   `SynologyTrustEvaluator` records a precise `certificateMismatch` — with the
   expected and received fingerprints — and `SynologyDSMError.detailForAPICode`
   maps every DSM code to a sentence a person can act on. The credentials sheet
   surfaces neither, reporting the generic URLSession error instead. The ATS bug
   above is what that costs: the sheet said "A TLS error caused the secure
   connection to fail" for an evening while the app's own log had already named
   ATS, and a sheet that reported which of its own branches refused would have
   pointed at the certificate rather than at the code that never got asked.
   Third instance of the same defect this week, after the usage row and the
   empty state — so the thing to write is the rule, not the third one-off:
   **a surface that refuses something must say which of its own branches
   refused, and never hand the user a lower layer's error verbatim.**

4. **The AI panel is the next thing to build.** It is the weakest surface in the
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

5. **Probe destination eligibility, and let the user express intent separately.**
   Capability is measured — an agent binary resolvable over a non-interactive
   ssh shell, git, and a checkout of the repo. Intent is a setting: some
   machines can host a session and still should not.

   **A destination is an account, not a machine.** The mini has both `clawd` and
   `malpern`, and everything deciding whether a session can land is per-user:
   the home directory and so which repos exist, the agent install, the
   credentials, and the GUI login session that the Keychain fact above turns on.
   That last point may invert the obvious choice — `malpern` is the account
   logged in graphically, so it, not the automation account, is where a Claude
   session can authenticate. Model it as one machine with several accounts, not
   as several machines: `MachineConfiguration` already refuses a second entry
   with the same hostname, and defeating that would double-count the mini in a
   herd view whose job is counting machines. `MachineID` wraps a `String`, so an
   account-qualified id costs the published `transfer.json` contract nothing.
   Note that moving between accounts on one box changes capability and not
   capacity — say so, or it reads as a rebalance that does nothing.
   Eligibility is both, and neither substitutes for the other. Default a new
   machine to off and let the probe make the offer.

   Say *which* reason a machine is not a destination, the way
   `RemoteUnavailability` already does for reachability — "excluded here", "no
   agent on the PATH ssh sees", and "no checkout of that repo" are three
   different answers and only the first is a preference. **Budget is not one of
   them: it is a herd-level precondition, not a per-machine one.** The machines
   share one account, so an exhausted limit cannot be escaped by choosing a
   different destination — check it once, before offering a move at all. **The NAS is
   never a destination for this herd** — DSM restricts shell access to
   administrators, the login shell is `/bin/sh`, and there is no package
   manager, so it fails the probe on every count. The setting exists so someone
   with a capable NAS can opt in, not as a safety control here; what stops an
   agent running on the Synology is that there is nothing there to run.

   This rung is useful on its own and everything below depends on it.

6. **Join activity to metrics — the highest-leverage thing not yet built.** The
   app samples both and correlates neither, so "the Air is at 90% sustained" and
   "three Claude sessions are on the Air" sit on two screens as unrelated facts.
   Saying it once — you are saturating the Air, the mini is idle — is what turns
   a monitor into something that answers "what should I do?", and it is the
   input any placement decision needs. It needs no new architecture.

7. **Transfer a session between machines, at the session level.** Not process
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
   the same state item 4 is about surfacing.

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

8. **iOS, scoped to the herd rather than to sessions.** Do not rebuild session
   steering; Remote Control and the Claude app already do it, with the local
   filesystem and MCP servers attached. What has no answer today is the herd:
   which machine is hot, what is waiting on you, what the budget looks like,
   and starting a transfer. Do not sample from the phone either — iOS will not
   ssh-poll in the background. It wants a resident collector on the mini, which
   is the same helper item 5 needs for the Keychain problem and the same one a
   durable successor session needs. Build it once. The model layer is already
   portable — 29 of 48 source files import neither SwiftUI nor AppKit, and
   `MachinePresentation` exists precisely because display decisions were pulled
   out of the view bodies.

9. **Show each machine's agent versions.** Cheap, and skew is invisible today
   while being the standing condition; see the facts above.

10. **A cloud column in the AI panel — source-only, native vehicles.** Adopted
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

11. **Local models are blocked, not pending.** Considered and deferred
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
