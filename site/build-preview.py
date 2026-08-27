#!/usr/bin/env python3
"""Fold index.html into one self-contained file for an Artifact preview.

The published page is served from site/ with its images beside it. An Artifact
is a single file behind a CSP that blocks every external host, so the preview
needs every asset inlined as a data: URI, and it must not carry its own
<!doctype>/<html>/<head>/<body> -- the publisher supplies that skeleton.

This exists only to look at the page before it is public. It is not part of
the deploy: the workflow uploads site/ as it stands.
"""
import base64
import pathlib
import re
import sys

here = pathlib.Path(__file__).parent
html = (here / "index.html").read_text()

MIME = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}


def inline(match):
    attr, path = match.group(1), match.group(2)
    f = here / path
    if not f.exists():
        sys.exit(f"missing asset: {path}")
    mime = MIME.get(f.suffix.lower())
    if not mime:
        sys.exit(f"unknown asset type: {path}")
    b64 = base64.b64encode(f.read_bytes()).decode()
    return f'{attr}="data:{mime};base64,{b64}"'


# src="images/…" in <img>, and url(images/…) in the hero's CSS background
html, n_src = re.subn(r'(src)="(images/[^"]+)"', inline, html)
html, n_css = re.subn(
    r'url\((images/[^)]+)\)',
    lambda m: "url(" + inline(re.match(r'()(.*)', m.group(1))).split('="', 1)[1].rstrip('"') + ")",
    html,
)

# strip the document skeleton the Artifact publisher supplies itself, and the
# metadata that only means something on a real origin
body = re.search(r"<body>(.*)</body>", html, re.S).group(1)
style = re.search(r"<style>.*?</style>", html, re.S).group(0)

out = "<title>Little Herd</title>\n" + style + "\n" + body

# Escape every non-ASCII character to a numeric entity. The <meta charset> went
# with the <head> we just stripped, and a host that assumes latin-1 renders the
# em dashes and middle dots as mojibake -- entities are correct either way.
out = "".join(c if ord(c) < 128 else f"&#{ord(c)};" for c in out)

(here / "preview.html").write_text(out, encoding="ascii")
print(f"preview.html: {len(out)/1e6:.1f} MB, inlined {n_src} images + {n_css} css")
