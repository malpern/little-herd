# Little Herd — website copy

The words come before the HTML, because the layout follows the words rather
than the other way round. This is the source; the page quotes it. When a line
changes here it changes there.

## Voice

Sound like the app, not like software marketing. The app's own prose — the
README, the handoff, the tooltips — is plainspoken, specific, and explains
itself. It prefers a measured number to an adjective. Keep that.

Four rules, each of which is a thing the first draft did wrong:

**Say the concrete thing.** "One short read-only command over SSH every ten
seconds" beats "lightweight agentless monitoring." The audience is people who
own four computers on purpose; they can read a sentence with a protocol in it,
and they distrust one without.

**No superlatives and no adjective stacking.** Not "beautiful, powerful,
blazingly fast." The screenshots carry beauty and the reader decides about
power. Every adjective spent on the app is one the reader has to discount.

**Never claim what the app does not do.** It does not dispatch work, it does
not move tasks, it does not manage machines. It watches. A monitor that
oversells becomes a monitor you cannot trust, which is the one thing a monitor
cannot survive.

**Warmth comes from the animals, not from the prose.** The characters are
already charming. If the writing is *also* whimsical it tips into twee and the
technical reader leaves. Let the art be warm and the words be dry — the
contrast is the whole personality.

---

## Hero

> # Stop running four computers. Run a herd.
>
> A laptop. A mini that used to be your desktop. A Linux box you built for one
> project. A NAS with the backups on it. Right now they are four islands — here
> is how they become one herd, and one small window to watch it.
>
> **[ Start a herd ]**  **[ Download Little Herd ]**
> Free while in development · macOS 15 or later · Apple silicon and Intel

Set over the calm left third of the hero art.

The headline had to do two jobs in seven words: say there are *several*
machines, and say the window is *small*. "Little window" also quietly explains
the name. Alternatives that lost: "Watch over your whole herd" (says nothing
about computers to someone who arrives cold), "A menu-bar monitor for all your
machines" (accurate, and reads like a directory listing).

**Say the price state in the hero.** "Free while in development" is four words
that stop someone hunting for a pricing page and set up a later change without
promising anything. Do not write "free forever," which is a promise the plan
does not make, and do not write "free" alone, which implies one.

---

## Section 1 — the category

> ## Every other monitor watches one machine.
>
> You have a laptop, a mini under the desk, a Linux box in the closet, and a
> NAS with the backups on it. Your system monitor shows you exactly one of
> them.
>
> Little Herd shows them side by side — one bar per machine, its name and its
> face underneath, a green dot when it's live and a red one when it isn't. One
> glance answers the question you actually have: which machine is busy, and is
> anything down?

This goes first because it is the category, and because it is the sentence
that makes someone recognise themselves. It names the reader's own hardware
back to them before it says anything about the product.

---

## Section 2 — the differentiator

> ## See which agent is working, and where.
>
> Claude Code and Codex sessions across every machine in the herd: the project
> each one is in, whether it's running, waiting for you, or finished, and how
> far through its plan it has got.
>
> Little Herd reads session metadata only — never your prompts, your
> responses, your command lines, or your keys. Nothing is sent anywhere.

Second, not first. The herd is the category and this is the thing nothing else
does, and a reader has to know what kind of app this is before a differentiator
means anything.

The privacy sentence belongs *here*, attached to the feature that raises the
worry, rather than saved for the privacy section. A reassurance three screens
after the alarm arrives too late.

---

## Section 3 — the objection

> ## Nothing to install on the other machines.
>
> No agent. No daemon. No password, no root, no companion app. Little Herd
> runs one short read-only command over the SSH connection you already have,
> once every ten seconds.
>
> If you can `ssh` to it, Little Herd can watch it.
>
> Your keys stay in your SSH config — Little Herd stores a hostname and,
> if you use one, the path to an identity file. A Synology is the one machine
> that needs an account, and its password goes in the login keychain, never in
> preferences.

This is the section that closes the sale for this audience. Anyone who has
installed a monitoring agent on four machines and then had to upgrade it on
four machines knows exactly what it is worth.

"If you can `ssh` to it, Little Herd can watch it" is the line to keep if the
section has to be cut for space. Set the `ssh` in code type.

---

