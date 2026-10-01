"""File helpers of kit-models: merge, ownership and backup rules of kit-sync (30-agent-setup).

Copied from kit-sync and reduced, so this module installs without 30-agent-setup. Same rules:
  - an existing file is never replaced without a backup (once per run) in
    <data dir>/backups/33-model-endpoints/<path below home>.bak-<timestamp>;
  - JSON: a key is written when it is missing, already has the value, or was written by
    kit-models before and not changed since; a value you set yourself is kept;
  - TOML/YAML/shell files: kit-models writes only inside its own delimited region; text
    outside the region is left alone;
  - files kit-models owns entirely carry a marker line and are removed only with that marker.
Ownership is recorded in ~/.local/share/work-kit/state/kit-models.json (never secrets).
"""
from __future__ import annotations

import json
import os
import re
import time
from pathlib import Path

MISSING = object()
REMOVE = object()
WRITE_ACTIONS = {"create", "update", "append", "link", "remove", "backup"}


class Ctx:
    def __init__(self, home: Path, dry_run: bool = False, quiet: bool = False):
        self.home = home
        self.dry_run = dry_run
        self.quiet = quiet
        self.stamp = time.strftime("%Y%m%d%H%M%S")
        self.data_dir = Path(os.environ.get("KIT_DATA_DIR") or home / ".local/share/work-kit")
        self.conf_dir = Path(os.environ.get("XDG_CONFIG_HOME") or home / ".config") / "work-kit"
        self.bin_dir = Path(os.environ.get("KIT_BIN_DIR") or home / ".local/bin")
        self.state_file = self.data_dir / "state/kit-models.json"
        self.state = self._load_state()
        self.state_dirty = False
        self.touched: set = set()
        self.log: list = []

    def say(self, action: str, path, note: str = "") -> None:
        prefix = "would " if self.dry_run and action in WRITE_ACTIONS else ""
        if isinstance(path, Path):
            path = tilde(self, path)
        line = f"[{prefix}{action}] {path}" + (f"  ({note})" if note else "")
        self.log.append(line)
        if not self.quiet:
            print(line)

    def backup(self, path: Path) -> None:
        if not (path.exists() or path.is_symlink()) or path in self.touched:
            return
        self.touched.add(path)
        dest = self.backup_dest(path)
        self.say("backup", path, f"-> {tilde(self, dest)}")
        if not self.dry_run:
            # copy, not rename: the harness keeps a valid file if we stop half-way
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(path.read_bytes())
            os.chmod(dest, path.stat().st_mode & 0o777)

    def backup_dest(self, path: Path) -> Path:
        """Backups live below the kit's data dir, never next to the user's file."""
        path = Path(os.path.abspath(path))
        try:
            rel = path.relative_to(self.home)
        except ValueError:
            rel = Path("_root") / path.relative_to(path.anchor)
        return self.data_dir / "backups" / "33-model-endpoints" / rel.parent / f"{rel.name}.bak-{self.stamp}"

    def write_text(self, path: Path, text: str, mode: int = None) -> None:
        self.touched.add(path)
        if self.dry_run:
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(f".{path.name}.kit-models-tmp")
        tmp.write_text(text, encoding="utf-8")
        if mode is not None:
            os.chmod(tmp, mode)
        elif path.exists():
            os.chmod(tmp, path.stat().st_mode & 0o777)
        os.replace(tmp, path)

    def _load_state(self) -> dict:
        try:
            data = json.loads(self.state_file.read_text(encoding="utf-8"))
            return data if isinstance(data.get("owned"), dict) else {"owned": {}}
        except (OSError, ValueError, AttributeError):
            return {"owned": {}}

    def owned(self, path: Path, keys: tuple):
        return self.state["owned"].get(json.dumps([str(path), *keys]), MISSING)

    def own(self, path: Path, keys: tuple, value) -> None:
        k = json.dumps([str(path), *keys])
        if self.state["owned"].get(k, MISSING) != value:
            self.state["owned"][k] = value
            self.state_dirty = True

    def disown(self, path: Path, keys: tuple) -> None:
        if self.state["owned"].pop(json.dumps([str(path), *keys]), MISSING) is not MISSING:
            self.state_dirty = True

    def owned_keys(self, path: Path, prefix: tuple = ()) -> list:
        out = []
        for k in self.state["owned"]:
            parts = json.loads(k)
            if parts[0] == str(path) and tuple(parts[1:1 + len(prefix)]) == prefix:
                out.append(tuple(parts[1:]))
        return out

    def save_state(self) -> None:
        if self.dry_run or not self.state_dirty:
            return
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        self.state_file.write_text(json.dumps(self.state, indent=2, sort_keys=True) + "\n",
                                   encoding="utf-8")
        os.chmod(self.state_file, 0o600)  # holds written values, among them the local proxy token
        self.state_dirty = False


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def tilde(ctx: Ctx, path: Path) -> str:
    try:
        return "~/" + str(Path(path).relative_to(ctx.home))
    except ValueError:
        return str(path)


