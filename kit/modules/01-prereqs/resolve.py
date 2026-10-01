#!/usr/bin/env python3
"""Resolve the dependency closure of the 01-prereqs items against Ubuntu Packages indexes.

Build-host helper for fetch.sh (Python 3.9+, standard library only, no network). It reads
indexes that fetch.sh already downloaded and verified (InRelease signature), checks every
Packages.xz against the SHA256 list in its InRelease, and writes for one release:

  <out>/<release>.lock   one line per package: name version sha256 size filename url items
  <out>/Packages         apt index for the offline repository (flat repo, Filename = pool/...)

Method: for each item, walk Pre-Depends and Depends (not Recommends) breadth first. For every
dependency the highest version across release, -updates and -security is used; alternatives
("a | b") take the first one that a real package or a provider satisfies, preferring packages
already chosen. The closure is complete down to libc6, so apt on the laptop finds every package
it may be missing. Resolution is deterministic for a fixed snapshot and fixed pins.

Usage:
  resolve.py --release noble --index-dir DIR --items items.conf --vendor NAME=INRELEASE=... ...
             --snapshot-url URL --out DIR
"""
import argparse
import hashlib
import lzma
import os
import re
import sys
from collections import OrderedDict

# --- Debian version comparison (dpkg verrevcmp) -------------------------------------------------


def _order(c):
    if c == "":
        return 0
    if c.isdigit():
        return 0
    if c.isalpha():
        return ord(c)
    if c == "~":
        return -1
    return ord(c) + 256


def _verrevcmp(a, b):
    i = j = 0
    while i < len(a) or j < len(b):
        first_diff = 0
        while (i < len(a) and not a[i].isdigit()) or (j < len(b) and not b[j].isdigit()):
            ac = _order(a[i] if i < len(a) and not a[i].isdigit() else "")
            bc = _order(b[j] if j < len(b) and not b[j].isdigit() else "")
            if ac != bc:
                return ac - bc
            i += 1
            j += 1
        while i < len(a) and a[i] == "0":
            i += 1
        while j < len(b) and b[j] == "0":
            j += 1
        while i < len(a) and j < len(b) and a[i].isdigit() and b[j].isdigit():
            if not first_diff:
                first_diff = ord(a[i]) - ord(b[j])
            i += 1
            j += 1
        if i < len(a) and a[i].isdigit():
            return 1
        if j < len(b) and b[j].isdigit():
            return -1
        if first_diff:
            return first_diff
    return 0


def _split(v):
    epoch = 0
    if ":" in v:
        e, v = v.split(":", 1)
        epoch = int(e)
    if "-" in v:
        up, rev = v.rsplit("-", 1)
    else:
        up, rev = v, ""
    return epoch, up, rev


def vercmp(a, b):
    ea, ua, ra = _split(a)
    eb, ub, rb = _split(b)
    if ea != eb:
        return -1 if ea < eb else 1
    r = _verrevcmp(ua, ub)
    if r:
        return 1 if r > 0 else -1
    r = _verrevcmp(ra, rb)
    return (r > 0) - (r < 0)


def version_ok(have, op, want):
    if op is None:
        return True
    c = vercmp(have, want)
    return {"<<": c < 0, "<=": c <= 0, "=": c == 0, ">=": c >= 0, ">>": c > 0,
            "<": c <= 0, ">": c >= 0}[op]


# --- index parsing ----------------------------------------------------------------------------


def parse_stanzas(text):
    for block in re.split(r"\n\s*\n", text):
        if not block.strip():
            continue
        fields = OrderedDict()
        key = None
        for line in block.split("\n"):
            if line.startswith((" ", "\t")) and key:
                fields[key] += "\n" + line
            elif ":" in line:
                key, val = line.split(":", 1)
                fields[key] = val.strip()
        yield fields