## Section 4 — Herdware

> ## Every machine gets a face.
>
> Twelve of them: laptop, mini, studio, all-in-one, NUC, edge box, NAS, tower,
> GPU workstation, rack, coordinator, and cloud. Little Herd guesses which one
> fits while it's discovering your machines. You get the last word.

Then the contact sheet, or a selection from it, at full width.

Keep it short. The picture is the argument, and a paragraph explaining why the
avatars are nice would undo them.

---

## Section 5 — the rest, as a grid

Small cards, three or four across. Each is a title and one sentence. No
adjectives.

> **Memory pressure, not memory used**
> macOS's own normal, warning, and critical states — so cache doing its job
> doesn't read as a problem.
>
> **Possible leaks, marked**
> An app whose memory has grown steadily across seven readings gets a red dot,
> with the measured growth behind it.
>
> **The volume that runs out first**
> Each machine's fullest disk, with free space underneath. APFS volumes
> sharing a container are counted once.
>
> **What's actually running**
> Per-machine process lists with approximate core usage, each with its own
> app icon.
>
> **It reconnects by itself**
> A machine that sleeps keeps its last values and says *Unavailable*, with a
> tooltip saying why. No dialog.
>
> **Signed, notarized, and updates itself**
> Developer ID and Apple notarization, with automatic updates.

The leak card says "possible" on purpose. Trend sampling cannot prove that
allocations are unreachable, the app's own tooltip says so, and the site must
not be braver than the app.

---

## Section 6 — the licence

> ## The source is public.
>
> Read it, build it, change it, ship it inside your own work — anything except
> selling a competing product. Two years after each release goes out, that
> release becomes MIT.

One sentence of plain words, then the badge for people who want the string.
`FSL-1.1-MIT` means nothing to almost everyone; a badge alone is a puzzle, and
this audience will not download an app whose licence they cannot parse.

---

## Footer CTA

> ## Point it at your herd.
>
> **[ Download for macOS ]**
> Free while in development · macOS 15 or later
>
> Source on GitHub · Release notes · Licence

---

## Reserved, not written

The layout keeps a slot between section 5 and the licence for a price block,
so pricing can arrive without a redesign. Nothing goes in it now, and the hero
does not hint at it beyond "while in development."

---

## Coming soon — labelled, not implied

Two sections describe work that is **not built**. Each carries a "Coming soon"
pill and sits on its own tinted ground, and every sentence in them is future
tense. That is what makes them honest: the copy rule is never to claim what the
app does not do, and a plainly labelled intention is not a claim.

> **Move a session to the machine that's free.**
>
> Your laptop is compiling and the mini is idle. Little Herd will stop a Claude
> or Codex session on one machine and start its successor on another, with the
> work intact.
>
> Not process migration — that isn't possible and isn't wanted. The session
> writes its full context, and a transfer branch carries that plus anything
> uncommitted, so the destination checks out one ref and has all of it at once.
>
> Your machines share one account, so a move rebalances silicon, not tokens.
> Little Herd will say so rather than let you move a session for a reason it
> cannot deliver. Machine to machine only: your phone can start a transfer and
> watch it, but is never a destination.

> **Cloud work, in the same window.**
>
> Codex cloud tasks listed beside your machines, so the herd is everything
> working for you rather than everything you own.
>
> Moving cloud work down to a machine will use each vendor's own command, never
> a protocol of Little Herd's. The two are honestly different and the interface
> will say so: Codex cloud tasks can be listed, while Claude sessions can only
> be pulled by id, because nothing can enumerate them from here.

Both are compressed from `HANDOFF.md` items 4 and 8, including the constraints
— "silicon, not tokens", the phone never being a destination, the vendors' own
commands. Those limits are the most credible thing in the section. A roadmap
that lists only upside reads as a wish; one that states what it will refuse to
do reads as a plan.

**When transfer ships, watching stays the headline.** Moving becomes a strong
section and not the thesis, because watching is the everyday use and the reason
it lives in the menu bar, while moving is occasional. It also means the product
does not collapse if the transfer proves finicky in practice.

---

## Motion

Two animations, both meaning something, and nothing decorative.