# --- JSON -------------------------------------------------------------------------------------

def strip_jsonc(text: str) -> str:
    """Remove // and /* */ comments and trailing commas (VS Code settings, opencode.jsonc)."""
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
        elif text.startswith("//", i):
            while i < n and text[i] != "\n":
                i += 1
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(c)
            i += 1
    return re.sub(r",(\s*[}\]])", r"\1", "".join(out))


def load_json_obj(ctx: Ctx, path: Path, jsonc: bool = False):
    """dict of a JSON file ({} when missing), or None when it cannot be merged safely.
    jsonc=True accepts comments, but such a file is only written when it has none."""
    if not path.exists():
        return {}
    text = read(path)
    if not text.strip():
        return {}
    try:
        data = json.loads(text)
    except ValueError:
        if jsonc:
            try:
                json.loads(strip_jsonc(text))
                ctx.say("skip", path, "has comments; writing it would drop them. Add the "
                        "kit-models values by hand (kit-models show <name>)")
                return None
            except ValueError:
                pass
        ctx.say("skip", path, "not plain JSON; left untouched (kit-models show <name>)")
        return None
    if not isinstance(data, dict):
        ctx.say("skip", path, "not a JSON object; left untouched")
        return None
    return data


def get_in(d: dict, keys: tuple):
    for k in keys:
        if not isinstance(d, dict) or k not in d:
            return MISSING
        d = d[k]
    return d


def set_in(d: dict, keys: tuple, value) -> bool:
    for k in keys[:-1]:
        nxt = d.get(k)
        if nxt is None:
            nxt = d[k] = {}
        if not isinstance(nxt, dict):
            return False
        d = nxt
    d[keys[-1]] = value
    return True


def del_in(d: dict, keys: tuple) -> None:
    trail = []
    for k in keys[:-1]:
        if not isinstance(d.get(k), dict):
            return
        trail.append((d, k))
        d = d[k]
    d.pop(keys[-1], None)
    for parent, k in reversed(trail):
        if parent[k] == {}:
            del parent[k]
        else:
            break


def json_settings(ctx: Ctx, path: Path, wanted: dict, force: set = frozenset(),
                  jsonc: bool = False, mode: int = None) -> set:
    """Apply {keypath: value | REMOVE} to a JSON file (kit-sync rules, see module doc)."""
    data = load_json_obj(ctx, path, jsonc)
    if data is None:
        return set()
    before = json.dumps(data, sort_keys=True)
    applied = set()
    for keys, value in wanted.items():
        cur = get_in(data, keys)
        owned = ctx.owned(path, keys)
        if value is REMOVE:
            if owned is not MISSING and cur == owned:
                del_in(data, keys)
            ctx.disown(path, keys)
            continue
        mine = owned is not MISSING and cur == owned
        if cur == value:
            applied.add(keys)
            if mine or owned is MISSING and keys in force:
                ctx.own(path, keys, value)
        elif cur is MISSING or mine or keys in force:
            if set_in(data, keys, value):
                ctx.own(path, keys, value)
                applied.add(keys)
            else:
                ctx.say("skip", path, f"{'.'.join(map(str, keys[:-1]))} is not an object")
        else:
            ctx.disown(path, keys)
            ctx.say("keep", path, f"{'.'.join(map(str, keys))} is your value; kit-models value not applied")
    if json.dumps(data, sort_keys=True) == before:
        if path.exists():
            ctx.say("unchanged", path)
        return applied
    existed = path.exists()
    if existed:
        ctx.backup(path)
    if data:
        ctx.write_text(path, json.dumps(data, indent=2, ensure_ascii=False) + "\n", mode)
        ctx.say("update" if existed else "create", path)
    else:
        ctx.say("remove", path, "held only kit-models settings")
        if not ctx.dry_run and path.exists():
            path.unlink()
    return applied


