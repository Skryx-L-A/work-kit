"""kit-design command line."""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from importlib import resources
from pathlib import Path

from . import __version__
from .refs import CATEGORIES, find_template, load_theme, ref_files, refs_home


def _say(msg: str) -> None:
    print(f"kit-design: {msg}", file=sys.stderr)


def cmd_refs(a) -> int:
    cats = [a.category] if a.category else list(CATEGORIES)
    home = refs_home()
    report = {c: [str(p.relative_to(home / c)) for p in ref_files(c)] for c in cats}
    if a.json:
        print(json.dumps({"home": str(home), "exists": home.is_dir(), "files": report}, indent=2))
        return 0
    if not home.is_dir():
        print(f"{home} does not exist (install module 90-design or set DESIGN_REFS)")
        return 0
    for c, files in report.items():
        state = f"{len(files)} file(s)" if files else "empty"
        print(f"{c:10} {state:12} {home / c}")
        for f in files[:20]:
            print(f"           - {f}")
        if len(files) > 20:
            print(f"           ... {len(files) - 20} more")
    return 0


def _pick(kind: str, value: str | None, category: str, suffixes: tuple[str, ...]) -> Path | None:
    """--template/--reference: a path, 'none', or 'auto' (the only matching file in design-refs)."""
    if value == "none":
        return None
    if value and value != "auto":
        p = Path(value).expanduser()
        if not p.is_file():
            raise SystemExit(f"kit-design: {kind} not found: {p}")
        return p
    found = find_template(category, suffixes)
    if len(found) == 1:
        _say(f"using {kind} from design-refs: {found[0]}")
        return found[0]
    if len(found) > 1:
        _say(f"several {kind}s in {refs_home() / category}; pass one with --{kind}: "
             + ", ".join(p.name for p in found))
    return None


def _theme(a):
    t = load_theme(Path(a.theme).expanduser() if getattr(a, "theme", None) else None)
    for w in t.warnings:
        _say(f"warning: {w}")
    if t.source != "kit default":
        _say(f"theme from {t.source}")
    return t


def cmd_deck(a) -> int:
    from . import html_deck, pptx_build
    from .deck import DeckError, parse_file

    src = Path(a.source)
    try:
        deck = parse_file(src)
    except (OSError, DeckError) as e:
        _say(f"error: {e}")
        return 1
    outs = [Path(o) for o in a.output] or [src.with_suffix(".pptx"), src.with_suffix(".html")]
    theme = _theme(a)
    rc = 0
    for out in outs:
        ext = out.suffix.lower()
        if ext == ".pptx":
            tpl = _pick("template", a.template, "slides", (".pptx", ".potx"))
            warnings = pptx_build.build(deck, out, theme, tpl)
        elif ext in (".html", ".htm"):
            warnings = html_deck.build(deck, out, theme)
        else:
            _say(f"error: unsupported output {out} (use .pptx or .html)")
            rc = 1
            continue
        for w in warnings:
            _say(f"warning: {w}")
        print(f"wrote {out} ({len(deck.slides)} slides)")
    return rc


def cmd_doc(a) -> int:
    from .doc import DocError, to_docx, to_html, to_pdf

    src = Path(a.source)
    outs = [Path(o) for o in a.output] or [src.with_suffix(".html"), src.with_suffix(".pdf")]
    theme = _theme(a)
    try:
        page, warnings = to_html(src, theme)
    except OSError as e:
        _say(f"error: {e}")
        return 1
    for w in warnings:
        _say(f"warning: {w}")
    rc = 0
    for out in outs:
        ext = out.suffix.lower()
        try:
            if ext in (".html", ".htm"):
                out.write_text(page, encoding="utf-8")
            elif ext == ".pdf":
                with tempfile.TemporaryDirectory() as tmp:
                    h = Path(tmp) / "doc.html"
                    h.write_text(page, encoding="utf-8")
                    to_pdf(h, out)
            elif ext == ".docx":
                to_docx(src, out, _pick("reference", a.reference, "documents", (".docx",)))
            else:
                _say(f"error: unsupported output {out} (use .html, .pdf or .docx)")
                rc = 1
                continue
        except DocError as e:
            _say(f"error: {e}")
            rc = 1
            continue
        print(f"wrote {out}")
    return rc


