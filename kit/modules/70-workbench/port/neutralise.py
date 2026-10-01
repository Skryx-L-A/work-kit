#!/usr/bin/env python3
"""Neutralise the build machine's private names in a workbench tree (regenerate step 5b).

    neutralise.py <dir>            rewrite <dir> in place, print what changed
    neutralise.py --check <dir>    list leftovers only (exit 1 when any)

The live workbench names the owner's local models, engines, second machine and notes store in
code, comments and tests. The kit ships none of them, so every occurrence is renamed the same
way in every file (code, tests and the extension source alike): behaviour stays, the private
name is gone. The external depersonalize tables (regenerate step 2) cover persons, hosts and
accounts; this table covers the setup vocabulary those tables leave alone.

Private network and hosting infrastructure (VPN, file sync, forge, hosting provider) is covered
too: the hosting provider is renamed like the models; the VPN and file-sync names have no
neutral rename (they sat in code and comments), so port/patches/ removes them and the gate
refuses a tree that still has one.

The names are stored rot13-encoded so that this table does not add them to the kit in plain
text (the same reason port/strip.txt writes host names as patterns). port/gate.py refuses a tree in
which TOKENS still match; tests/test-models.sh uses the same list.
"""
import codecs
import re
import sys
from pathlib import Path


def _d(s):
    return codecs.decode(s, "rot13")


def _cases(word, repl, before=r"", after=r""):
    """The lower, Title and UPPER spelling of word, each to the same spelling of repl."""
    out = []
    for f in (str.lower, lambda s: s[:1].upper() + s[1:], str.upper):
        out.append((re.compile(before + re.escape(f(word)) + after), f(repl)))
    return out


# Ordered: specific phrases first, then the bare names.
RENAMES = (
    # The notes store below $HOME becomes the kit brain folder.
    [(re.compile(r"(?<=[~/'\"])" + _d("Xabjyrqtr") + r"(?=[/'\"\s`),.;:-]|$)", re.M), "work/brain"),
     (re.compile(_d("Xabjyrqtr") + r"(?=[-/])"), "Brain"),
     (re.compile(re.escape(_d("30-gbcvpf"))), "topics")]
    + _cases(_d("zyk-ybxny"), "mlx-local")
    + _cases(_d("zyk_ybxny"), "mlx_local")
    + _cases(_d("djra3.8"), "lmgamma")
    + _cases(_d("djra38"), "lmgamma")
    + _cases(_d("beavgu"), "lmalpha")
    + _cases(_d("teht"), "lmbeta")
    + _cases(_d("fcynfu"), "enginex")
    + [(re.compile(re.escape(_d("bZYK"))), "engineY")]
    + _cases(_d("bzyk"), "enginey")
    + _cases(_d("inhyg"), "kbase")
    + _cases(_d("urgmare"), "hostco")
    # The second machine. Not the socket words (PEERCRED, PEERPID, peerToken of the mailbox)
    # and not npm's peerDependencies.
    + [(re.compile(r"(?<![a-z])" + _d("crre") + r"(?![a-z]|Dep|Token)"), "host2"),
       (re.compile(_d("Crre") + r"(?![a-z])"), "Host2"),
       (re.compile(r"(?<![A-Z_])" + _d("CRRE") + r"(?![A-Z])"), "HOST2")]
)

# Leftover check (gate, tests): case-insensitive, contents and paths.
TOKENS = [re.compile(p, re.I) for p in (
    _d("teht"), _d("beavgu"), _d("djra3\\.?8"), _d("fcynfu"), _d("bzyk"), _d("zyk[-_]ybxny"),
    r"[~/]" + _d("xabjyrqtr") + r"\b", _d("30-gbcvpf"), _d("inhyg"), _d("yycp"), _d("fxelk"),
    _d("yvyyrobe"), _d("gwbevpx"),
    # Private network and hosting infrastructure: VPN, file sync, forge, hosting provider.
    _d("gnvyfpnyr"), _d("gnvyarg"), r"\.ts\.net\b", _d("flapguvat"), _d("sbetrwb"), _d("urgmare"))] + [
    # The machine name: case-sensitive, same exceptions as the rename.
    re.compile(r"(?<![a-z])" + _d("crre") + r"(?![a-z]|Dep|Token)"),
    re.compile(_d("Crre") + r"(?![a-z])"),
    re.compile(r"(?<![A-Z_])" + _d("CRRE") + r"(?![A-Z])"),
]

SKIP_DIRS = {"node_modules", ".git", "__pycache__"}


def is_text(data):
    return b"\0" not in data[:8192]


def rewrite(text):
    n = 0
    for rx, repl in RENAMES:
        text, k = rx.subn(repl, text)
        n += k
    return text, n


def leftovers(text):
    return [m.group(0) for rx in TOKENS for m in rx.finditer(text)]


def files(root):
    for p in sorted(Path(root).rglob("*")):
        if p.is_file() and not SKIP_DIRS.intersection(p.parts) and p.suffix not in (".vsix", ".zip"):
            yield p


def apply(root):
    """Rewrite every text file (and path) below root; returns (files changed, replacements)."""
    changed = total = 0
    for p in list(files(root)):
        data = p.read_bytes()
        if is_text(data):
            text = data.decode("utf-8", "surrogateescape")
            new, n = rewrite(text)
            if n:
                p.write_bytes(new.encode("utf-8", "surrogateescape"))
                changed += 1
                total += n
        new_name, n = rewrite(p.name)
        if n:
            p.rename(p.with_name(new_name))
    return changed, total


def check(root):
    out = []
    for p in files(root):
        rel = p.relative_to(root).as_posix()
        if leftovers(rel):
            out.append(f"{rel}: path")
        data = p.read_bytes()
        if is_text(data):
            for i, line in enumerate(data.decode("utf-8", "replace").splitlines(), 1):
                hits = leftovers(line)
                if hits:
                    out.append(f"{rel}:{i}: {', '.join(sorted(set(hits)))}")
    return out


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        found = check(Path(sys.argv[2]))
        print("\n".join(found))
        sys.exit(1 if found else 0)
    if len(sys.argv) == 2:
        c, t = apply(Path(sys.argv[1]))
        print(f"   {t} private names neutralised in {c} files")
        sys.exit(0)
    sys.exit(__doc__)