def json_unsync(ctx: Ctx, path: Path, prefix: tuple = (), jsonc: bool = False) -> None:
    keys = ctx.owned_keys(path, prefix)
    if keys:
        json_settings(ctx, path, {k: REMOVE for k in keys}, jsonc=jsonc)


# --- text regions (TOML, YAML, shell) ---------------------------------------------------------

def region_re(begin: str, end: str):
    return re.compile(r"(?m)^" + re.escape(begin) + r".*?^" + re.escape(end) + r"[^\n]*\n?", re.S)


def replace_text(ctx: Ctx, path: Path, old: str, new: str, check_toml: bool = False,
                 mode: int = None) -> bool:
    if new == old:
        if path.exists():
            ctx.say("unchanged", path)
        return True
    if check_toml:
        try:
            import tomllib
        except ImportError:  # Python < 3.11: no check
            tomllib = None
        if tomllib is not None:
            try:
                tomllib.loads(new)
            except tomllib.TOMLDecodeError as e:
                ctx.say("skip", path, f"result would not be valid TOML ({e}); left untouched")
                return False
    existed = path.exists()
    if existed:
        ctx.backup(path)
    if new.strip():
        ctx.write_text(path, new, mode)
        ctx.say("update" if existed else "create", path)
    else:
        ctx.say("remove", path, "held only kit-models settings")
        if not ctx.dry_run and path.exists():
            path.unlink()
    return True


def set_region(ctx: Ctx, path: Path, begin: str, end: str, body: str, where: str = "end",
               check_toml: bool = False, mode: int = None) -> bool:
    """Put body into the region begin..end of path (created at `where`: start|end).
    An empty body removes the region. Text outside the region is kept."""
    old = read(path) if path.exists() else ""
    rx = region_re(begin, end)
    block = f"{begin}\n{body.rstrip()}\n{end}\n" if body.strip() else ""
    if rx.search(old):
        new = rx.sub(lambda _m: block, old, count=1)
    elif not block:
        return True
    elif where == "start":
        new = block + ("\n" + old if old.strip() else "")
    else:
        new = (old.rstrip("\n") + "\n\n" if old.strip() else "") + block
    new = re.sub(r"\n{3,}", "\n\n", new)
    if not block:  # removing: give back the file as it was before the region was added
        new = new.rstrip("\n") + "\n"
    if not new.strip():
        new = ""
    return replace_text(ctx, path, old, new, check_toml, mode)


def write_managed_file(ctx: Ctx, path: Path, body: str, marker: str, mode: int = None) -> None:
    """A file kit-models owns entirely (marker in the first lines)."""
    text = body if marker in body.split("\n", 3)[:3] or marker in body[:400] else marker + "\n" + body
    if path.exists():
        old = read(path)
        if old == text:
            ctx.say("unchanged", path)
            return
        if marker not in old:
            ctx.backup(path)
        ctx.write_text(path, text, mode)
        ctx.say("update", path)
        return
    ctx.write_text(path, text, mode)
    ctx.say("create", path)


def remove_managed_file(ctx: Ctx, path: Path, marker: str) -> None:
    if path.exists() and marker in read(path):
        ctx.say("remove", path)
        if not ctx.dry_run:
            path.unlink()


def toml_str(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, list):
        return "[" + ", ".join(toml_str(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{toml_key(k)} = {toml_str(x)}" for k, x in v.items()) + " }"
    return json.dumps(v)


def toml_key(k: str) -> str:
    return k if re.fullmatch(r"[A-Za-z0-9_-]+", k) else json.dumps(k)


def yaml_str(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    return json.dumps(v)