def cmd_new(a) -> int:
    dest = Path(a.dir)
    root = resources.files("kitdesign").joinpath("templates")
    files = {
        "deck": {"deck.md": "deck/sample-deck.md"},
        "doc": {"document.md": "doc/sample-doc.md"},
        "web": {n: f"web/{n}" for n in ("index.html", "styles.css", "tokens.css", "app.js", "data.js", "README.md")},
    }[a.kind]
    dest.mkdir(parents=True, exist_ok=True)
    existing = [n for n in files if (dest / n).exists()]
    if existing and not a.force:
        _say(f"error: {dest} already has {', '.join(existing)} (use --force to overwrite)")
        return 1
    for name, rel in files.items():
        (dest / name).write_bytes(root.joinpath(rel).read_bytes())
    if a.kind == "web":
        t = _theme(a)
        (dest / "tokens.css").write_text(
            "/* Design tokens, generated by kit-design from " + t.source + ". */\n:root {\n" + t.css_vars() + "}\n",
            encoding="utf-8",
        )
    refs = {"deck": "slides", "doc": "documents", "web": "web"}[a.kind]
    have = ref_files(refs) + ref_files("brand")
    print(f"created {a.kind} in {dest}")
    if have:
        print(f"design references found: read {refs_home() / refs} and {refs_home() / 'brand'} before designing")
    else:
        print(f"no design references in {refs_home() / refs}; using kit defaults")
    return 0


def cmd_theme(a) -> int:
    t = _theme(a)
    print(json.dumps({"source": t.source, "colors": {k: getattr(t, k) for k in ("text", "background", "accent", "muted", "surface")},
                      "fonts": {"heading": t.heading_font, "body": t.body_font},
                      "logo": str(t.logo) if t.logo else None}, indent=2))
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="kit-design", description="Offline decks, documents and web prototypes.")
    p.add_argument("--version", action="version", version=__version__)
    sub = p.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("refs", help="list design references in ~/work/design-refs")
    r.add_argument("category", nargs="?", choices=CATEGORIES)
    r.add_argument("--json", action="store_true")
    r.set_defaults(fn=cmd_refs)

    d = sub.add_parser("deck", help="Markdown deck to .pptx and/or .html")
    d.add_argument("source")
    d.add_argument("-o", "--output", action="append", default=[], help="repeatable; default: <source>.pptx and .html")
    d.add_argument("--template", default="auto", help="company .pptx/.potx, 'auto' (the only one in design-refs/slides) or 'none'")
    d.add_argument("--theme", help="theme.json (default: design-refs/brand/theme.json)")
    d.set_defaults(fn=cmd_deck)

    o = sub.add_parser("doc", help="Markdown document to .html, .pdf and/or .docx")
    o.add_argument("source")
    o.add_argument("-o", "--output", action="append", default=[], help="repeatable; default: <source>.html and .pdf")
    o.add_argument("--reference", default="auto", help="DOCX reference doc, 'auto' (the only .docx in design-refs/documents) or 'none'")
    o.add_argument("--theme", help="theme.json (default: design-refs/brand/theme.json)")
    o.set_defaults(fn=cmd_doc)

    n = sub.add_parser("new", help="start a deck, document or web prototype from the kit template")
    n.add_argument("kind", choices=("deck", "doc", "web"))
    n.add_argument("dir")
    n.add_argument("--force", action="store_true")
    n.add_argument("--theme", help="theme.json for web tokens")
    n.set_defaults(fn=cmd_new)

    t = sub.add_parser("theme", help="show the colours and fonts in use")
    t.add_argument("--theme", help="theme.json to check")
    t.set_defaults(fn=cmd_theme)

    a = p.parse_args(argv)
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
