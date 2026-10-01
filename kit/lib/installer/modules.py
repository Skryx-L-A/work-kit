"""Discover kit modules from kit/modules/*/ and read their module.conf."""
import os
import re

KNOWN_KEYS = ("name", "description", "depends", "after", "group", "needs_sudo", "default_on", "check", "install", "offline")


class Module:
    def __init__(self, mid, path):
        self.id = mid
        self.path = path
        self.name = mid
        self.description = ""
        self.depends = []
        self.after = []
        self.group = ""
        self.needs_sudo = False
        self.default_on = True
        self.check = ""
        self.install = "install.sh"
        self.offline = []
        self.has_conf = False
        self.problems = []

    def label(self):
        return "%s - %s" % (self.name, self.description) if self.description else self.name


def _readme_summary(path):
    """First heading line (title) and first prose line of README.md, if any."""
    title, prose = "", ""
    try:
        with open(os.path.join(path, "README.md"), encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                if line.startswith("#"):
                    title = title or line.lstrip("# ").strip()
                    continue
                if line.startswith("```"):
                    break
                prose = line
                break
    except OSError:
        pass
    return title, prose


def parse_conf(text, mod):
    """key=value lines; '#' starts a comment line; unknown keys are problems."""
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            mod.problems.append("module.conf line %d: expected key=value" % n)
            continue
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip()
        if key not in KNOWN_KEYS:
            mod.problems.append("module.conf line %d: unknown key '%s'" % (n, key))
        elif key == "depends":
            mod.depends = [d.strip() for d in value.split(",") if d.strip()]
        elif key == "after":
            mod.after = [d.strip() for d in value.split(",") if d.strip()]
        elif key == "offline":
            mod.offline = value.split()
        elif key == "needs_sudo":
            if value.lower() not in ("yes", "no"):
                mod.problems.append("module.conf line %d: needs_sudo must be yes or no" % n)
            mod.needs_sudo = value.lower() == "yes"
        elif key == "default_on":
            if value.lower() not in ("yes", "no"):
                mod.problems.append("module.conf line %d: default_on must be yes or no" % n)
            mod.default_on = value.lower() != "no"
        else:
            setattr(mod, key, value)


def discover(modules_dir):
    """Return modules sorted by folder name. A folder counts if it has install.sh or module.conf."""
    mods = []
    if not os.path.isdir(modules_dir):
        return mods
    for entry in sorted(os.listdir(modules_dir)):
        path = os.path.join(modules_dir, entry)
        conf = os.path.join(path, "module.conf")
        if not os.path.isdir(path) or not (os.path.exists(conf) or os.path.exists(os.path.join(path, "install.sh"))):
            continue
        mod = Module(entry, path)
        title, prose = _readme_summary(path)
        if not os.path.exists(conf):
            mod.problems.append("no module.conf (README first line used)")
            mod.name = title or entry
            mod.description = prose
        else:
            mod.has_conf = True
            mod.name = title or entry
            mod.description = prose
            with open(conf, encoding="utf-8") as fh:
                parse_conf(fh.read(), mod)
        if not os.path.exists(os.path.join(path, mod.install)):
            mod.problems.append("install script '%s' missing" % mod.install)
        mods.append(mod)
    return mods


def validate(mods):
    """Cross-module problems: unknown dependency, dependency cycle, group with depends on its own group."""
    ids = {m.id for m in mods}
    problems = []
    for m in mods:
        for p in m.problems:
            problems.append("%s: %s" % (m.id, p))
        for d in m.depends:
            if d not in ids:
                problems.append("%s: depends on unknown module %s" % (m.id, d))
        for a in m.after:
            if a not in ids:
                problems.append("%s: after unknown module %s" % (m.id, a))
            elif a == m.id:
                problems.append("%s: after names itself" % m.id)
        if re.search(r"\s", m.id):
            problems.append("%s: module folder name contains whitespace" % m.id)
    try:
        order(mods, {m.id for m in mods}, strict=True)
    except ValueError as exc:
        problems.append(str(exc))
    return problems


def order(mods, wanted, strict=False):
    """Dependencies first, then soft `after` neighbours that are also wanted, ties by folder name.
    Unknown modules are skipped. A cycle through `depends` raises; a cycle that needs an `after`
    edge is ignored (the soft edge is dropped) unless strict."""
    by_id = {m.id: m for m in mods}
    out, state = [], {}

    def visit(mid, chain, soft=False):
        if state.get(mid) == 2 or mid not in by_id:
            return
        if state.get(mid) == 1:
            if soft and not strict:
                return
            raise ValueError("dependency cycle: %s" % " -> ".join(chain + [mid]))
        state[mid] = 1
        for d in by_id[mid].depends:
            visit(d, chain + [mid])
        for a in by_id[mid].after:
            if a in wanted and a != mid:
                visit(a, chain + [mid], soft=True)
        state[mid] = 2
        if mid in wanted:
            out.append(by_id[mid])

    for m in mods:
        visit(m.id, [])
    return out


def resolve_ref(ref, mods):
    """Match 'id', numeric prefix ('20') or unique id prefix. Returns module or None."""
    for m in mods:
        if m.id == ref:
            return m
    hits = [m for m in mods if m.id.startswith(ref + "-")]
    return hits[0] if len(hits) == 1 else None