REL_RE = re.compile(r"^\s*([a-z0-9][a-z0-9.+-]*)(?::[a-z0-9-]+)?\s*(?:\(\s*(<<|<=|=|>=|>>|<|>)\s*([^)\s]+)\s*\))?\s*$")


def parse_relations(value):
    """'a (>= 1) | b, c' -> [[(a, '>=', '1'), (b, None, None)], [(c, None, None)]]"""
    groups = []
    for part in value.split(","):
        part = part.strip()
        if not part:
            continue
        alts = []
        for alt in part.split("|"):
            alt = re.sub(r"\[[^]]*\]|<[^>]*>", "", alt)  # arch and build-profile restrictions
            m = REL_RE.match(alt)
            if not m:
                raise ValueError("cannot parse relation: %r" % alt)
            alts.append((m.group(1), m.group(2), m.group(3)))
        groups.append(alts)
    return groups


def inrelease_sums(path):
    """SHA256 (else SHA512) section of an InRelease file -> {relative path: (algo, hex, size)}"""
    sections = {}
    cur = None
    for line in open(path, encoding="utf-8"):
        if line.startswith(("SHA256:", "SHA512:")):
            cur = sections.setdefault(line[:6].lower(), {})
            continue
        if cur is not None:
            if not line.startswith(" "):
                cur = None
                continue
            digest, size, name = line.split()
            cur[name] = (digest, int(size))
    algo = "sha256" if "sha256" in sections else "sha512"
    return {k: (algo, d, n) for k, (d, n) in sections.get(algo, {}).items()}


def check_listed(inrelease, rel, path):
    want = inrelease_sums(inrelease).get(rel)
    if want is None:
        raise SystemExit("%s: %s is not listed" % (inrelease, rel))
    h = hashlib.new(want[0])
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    if h.hexdigest() != want[1]:
        raise SystemExit("%s does not match %s" % (path, inrelease))


class Archive:
    def __init__(self):
        self.best = {}         # name -> stanza (highest version), stanza has _url
        self.provides = {}     # virtual name -> [(provider, provided version or None)]

    def add(self, stanza, base_url):
        if stanza.get("Architecture") not in ("amd64", "all"):
            return
        name = stanza["Package"]
        stanza["_url"] = base_url.rstrip("/") + "/" + stanza["Filename"]
        old = self.best.get(name)
        if old is None or vercmp(stanza["Version"], old["Version"]) > 0:
            self.best[name] = stanza

    def finish(self):
        self.provides = {}
        for name in sorted(self.best):
            st = self.best[name]
            for group in parse_relations(st.get("Provides", "")):
                for pname, _op, pver in group:
                    self.provides.setdefault(pname, []).append((name, pver))

    def candidates(self, rel):
        name, op, ver = rel
        out = []
        st = self.best.get(name)
        if st and version_ok(st["Version"], op, ver):
            out.append(name)
        for prov, pver in self.provides.get(name, []):
            if op is None or (pver is not None and version_ok(pver, op, ver)):
                if prov not in out:
                    out.append(prov)
        return out


def resolve(archive, roots, log):
    """roots: list of package names -> ordered list of package names in the closure"""
    chosen = OrderedDict()
    queue = list(roots)
    for r in roots:
        if r not in archive.best:
            raise SystemExit("package not found in any index: %s" % r)
    while queue:
        name = queue.pop(0)
        if name in chosen:
            continue
        chosen[name] = True
        st = archive.best[name]
        rels = parse_relations(st.get("Pre-Depends", "")) + parse_relations(st.get("Depends", ""))
        for group in rels:
            pick = None
            options = []
            for alt in group:
                options.extend(c for c in archive.candidates(alt) if c not in options)
            for c in options:           # something already chosen satisfies the group
                if c in chosen or c in queue:
                    pick = c
                    break
            if pick is None:
                for alt in group:       # first alternative that can be satisfied
                    cands = archive.candidates(alt)
                    if not cands:
                        continue
                    real = [c for c in cands if c == alt[0]]
                    pick = real[0] if real else cands[0]
                    if not real and len(cands) > 1:
                        log("note: %s: virtual %s has providers %s, using %s"
                            % (name, alt[0], " ".join(cands), pick))
                    break
            if pick is None:
                text = " | ".join("%s%s" % (n, " (%s %s)" % (o, v) if o else "") for n, o, v in group)
                raise SystemExit("unsatisfiable dependency of %s: %s" % (name, text))
            if pick not in chosen and pick not in queue:
                queue.append(pick)
    return list(chosen)


