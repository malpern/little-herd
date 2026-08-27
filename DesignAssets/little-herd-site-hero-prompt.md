# Little Herd website hero prompt

OpenAI images API, `gpt-image-2`, `POST /v1/images/edits` at `1536x1024`,
quality `high`, with **both** `little-herd-splash-art-source.png` and
`little-herd-app-icon-source.png` passed as `image[]` references so the
characters, materials, palette, and lighting carry over exactly.

The key that works is `OPENAI_API_KEY_PERSONAL` in sops. The plain
`OPENAI_API_KEY` in the same file is a different key and has **no credits** —
it fails with "You have no credits remaining", which reads like a broken key
rather than an empty account.

`little-herd-social-card-source.png` is not a separate generation. It is this
same image centre-cropped to 1536x806, the 1.91:1 that Open Graph wants, so
the hero and the social card cannot drift apart:

```sh
sips -c 806 1536 little-herd-site-hero-source.png -o little-herd-social-card-source.png
```

```text
Use case: stylized-concept. Asset type: full-bleed website hero banner for an
indie macOS app, wide 3:2 landscape.

Recompose the supplied Little Herd scene as a WIDE banner. Keep the exact same
three characters, materials, and lighting as the reference: the young
chestnut-and-cream calf, the yellow chick, and the pink piglet, gathered around
one softly glowing computer processor that emits restrained cyan and green
light.

Spread the composition horizontally for a wide screen. Place the calf left of
center and the piglet right of center, both lying down and leaning in, with the
chick standing behind the processor at center. Widen the deep forest-green and
teal workspace so there is generous calm negative space on the LEFT THIRD of
the frame, dark and low-detail, as safe space for a headline and a button to be
placed over it in HTML. Keep all faces and the processor in the right two
thirds, well away from crop edges.

Premium polished 3D character illustration: soft tactile materials, expressive
but restrained faces, elegant macOS-adjacent finish, charming without looking
like a children's game. Deep evergreen, muted teal, warm cream, chick yellow,
calf chestnut, piglet coral pink, restrained cyan and green highlights.
Cinematic soft key light.

No text, letters, logos, watermark, app-icon bezel, floating UI, extra animals,
extra computers, farm scenery, barn, hay, or rustic props.
```

## The variant that was rejected, and why it matters

A second concept was generated and thrown away: a wider scene showing four
*different* Herdware characters — chick-laptop, calf-mini, piglet-NAS,
ox-tower — arced across the ground with light threads running between them,
meant to say "several machines, one view" in a single picture. The idea is
still sound. The execution failed in three ways worth knowing before anyone
prompts it again.

It drew animals **using** laptops instead of animals **fused with** computers,
which is the whole visual grammar of the Herdware set and the thing that makes
those avatars read as machines rather than as pets. It added foliage despite
"no farm scenery". And it invented logos on the screens — a cloud, a wifi
glyph, and a fruit shape close enough to Apple's mark to be a real problem on a
page marketing a Mac app, despite the prompt saying "no logos".

The last one is the lesson. A negative instruction is not a guarantee, and the
failure here would have been a trademark exposure rather than an ugly picture.
**Look at every generated asset at full size before it goes near the site**,
specifically for invented marks on any surface that could hold one.
