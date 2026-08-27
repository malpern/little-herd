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

> # All your computers. One little window.
>
> Little Herd watches your Mac, your other Macs, your Linux boxes and your NAS
> from the menu bar — CPU, memory, disk, and which AI agents are running where.
>
> **[ Download for macOS ]**
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

## Still needed

Fresh screenshots, and one of the AI view — the section that names the thing
nothing else does currently runs without a picture, because the only shots on
hand show CPU and memory and pairing either with it would illustrate a claim it
does not make.

The wordmark is done: Gabarito 600, outlined, with the *i*'s tittle as the
green status dot. It sits beside the app icon in the header and alone in the
footer.