def load_items(path):
    items = OrderedDict()
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        cols = [c.strip() for c in line.split("|")]
        item_id, pkgs = cols[0], cols[3].split()
        if pkgs:
            items[item_id] = pkgs
    return items


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--release", required=True)
    ap.add_argument("--index-dir", required=True,
                    help="dir with <suite>.InRelease and <suite>/<comp>/Packages.xz")
    ap.add_argument("--snapshot-url", required=True)
    ap.add_argument("--components", default="main universe")
    ap.add_argument("--items", required=True)
    ap.add_argument("--vendor", action="append", default=[],
                    help="NAME=INRELEASE=PACKAGES=BASEURL=PACKAGE=VERSION (third-party .deb)")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    log = lambda m: print("[resolve %s] %s" % (a.release, m), file=sys.stderr)
    archive = Archive()
    for suite in (a.release, a.release + "-updates", a.release + "-security"):
        for comp in a.components.split():
            path = os.path.join(a.index_dir, suite, comp, "Packages.xz")
            check_listed(os.path.join(a.index_dir, suite + ".InRelease"),
                         "%s/binary-amd64/Packages.xz" % comp, path)
            with lzma.open(path, "rt", encoding="utf-8") as f:
                for st in parse_stanzas(f.read()):
                    archive.add(st, a.snapshot_url)

    for spec in a.vendor:
        vname, inrel, pfile, base, pkg, ver = spec.split("=", 5)
        check_listed(inrel, "main/binary-amd64/Packages", pfile)
        found = None
        with open(pfile, encoding="utf-8") as f:
            for st in parse_stanzas(f.read()):
                if st.get("Package") == pkg and st.get("Version") == ver:
                    found = st
        if not found:
            raise SystemExit("%s: %s %s not in %s (pin outdated? see README)" % (vname, pkg, ver, pfile))
        found["_url"] = base.rstrip("/") + "/" + found["Filename"]
        found["Filename"] = "pool/%s/%s" % (vname, os.path.basename(found["Filename"]))
        archive.best[pkg] = found
    archive.finish()

    items = load_items(a.items)
    owner = OrderedDict()   # package -> [items]
    for item_id, roots in items.items():
        missing = [r for r in roots if r not in archive.best]
        if missing:
            log("item %s skipped: not in %s: %s" % (item_id, a.release, " ".join(missing)))
            continue
        for p in resolve(archive, roots, log):
            owner.setdefault(p, []).append(item_id)

    os.makedirs(a.out, exist_ok=True)
    total = 0
    with open(os.path.join(a.out, a.release + ".lock"), "w", encoding="utf-8") as lock, \
            open(os.path.join(a.out, "Packages"), "w", encoding="utf-8") as idx:
        lock.write("# 01-prereqs apt closure for %s, generated by resolve.py from %s\n"
                   % (a.release, a.snapshot_url))
        lock.write("# package version sha256 size filename url items\n")
        for name in sorted(owner):
            st = archive.best[name]
            total += int(st["Size"])
            lock.write("%s %s %s %s %s %s %s\n" % (name, st["Version"], st["SHA256"], st["Size"],
                                                   st["Filename"], st["_url"], ",".join(owner[name])))
            for k, v in st.items():
                if not k.startswith("_"):
                    idx.write("%s: %s\n" % (k, v))
            idx.write("\n")
    log("%d packages, %.1f MB" % (len(owner), total / 1e6))


if __name__ == "__main__":
    main()
