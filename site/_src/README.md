# Building the site

`index.html` and `herd.html` are **generated**. Edit the sources here and run:

```sh
python3 site/_src/build.py
```

| file | what it is |
|---|---|
| `steps.py` | The eight guide steps **and** the homepage card for each. One entry per step; the guide and the card take the tool name and the anchor from the same place, which is what stops the two pages drifting. |
| `partials/` | `head`, `header`, `footer` — the chrome, which used to be copied into both pages. |
| `index.page`, `herd.page` | Everything between the header and the footer, verbatim, with a slot where the generated cards or steps go. |
| `build.py` | Fills the slots. No dependencies. |

## Why a script and not Vite

The two things that actually hurt were the chrome being duplicated and eight
hand-written steps the homepage cards had to be kept in step with — which twice
they were not. Both are fixed by ~170 lines with no dependencies, so the Pages
deploy stays "upload a folder", a bad transitive dependency cannot break the
website, and there is no second ecosystem to maintain beside a Swift app.

Revisit a real framework at five-plus pages or a blog, and prefer Astro over
bare Vite — this is a content site, not an app.

## `--check`

`python3 site/_src/build.py --check` rebuilds into memory and compares. The
Pages workflow runs it, so a page edited by hand instead of through here fails
the deploy rather than being silently overwritten by the next build.

## The trap this already caught

The first version took everything between `</header>` and `<footer>` as the
page body — and `<script src="demo.js">` lives *after* the footer. The build
dropped it, every page still rendered perfectly, and all three live panels were
dead. Anything after `</footer>` has to be declared in the page's `scripts`
slot. **Verify a build by comparing the rendered page, not the source**: the
source diff looked like nothing but an entity and a moved `<link>`.

## Where the tool marks come from

`logos/` holds one 24×24 SVG per step, inlined by the builder so each takes
`currentColor` and costs no request.

**Tailscale, Homebrew and tmux are real brand marks** from
[Simple Icons](https://simpleicons.org), which releases the icon files under
**CC0 1.0**. The hardcoded fill is stripped so they theme with the page. The
trademarks remain their owners'; naming a tool you are telling someone to
install is referential use, which is what these are for.

**The other five are drawn**, and deliberately so:

- **OpenSSH has no mark.**
- **Apple's would imply an endorsement nobody gave**, so Screen Sharing and
  Time Machine get a display and a clock instead. Apple's guidelines are the
  strictest of any vendor here; do not put the Apple logo on this site.
- **Herdr's is Apache-2.0**, which grants no trademark rights, and it sits on a
  solid background that will not theme.

**OpenAI's mark is the one exception to the caution above**, and it is a
considered one. `logos/openai.svg` is the knot from the Wikimedia ChatGPT SVG —
one petal rotated six times — recoloured to `currentColor`. OpenAI's brand
guidelines permit third-party referential use on two conditions, and the button
meets both: it must not imply endorsement, and it must not be more prominent
than your own mark. It is a 17px glyph in a button that says what it does, on a
page led by the Little Herd wordmark. Do not grow it, and do not put it
anywhere that reads as a badge of partnership.

Vendor *marketing* images are a separate question and the answer is mostly no:
Tailscale's press page states no usage terms at all, and a press kit is
conventionally for editorial coverage rather than for illustrating another
company's product site. Ask press@tailscale.com if you want them.
