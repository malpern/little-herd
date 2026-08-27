# Little Herd wordmark

`little-herd-wordmark.svg` — "Little Herd" in **Gabarito**, weight 600, with the
tittle of the *i* replaced by the app's green status dot.

**It is outlined paths, not text.** There is no webfont, no font file to ship,
and no chance of a substituted face on a machine that lacks Gabarito. It scales
to any size, weighs about 3 KB, and takes `currentColor` for the letters, so it
themes with whatever it sits on.

## The idea

The app's whole vocabulary for *this machine is alive* is a small green dot —
under every avatar on the dashboard, beside every name. The wordmark borrows
it: the dot over the *i* is that status light. It is the one place the mark
says something about what the product does, and it costs nothing, because the
letter already had a dot.

The dot is drawn about 12% larger than the tittle it replaces. At the original
size it reads as ordinary punctuation; slightly larger it reads as deliberate.

## Colour

Letters are `currentColor`. The dot takes `--dot`, which **inherits into the
`<use>` shadow tree where a class selector cannot reach** — that is why it is a
custom property rather than a class. The standalone `.svg` hard-codes
`#1F9E52` for use outside a page that defines the variable.

| where | `--dot` | why |
|---|---|---|
| over the dark hero | `#34C46F` | `#1F9E52` goes muddy on `#0C2B24` at 19px |
| light body / footer | `#1F9E52` | `HerdLoadGreen`, the app's own value |

## Regenerating it

`scripts/make-wordmark.swift` outlines the text with CoreText, splits the
result into subpaths, finds the tittle geometrically — a small, roughly square
subpath in the top third, left of centre — drops it, and writes a circle in its
place. It **fails loudly unless exactly one candidate matches**, so a font
change or a different string cannot silently produce a mark with two dots or
none.

```sh
swift scripts/make-wordmark.swift <font.ttf> 600 "Little Herd" out.svg "#1F9E52"
```

Gabarito is under the SIL Open Font License, which places no restriction on
artwork made from its outlines. The font file itself is not in this repo and
does not need to be — only the outlines are. Get it from
<https://fonts.google.com/specimen/Gabarito> if the mark ever needs redrawing.

## Why Gabarito

Five OFL faces were set and compared at 48, 19 and 13 px, which is the range
that matters — the site header sets it at 19. Fraunces and Instrument Serif are
handsomer at display size and both go fragile below 20 px, where most people
will meet this mark. Hanken Grotesk is clean and anonymous; it looks like every
other software site. Bricolage Grotesque was close and slightly wider.

Gabarito won because it is geometric enough to read as a system utility and
soft enough to rhyme with the toy-3D characters, and because it holds its
weight small. The art supplies the warmth here, the same rule the copy follows
— a rounder, friendlier face would have made it twee.

## The generated alternative, and why it lost

The same mark was put through the OpenAI images API (`gpt-image-2`) for
comparison — see `little-herd-wordmark-comparison.jpg`, which is the test that
settled it: both marks at 44 px and 19 px, on cream and on the hero's
evergreen.

**It did better than expected.** Both attempts spelled "Little Herd" correctly,
set it in a plausible geometric sans, and put a green dot over the *i* when
asked. On a light background at display size the first attempt is a credible
logo. Anyone claiming image models cannot do typography should look at it.

It lost on things that have nothing to do with how it looks:

**It has an opaque background.** The header sits on the dark hero. A generated
raster carries the cream it was drawn on, and in the comparison sheet that
cream box is impossible to miss. Keying it out would leave cream fringing on
every anti-aliased edge, and the letters would still be dark green — on a dark
ground they need to be near-white, which a raster cannot become.

**It cannot take `currentColor`.** The drawn mark is forest green on cream,
near-white on the hero, and muted grey in the footer, from one 3 KB file. The
generated one is one colour on one background, so the site would need a
separate export per context, each drifting from the others.

**It cannot be regenerated or edited.** `make-wordmark.swift` reproduces the
drawn mark byte-for-byte, and a weight, a string, or a dot size is an argument.
The generated mark cannot be reproduced at all, and no part of it can be
adjusted — a wordmark is the one asset most likely to need a variant.

**Its letterforms have no provenance.** They approximate some typeface nobody
can name. Gabarito is OFL, and the licence explicitly permits artwork made from
its outlines. For a logo — the asset that ends up on everything — knowing where
the shapes came from is worth more than a good first impression.

The dot placement is the small tell. In both generated attempts it sits
slightly left of the *i* stem, because it was drawn by eye. In the drawn mark
it is centred on the tittle's own measured bounding box, because it replaced
it.
