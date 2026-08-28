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