**The wordmark's dot breathes** on a 4.5s cycle, because it *is* a status
light. It sits inside the `<use>` shadow tree where no selector reaches it, so
the colour animates through the `--dot` custom property — which has to be
registered with `@property` as a `<color>`, or it steps instead of fading.

**The Herdware avatars lift on hover.** They read as toys; they should feel
like you could pick one up.

Both sit inside `prefers-reduced-motion: no-preference`. Scroll-reveals, fades
and parallax were left out: they are what a generated page looks like, and this
page has a real mark and real toys to spend motion on instead.

---

## The live panel

Three sections carry a working miniature of the app window instead of a
screenshot: the CPU overview, the AI panel, and a machine's own Disk page.

It earns the space by teaching, and it has to match the app move for move.
Clicking a bar opens that machine through the current metric; the bar travels
out of the overview and **grows**, staying on the left with the value above it
and the avatar and name below, and that whole column is a second way back
beside the chevron. The detail sits to its right behind a divider, under the
app's own titles — WHAT'S RUNNING, WHAT'S USING MEMORY, VOLUMES. The metric
picker comes along, so switching lens re-lenses the machine you are on rather
than returning you to the herd.

The first version of this got it wrong by keeping only the list: the grown bar
vanished, the avatar moved into the header, and the detail filled the width.
It read as a plausible drill-in and was not the app's. Sessions arrive, wait and finish on their own, which is what the AI panel
looks like over a minute.

**It used to demonstrate hovering a machine to put it in the header. The app
removed that, so the page removed it too** — along with the screenshot of it.
A page that demonstrates a feature the product no longer has is worse than a
page with no demo at all, because everything else on it then reads as a guess.

**It is labelled "A working recreation".** Everything it does is something the
app does, but the numbers are invented and the caption says so rather than
letting anyone take it for a screenshot.

Machine columns are focusable and open on Enter or Space. The session rows are
deliberately *not* focusable, because nothing happens when you activate one and
a tab stop that leads nowhere is worse than no tab stop.


---

## Positioning: the herd is the idea, the app is the payoff

The word *herd* used to be decoration. The site said it constantly and never
taught it, so a visitor who did not already think this way read it as a name
for the animals. It is a claim now, and the page makes it.

**The hero sells the practice.** "Stop running four computers. Run a herd."
Then the reader's own hardware named back to them — a laptop, a mini that used
to be your desktop, a Linux box you built for one project, a NAS with the
backups — and the promise that those four islands can be one herd. Two calls to
action, the guide first and the download second.

**Then: what makes a herd.** Four properties, none of which is Little Herd and
none of which costs money — one network, one way in, the same tools everywhere,
work that outlives the connection. Saying plainly that the product is not
required is what makes the rest of the page believable.

**Only then the monitor.** "And one window that watches all of it." The old
line, "every other monitor watches one machine", was competing inside the
monitor category on its terms. This audience is not shopping for a monitor;
they have just realised the mini under the desk could be doing something.

## The guide — `herd.html`

Six steps, in order, each assuming the last: Tailscale, SSH config, Homebrew and
a Brewfile, tmux, Screen Sharing, and Herdr. Little Herd is the payoff at the
end and is not one of the six.

**Every step carries its trap**, and the traps are the reason to read it rather
than any of the thousand existing tutorials: a Tailscale key that expires and
silently drops an unattended box off the network; an SSH key with a passphrase
that no scheduled job can ever use; a non-interactive shell that never gets
Homebrew on its PATH, so everything works while you type and fails when it runs
alone; tmux started on the wrong machine; a macOS privacy prompt that only ever
appears on the machine's own screen.

**It is deliberately finite.** Six steps, written once, true for years. A guide
section that turns into a blog with three posts and a two-year gap reads as an
abandoned project, which is worse than not having one.

**The generic version of this loses.** "What is SSH" competes with a million
pages. The angle has to stay this specific setup — a few Macs, a Linux box, a
NAS, at home, increasingly running agents.

## Still needed

Fresh screenshots, and one of the AI view — the section that names the thing
nothing else does currently runs without a picture, because the only shots on
hand show CPU and memory and pairing either with it would illustrate a claim it
does not make.

The wordmark is done: Gabarito 600, outlined, with the *i*'s tittle as the
green status dot. It sits beside the app icon in the header and alone in the
footer.
