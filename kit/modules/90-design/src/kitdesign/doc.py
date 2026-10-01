"""Markdown document to print-ready HTML, PDF (headless Chromium-family browser) or DOCX (pandoc)."""

from __future__ import annotations

import base64
import html
import mimetypes
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
from importlib import resources
from pathlib import Path

import markdown

from .refs import Theme

BROWSERS = (
    "kit-chrome-headless", "chromium", "chromium-browser", "google-chrome", "google-chrome-stable", "microsoft-edge",
    "microsoft-edge-stable", "brave-browser",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/snap/bin/chromium",
)


class DocError(RuntimeError):
    pass


def _kit_bin_dirs() -> list[str]:
    """Where the kit installs kit-chrome-headless; PATH may lack it (non-login shell, ssh, cron)."""
    dirs = [os.environ.get("KIT_BIN_DIR", ""), str(Path.home() / ".local" / "bin")]
    return [d for d in dirs if d and Path(d).is_dir()]


def find_browser() -> str | None:
    env = os.environ.get("KIT_DESIGN_BROWSER")
    if env:
        return env
    # The bundled headless shell comes first: PATH, then the kit's own bin dirs.
    bundled = BROWSERS[0]
    for extra in (None, *_kit_bin_dirs()):
        p = shutil.which(bundled, path=extra)
        if p:
            return p
    for b in BROWSERS[1:]:
        p = shutil.which(b) if not b.startswith("/") else (b if Path(b).exists() else None)
        if p:
            return p
    return None


def split_front_matter(text: str) -> tuple[dict[str, str], str]:
    meta: dict[str, str] = {}
    lines = text.replace("\r\n", "\n").split("\n")
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() == "---":
                for ln in lines[1:i]:
                    if ":" in ln:
                        k, v = ln.split(":", 1)
                        meta[k.strip().lower()] = v.strip().strip("\"'")
                return meta, "\n".join(lines[i + 1:])
    return meta, text


def first_heading(text: str) -> str:
    """Return the first Markdown heading, without its optional closing hashes."""
    for line in text.splitlines():
        match = re.match(r"^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$", line)
        if match:
            return match.group(1).strip()
    return ""


def _drop_first_heading(text: str) -> str:
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if re.match(r"^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$", line):
            return "\n".join(lines[:i] + lines[i + 1:])
    return text


def _embed_images(body: str, base: Path, warnings: list[str]) -> str:
    def repl(m: re.Match) -> str:
        src = html.unescape(m.group(2))
        if re.match(r"^(data:|https?:)", src):
            return m.group(0)
        p = (base / src) if not Path(src).is_absolute() else Path(src)
        if not p.is_file():
            warnings.append(f"image not found: {p}")
            return m.group(0)
        mime = mimetypes.guess_type(p.name)[0] or "application/octet-stream"
        return f'{m.group(1)}data:{mime};base64,{base64.b64encode(p.read_bytes()).decode()}"'
    return re.sub(r'(<img[^>]*?src=")([^"]+)"', repl, body)


def to_html(src: Path, theme: Theme) -> tuple[str, list[str]]:
    warnings: list[str] = []
    meta, text = split_front_matter(src.read_text(encoding="utf-8"))
    heading = first_heading(text)
    if not meta.get("title") and heading:
        # The first heading becomes the page title; drop it from the body so it is not shown twice.
        text = _drop_first_heading(text)
    md = markdown.Markdown(extensions=["tables", "fenced_code", "toc", "attr_list", "sane_lists", "md_in_html"])
    body = md.convert(text)
    if meta.get("toc", "").lower() in ("1", "true", "yes"):
        body = f'<nav class="toc">{md.toc}</nav>' + body
    body = _embed_images(body, src.parent, warnings)
    title = meta.get("title") or heading or src.stem
    info = " &middot; ".join(html.escape(meta[k]) for k in ("author", "date", "version", "class") if meta.get(k))
    logo = ""
    if theme.logo:
        mime = mimetypes.guess_type(theme.logo.name)[0] or "image/png"
        logo = f'<img class="logo" alt="" src="data:{mime};base64,{base64.b64encode(theme.logo.read_bytes()).decode()}">'
    footer = " · ".join(v for v in (meta.get("title"), meta.get("version"), meta.get("class")) if v)
    css = resources.files("kitdesign").joinpath("templates/doc/print.css").read_text(encoding="utf-8")
    css = css.replace("/*TOKENS*/", theme.css_vars()).replace("/*FOOTER*/", footer.replace('"', "").replace("\\", ""))
    page = (
        f'<!doctype html>\n<html lang="{html.escape(meta.get("lang", "en"))}">\n<head>\n<meta charset="utf-8">\n'
        f"<title>{html.escape(title)}</title>\n<style>\n{css}</style>\n</head>\n<body>\n"
        f'<header class="doc-head">{logo}<h1>{html.escape(title)}</h1>'
        f'{f"<div class=meta>{info}</div>" if info else ""}</header>\n{body}\n</body>\n</html>\n'
    )
    return page, warnings


def to_pdf(html_file: Path, out: Path, timeout: int = 120) -> None:
    browser = find_browser()
    if not browser:
        raise DocError(
            "no Chromium-family browser found (kit-chrome-headless, chromium, google-chrome, microsoft-edge). "
            f"Open {html_file} in a browser and print to PDF, or set KIT_DESIGN_BROWSER."
        )
    out = out.resolve()
    out.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory() as prof:
        cmd = [browser, "--headless", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
               f"--user-data-dir={prof}", "--no-pdf-header-footer", f"--print-to-pdf={out}",
               html_file.resolve().as_uri()]
        # Some Chrome builds keep running after the PDF is written: wait for the file, not the exit.
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
                                start_new_session=True)
        deadline, last, stable = time.monotonic() + timeout, -1, 0
        try:
            while time.monotonic() < deadline and proc.poll() is None:
                size = out.stat().st_size if out.is_file() else -1
                stable = stable + 1 if size > 0 and size == last else 0
                last = size
                if stable >= 4:
                    break
                time.sleep(0.25)
        finally:
            if proc.poll() is None:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                    proc.wait(timeout=10)
                except (ProcessLookupError, subprocess.TimeoutExpired):
                    os.killpg(proc.pid, signal.SIGKILL)
                    proc.wait()
            err = proc.stderr.read() if proc.stderr else ""
    if not out.is_file() or out.stat().st_size == 0:
        raise DocError(f"browser did not write the PDF (exit {proc.returncode}): {err.strip()[-400:]}")


def to_docx(src: Path, out: Path, reference: Path | None) -> None:
    pandoc = shutil.which("pandoc")
    if not pandoc:
        raise DocError("pandoc not found (module 12-docs-tools installs it). Deliver PDF/HTML instead.")
    cmd = [pandoc, str(src), "-o", str(out), "--resource-path", str(src.parent)]
    if reference:
        cmd += ["--reference-doc", str(reference)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise DocError(f"pandoc failed: {r.stderr.strip()[-400:]}")
