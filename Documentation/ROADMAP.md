# Little Herd — roadmap

**This file is the plan.** It says what is being built, in what order, and when
each item counts as done. `HANDOFF.md` is the history: what happened, why, and
the lessons. The roadmap deck
([Little Herd Transfers Roadmap](https://claude.ai/artifact/LcMQUWwxSNbZQT8DoGTg23))
is a view of this file, rebuilt from it on request; when the two disagree, this
file wins.

**Agents: keep it current.** Change an item's status in the same commit as the
work that changes it. Add a line under _Done_ with the commit or PR when an item
lands. Check the watch list at the start of any session that touches moves,
transport or sessions, and update its dates.

Status words: `todo`, `doing`, `done`, `blocked`.

Last reviewed: 15 November 2026, at `9a90b30` on `ios/spike-1`.

---

## Rules that shape every item

1. **First-party first.** Use Apple's, Anthropic's or OpenAI's own feature
   wherever one exists. Build our own only where none does, list it in
   `HANDOFF.md` under "First-party first", and switch when a replacement ships.
2. **Research, never a library.** Third-party tools are read for ideas, never
   added as dependencies. On record: [marcmy/claudeimportfromcodex](https://github.com/marcmy/claudeimportfromcodex).
3. **App automation is a stopgap.** Typing into a command-line tool under tmux
   is acceptable. Driving a desktop app's screen is a last resort, recorded in
   the watch list until an API ships.
4. **Chat lives in the vendors' apps.** People talk to a session in the Claude
   app (Remote Control) or ChatGPT (its remote connections). Little Herd moves
   and watches sessions; it does not host conversations. See item 11 for the
   one exception worth building.
5. **Smirk stays separate.** Little Herd runs on the personal Claude account
   (Max) and never uses the Smirk Team account, not even as a middleman. Smirk
   work must never cross into the personal account unnoticed.

---

## Transfers: where they stand

"Full" means the whole conversation resumes on the destination. "Brief" means
the departing agent writes a summary and a fresh session starts from it on the
same git branch.

| Transfer                          | Today                      | Reasonable next                       | Unlikely soon        |
| --------------------------------- | -------------------------- | ------------------------------------- | -------------------- |
| Machine → machine, Claude         | ✅ Full (watcher Mac only) | Full from any machine (#6)            | —                    |
| Machine → machine, Codex          | ⚠️ Brief                   | Full (#2)                             | —                    |
| Machine → Claude cloud            | ❌                         | New session from brief (#7)           | Full                 |
| Claude cloud → machine            | ❌                         | Full via teleport (#4)                | —                    |
| Machine ↔ Codex cloud             | ❌                         | New task from brief (#7, unverified)  | Full                 |
| Personal ↔ Smirk, on our machines | ⚠️ Crosses silently        | Warn or refuse (#1)                   | —                    |
| Personal ↔ Smirk, in the cloud    | ❌                         | —                                     | Impossible by design |
| Claude → Codex                    | ❌                         | Recent chats via Codex `/import` (#5) | —                    |
| Codex → Claude                    | ❌                         | Brief (#8)                            | Full                 |

Facts behind the "Today" column, checked against the code on 15 November:
`TranscriptCarry.canCarry` carries Claude sessions only; `TransferDriver.carryTranscript`
carries only sessions local to the watcher Mac and falls back to a brief
otherwise; the successor always runs the origin's provider; nothing reads which
Claude account a session or machine uses.

---

## Now: make today's moves safe and complete

### 1. Guard the account line · `todo`

A move can carry a Smirk session into the personal account (or back) because
the destination resumes under whatever account it is signed into.

- Read each machine's Claude account (`claude auth status`: `email`, `orgId`)
  and each session's, and show it.
- Refuse a move that crosses accounts unless the person confirms it, on the Mac
  and in the phone's move sheet.

**Done when:** a test pins the refusal, and a live dry run between a personal
and a Smirk machine shows the warning.

### 2. Codex keeps its conversation · `todo`

- Carry the Codex session file (`~/.codex/sessions/…/rollout-*.jsonl`) and
  resume it on the destination with `codex resume <id>`.
- For sessions whose rollout says `originator: "Codex Desktop"`, point the
  person to ChatGPT's own Handoff instead of running our move.

**Done when:** a Codex session moved between two machines resumes with its
history, and a desktop-app session shows the Handoff pointer.

### 3. Prove the phone move · `done`

Landed on 15 November at 11:15, from iPhone build 3 and Mac 0.1.74 (build 78,
`ca23009`). The ".herd Move Test" session went from the mini to linux and was
carried in full (`--resume --fork-session`). Taking PR #36 out of draft is
Micah's call.

### 10. Keep talking on the destination · `done`

Today the successor runs once, headless (`claude -p` in `SuccessorLaunch` and
`TranscriptCarry.resumeArguments`). It finishes, and its workspace is deleted,
so nobody can talk to the session after it lands. A move should leave a live
session on the destination, and the person chats with it in the Claude app.

Proved on linux on 15 November with Claude Code 2.1.325, before any code:

- `claude --bg` starts a background session that stays listed in
  `claude agents --json` and is managed with `attach`, `logs`, `stop` and `rm`.
- `--bg --resume <id> --fork-session` continues a carried conversation; the
  copy remembered its earlier reply.
- A worktree we make at `<repo>/.claude/worktrees/<name>` is covered by the
  repo's trust, so the session can start from the exact pushed commit.
  (`--worktree` would branch from the repo's current commit instead.)
- Remote Control is on for background sessions (`/rc active`). Micah found the
  session in the Claude app on his iPhone and chatted with it.
- An untrusted repo is refused ("Workspace not trusted"). Only `-p` skips the
  trust check, which is why one-shot moves never met it.

The build:

- Worktree at `<repo>/.claude/worktrees/herd-<branch>` on the transfer branch,
  with `.claude/worktrees/` added to that repo's `.git/info/exclude`.
- Start with `claude --bg --name "<title>" --permission-mode default`, plus
  `--resume <id> --fork-session` when the conversation is carried. The brief or
  carry prompt is the first message, kept off the command line.
- Landed means the session is listed in `claude agents --json`. The phone says
  where it is and that it continues in the Claude app. The automatic check and
  push stop; the session owns its branch.
- Before pushing, refuse a destination repo Claude doesn't trust, and say how to
  trust it. Little Herd never answers the trust prompt.
- Codex stays one-shot: it has no background sessions.
- **A move, not a copy** (Micah, 15 November): once the live copy is running,
  the original is ended if it is idle (`SIGTERM` for an interactive session,
  `claude stop` for a background one), and left open if it is mid-turn. The
  carried transcript on the destination is removed once the fork holds its
  last message, so the herd no longer lists it as a finished second session.
- **Automation shows in the window** (Micah, 15 November): `little-herd move
  --yes` hands the move to the running app over loopback with the pairing code,
  so it runs through `beginTransfer` like a drag or the phone and the window and
  phone show every phase; the command prints the phases and exits on the
  result. Without the app it runs the move itself, as before, and says so.

**Done when:** a move started from the phone lands on linux, and the moved
session answers a follow-up message sent from the Claude app.

Landed on 15 November at 12:58, from the iPhone (build 4) through Mac 0.1.77
(build 81): ".herd Move Test" became background session `d7f219e2` on linux,
in `sandpiper/.claude/worktrees/transfer-herd-move-test-clauded8`, holding the
whole conversation from the mini. The follow-up from the Claude app was not
repeated on that run; Remote Control chat with a background session was
confirmed earlier the same day ("herd probe fork"). Since `9a90b30` a move
carries the conversation by default, unscrubbed (Micah's choice), with a
privacy call-out in Settings.

---

## Next: reach the cloud, and cross to Codex

### 4. Pull from Claude's cloud · `todo`

Run `claude --teleport <session-id>` on a chosen machine, in tmux. Little Herd
cannot list cloud sessions, so the person picks one from the phone or pastes its
ID. Requires the destination to be signed into the account that owns the
session, a clean checkout of the same repo, and the branch pushed.

**Done when:** a cloud session started from the Claude app resumes on linux
through Little Herd.

### 5. Claude → Codex via Codex's import · `todo`

Drive Codex's interactive `/import` under tmux to bring recent Claude Code chats
across (up to 50 from the last 30 days, local only).

- First, test whether imported chats arrive in full or summarized; OpenAI's
  page does not say.

**Done when:** a Claude session's conversation is readable in Codex on the same
machine after a Little Herd-started import.

### 6. Full Claude carries from every machine · `todo`

Lift the watcher-only limit in `TransferDriver.carryTranscript`: carry the
transcript from linux and the Air over ssh, not just from the watcher Mac.

**Done when:** a session on linux moves to the mini with its full conversation.

---

## Later: briefs where conversations can't go

### 7. Into the clouds by brief · `todo`

Start a new Claude cloud session (`claude --cloud "<brief>"`) or a Codex cloud
task from the pushed branch and a brief. Verify Codex's cloud command line first.

### 8. Codex → Claude by brief · `todo`

The departing Codex agent writes the brief; Claude starts on the same branch.
Read claudeimportfromcodex for ideas when designing it.

### 9. Try CloudKit as the transport · `todo`

Spike: the herd snapshot alone, read-only, through the private iCloud database.

- Measure update delay and whether notifications arrive reliably.
- Confirm a Developer ID provisioning profile works for the Mac app.
- Check whether CloudKit notifications can be time-sensitive; if not, alerts
  keep the direct APNs sender.

If it holds, CloudKit replaces our server, pairing and signing (see "First-party
first" in `HANDOFF.md`).

### 12. An ended session is not "waiting on you" · `doing`

Little Herd listed Claude sessions from transcripts written in the last day,
whether or not a process was still running, so a closed session read "Waiting
on you" and the AI tab counted 27.

- **Claude: done** (`9792ff6`, Mac 0.1.78). A finished session with no running
  process is history. The running list comes from `~/.claude/sessions/*.json`
  where those still carry a session id, and from `claude agents --json` where
  Claude Code 2.1.325 no longer writes one. Checked live: linux went from three
  waiting to the one session actually running.
- **Codex: todo.** Most of what still reads "waiting" is Codex, chiefly
  "Guardian review" runs on the Air (eleven on 15 November). Codex has no list
  of running sessions to ask; Codex App Server thread status is the first-party
  candidate (see "Provider interfaces first").

### 13. The phone recovers when its watcher search breaks · `done`

After a network change the phone showed "Not updating … Can’t look for a
watcher: (Network.NWError error -65569 - DefunctConnection)" and stopped
reading. Two causes, both fixed in `9792ff6` (iPhone build 5): requests had no
timeout, so one stalled connection blocked every later read; and a failed
Bonjour search was never started again. Requests now give up after 15 s, and the
search restarts after a failure and when the app returns to the foreground.
Not yet seen recovering on the phone itself.

### 14. Tidy up after a moved session ends · `todo`

Every live move leaves three things behind on purpose, because the moved
session owns them: a worktree under `<repo>/.claude/worktrees/` on the
destination, a `transfer/...` branch there and on GitHub, and an entry in
`claude agents`. Nothing removes them once the session is over, so they pile up
with every move (three moves on 15 November left all three of each, cleaned by
hand).

Once a moved session has ended, Little Herd removes the worktree, `claude rm`s
the session and deletes the branch locally and on GitHub, **only when nothing
would be lost**: the session is not running, the worktree is clean, and every
commit on the branch is already on the default branch. Otherwise it keeps all of
it and says the work is still on the branch.

### 11. Answer a session from Little Herd · `todo`

For command-line sessions on our machines only: send one follow-up message and
approve or deny a permission request, without rendering whole conversations.
Claude through its stream-json mode (`claude -p --resume <id>
--input-format stream-json`, the Agent SDK's interface) with a permission-prompt
tool; Codex through `codex app-server`, which has approvals built in. Little
Herd must make sure only one place drives a session at a time.

---

## Blocked on the vendors

| Item                                     | Why                                                                                                                                                                                                                                                    | Unblocks when                                                                                                                        |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| Full conversation into Claude's cloud    | The CLI can't push a local session; Desktop's Open in → Cloud sends a summary and refuses SSH sessions                                                                                                                                                 | Anthropic ships a push ([claude-code#11455](https://github.com/anthropics/claude-code/issues/11455))                                 |
| Full conversation into Codex's cloud     | OpenAI doesn't support handoff to its cloud; cloud tasks return code, not chats                                                                                                                                                                        | OpenAI adds it ([codex#19657](https://github.com/openai/codex/issues/19657), [#34804](https://github.com/openai/codex/issues/34804)) |
| Full conversation, Codex → Claude        | Formats and tool calls don't map; only Codex imports the other way                                                                                                                                                                                     | Anthropic adds an import                                                                                                             |
| Chat by computer use in the desktop apps | Rejected on 15 November, not blocked: Claude desktop has Remote Control and ChatGPT has "Control this Mac", so a first-party route exists. Driving the screen needs the mini unlocked, breaks on app updates, and types into whatever window has focus | Never, while those routes exist                                                                                                      |
| Cloud moves between accounts             | Teleport works only within one account                                                                                                                                                                                                                 | Never: by design                                                                                                                     |

---

## The rest of the herd

Details for each are in `HANDOFF.md` under "Next".

| Item                                                        | Status    | Notes                                                                        |
| ----------------------------------------------------------- | --------- | ---------------------------------------------------------------------------- |
| A watcher that keeps running without the app open (item 18) | `doing`   | Alerts with nobody looking                                                   |
| Warnings before the drop                                    | `todo`    | Say what a move will refuse while dragging                                   |
| Quieter stall alerts                                        | `todo`    | Don't call a session stalled while it is thinking                            |
| Provider interfaces first                                   | `todo`    | Codex App Server thread metadata, `claude agents --json` before our probes   |
| Release verification                                        | `todo`    | A throwaway transfer per provider on the current macOS; keep macOS 15 checks |
| Flaky test                                                  | `todo`    |                                                                              |
| P-core / E-core awareness (item 2)                          | `blocked` | macOS gives no per-core readings                                             |
| Local models (item 10)                                      | `blocked` | Deferred until a local agent is worth watching                               |

---

## Watch list

Check at the start of any session that touches moves, transport or sessions:
`gh issue view <n> --repo <repo> --json state,updatedAt,comments`, and look for
an answer from the vendor. Update the dates here.

| Issue                                                                                  | Asks for                                | State, 15 November 2026                                                     |
| -------------------------------------------------------------------------------------- | --------------------------------------- | --------------------------------------------------------------------------- |
| [anthropics/claude-code#11455](https://github.com/anthropics/claude-code/issues/11455) | Session handoff and continuity          | Open (reopened); last activity 3 November; 42 comments, none from Anthropic |
| [openai/codex#19657](https://github.com/openai/codex/issues/19657)                     | Native remote session handoff           | Open; last activity 3 May                                                   |
| [openai/codex#34804](https://github.com/openai/codex/issues/34804)                     | Workspace continuity across devices     | Open; last activity 7 September                                             |
| [openai/codex#21803](https://github.com/openai/codex/issues/21803)                     | Cross-device sync of projects and chats | Open; last activity 9 November                                              |

Docs to re-read on the same occasions:
[Claude Code cloud sessions](https://code.claude.com/docs/en/claude-code-on-the-web),
[self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments),
[Agent SDK session storage](https://code.claude.com/docs/en/agent-sdk/session-storage),
[ChatGPT remote connections and Handoff](https://learn.chatgpt.com/docs/remote-connections),
[ChatGPT import from another agent](https://learn.chatgpt.com/docs/import),
[Codex app-server](https://developers.openai.com/codex/app-server.md).

---

## Done

- 15 Nov 2026 · A Claude session with no running process is no longer "waiting"; the phone's reads time out and its search restarts (`9792ff6`, Mac 0.1.78, iPhone build 5).
- 15 Nov 2026 · A moved Claude session stays on the destination as a background session, with the whole conversation (`4fe7a6e`, `9a90b30`, Mac 0.1.77).
- 15 Nov 2026 · The phone keeps hearing about a finished move for 15 minutes, so its sheet reaches the landing (`78f1164`, iPhone build 4).
- 15 Nov 2026 · A move started from a physical iPhone landed, mini to linux, with the full conversation (Mac 0.1.74, `ca23009`).
- 15 Nov 2026 · A move picks the agent that runs the session, and a step started from the Mac carries the account name (`3e9bd7e`, `ca23009`).
- 15 Nov 2026 · The phone's move sheet follows a move to its landing (`312703d`, iPhone build 3).
- 15 Nov 2026 · One phone server on the branch, pairing code accepted only over Tailscale, signed reads (`62192ad`).
- 27 Sep 2026 · A move through the phone path landed, mini to linux (`HANDOFF.md` item 6). Not yet started from a physical iPhone; that is item 3.
