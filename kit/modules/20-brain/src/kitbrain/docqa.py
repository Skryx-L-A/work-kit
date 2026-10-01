"""doc-qa: questions over approved company documents (module 18-doc-qa).

A separate brain scope (own notes repo and index, default `~/work/doc-qa`) holds Markdown copies
of documents from approved source folders. A label/exclusion gate decides per file what may enter.
Everything is refused until the config names an approved scope (enabled, approver, date, sources).
Answers are not generated here: `ask` returns cited passages; the agent or human writes the answer.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sys
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from . import ingest as ing
from . import notes, service

TEMPLATE = """\
# doc-qa: questions over approved company documents (kit module 18-doc-qa).
# Disabled until IT approves a scope. Fill in every field below, then set enabled = true.
# Values marked TODO(ask IT) must come from IT / data protection, not from guesses.

enabled = false
scope = ""              # short name of the approved scope, e.g. "engineering-handbook"
approved_by = ""        # TODO(ask IT): who approved it (name, role or ticket id)
approved_on = ""        # TODO(ask IT): date of the approval, YYYY-MM-DD
home = "~/work/doc-qa"  # separate notes repo and index; never your personal brain
sources = []            # folders (or files) with the approved documents

# Label gate. Labels come from document properties (e.g. sensitivity labels) and from
# "Classification: ..." style markers in the text. Exclusions always win.
allowed_labels = []     # TODO(ask IT): e.g. ["Public", "Internal"]
unlabeled = "skip"      # "skip" (strict default) or "allow" documents without any label
excluded_labels = ["confidential", "strictly confidential", "secret", "restricted", "customer",
                   "personal", "vertraulich", "streng vertraulich", "geheim", "personenbezogen"]
exclude = ["**/customer*/**", "**/kunde*/**", "**/hr/**", "**/personal/**", "*.bak"]
"""

MARKER = re.compile(
    r"(?:classification|klassifizierung|sensitivity|vertraulichkeit|schutzklasse|label)"
    r"\s*[:\-]\s*([A-Za-zÄÖÜäöüß][A-Za-zÄÖÜäöüß \-]{1,40})", re.I)
BARE = re.compile(r"^\W*(strictly confidential|streng vertraulich|confidential|vertraulich|"
                  r"internal only|internal|intern|public|öffentlich|restricted|secret|geheim)\W*$",
                  re.I)


class DocQaError(notes.NoteError):
    pass


@dataclass
class Config:
    path: Path
    enabled: bool = False
    scope: str = ""
    approved_by: str = ""
    approved_on: str = ""
    home: Path = Path("~/work/doc-qa")
    sources: list[Path] = field(default_factory=list)
    allowed_labels: list[str] = field(default_factory=list)
    unlabeled: str = "skip"
    excluded_labels: list[str] = field(default_factory=list)
    exclude: list[str] = field(default_factory=list)

    def problems(self) -> list[str]:
        """Why the scope is not usable; empty when it is."""
        out = []
        if not self.path.is_file():
            return [f"no config at {self.path}; run 'doc-qa init' and fill it in"]
        if not self.enabled:
            out.append("enabled = false")
        for key in ("scope", "approved_by", "approved_on"):
            if not str(getattr(self, key)).strip():
                out.append(f"{key} is empty")
        if not self.sources:
            out.append("sources is empty")
        if self.unlabeled not in ("skip", "allow"):
            out.append("unlabeled must be 'skip' or 'allow'")
        if not self.allowed_labels and self.unlabeled != "allow":
            out.append("allowed_labels is empty and unlabeled = 'skip': nothing could pass")
        return out


def config_path() -> Path:
    if os.environ.get("DOCQA_CONFIG"):
        return Path(os.environ["DOCQA_CONFIG"]).expanduser()
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "work-kit" / "doc-qa.toml"


def load_config() -> Config:
    path = config_path()
    cfg = Config(path=path, excluded_labels=[], exclude=[])
    if not path.is_file():
        return cfg
    try:
        data = tomllib.loads(path.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as exc:
        raise DocQaError(f"{path}: {exc}") from None
    cfg.enabled = data.get("enabled") is True
    for key in ("scope", "approved_by", "approved_on", "unlabeled"):
        if key in data:
            setattr(cfg, key, str(data[key]))
    cfg.home = Path(str(data.get("home") or "~/work/doc-qa")).expanduser()
    cfg.sources = [Path(str(s)).expanduser() for s in data.get("sources") or []]
    cfg.allowed_labels = [str(x) for x in data.get("allowed_labels") or []]
    cfg.excluded_labels = [str(x) for x in data.get("excluded_labels") or []]
    cfg.exclude = [str(x) for x in data.get("exclude") or []]
    return cfg


def require_enabled(cfg: Config) -> None:
    probs = cfg.problems()
    if probs:
        raise DocQaError("doc-qa is disabled until an approved scope is configured in "
                         f"{cfg.path}: " + "; ".join(probs))


def use_scope(cfg: Config) -> None:
    """Point the brain service at the doc-qa scope (separate repo and index)."""
    os.environ["BRAIN_HOME"] = str(cfg.home.resolve())


# -- gate ------------------------------------------------------------------------------------
def text_labels(markdown: str) -> list[str]:
    """Classification markers in the head and tail of a document."""
    found = []
    region = markdown[:3000] + "\n" + markdown[-1500:]
    for m in MARKER.finditer(region):
        found.append(m.group(1).strip())
    for line in region.splitlines():
        if len(line) <= 60:
            m = BARE.match(line.strip())
            if m:
                found.append(m.group(1))
    return found


def _norm(s: str) -> str:
    return " ".join(s.lower().replace("-", " ").replace("_", " ").split())


def gate(cfg: Config, path: Path, labels: list[str]) -> tuple[bool, str]:
    rel = path.as_posix()
    for pat in cfg.exclude:
        if fnmatch.fnmatch(rel.lower(), pat.lower()) or fnmatch.fnmatch(path.name.lower(), pat.lower()):
            return False, f"path matches exclude pattern '{pat}'"
    norm = [_norm(label) for label in labels]
    for bad in cfg.excluded_labels:
        b = _norm(bad)
        for label, n in zip(labels, norm):
            if re.search(rf"\b{re.escape(b)}\b", n):
                return False, f"label '{label}' is excluded"
    if not labels:
        return (cfg.unlabeled == "allow", "no label found"
                + ("" if cfg.unlabeled == "allow" else " (unlabeled = skip)"))
    allowed = {_norm(a) for a in cfg.allowed_labels}
    for label, n in zip(labels, norm):
        if n in allowed:
            return True, f"label '{label}' allowed"
    return False, f"label(s) {', '.join(labels)} not in allowed_labels"


# -- operations ------------------------------------------------------------------------------
def _files(cfg: Config) -> list[Path]:
    out = []
    for src in cfg.sources:
        if src.is_file():
            out.append(src.resolve())
        elif src.is_dir():
            out += sorted(p.resolve() for p in src.rglob("*")
                          if p.is_file() and p.suffix.lower() in ing.FORMATS
                          and not any(part.startswith(".") for part in p.relative_to(src).parts))
    return out


def _source_notes(home: Path) -> dict[str, Path]:
    out = {}
    if not home.is_dir():
        return out
    for p in notes.iter_notes(home):
        src = notes.load(p).meta.get("source")
        if isinstance(src, dict) and src.get("path"):
            out[str(src["path"])] = p
    return out


def _remove(home: Path, note: Path, why: str) -> None:
    note.unlink()
    service._after_write(note, f'doc-qa: remove {note.relative_to(home).as_posix()} ({why})')


def sync(cfg: Config, dry_run: bool = False) -> dict:
    require_enabled(cfg)
    use_scope(cfg)
    home = cfg.home.resolve()
    if not dry_run and not (home / ".git").exists():
        # Plain repo without the personal-notes template: only ingested documents live here.
        from . import gitops
        home.mkdir(parents=True, exist_ok=True)
        if gitops.available():
            gitops.ensure_repo(home)
            gitops.install_hooks(home)
            gitops.commit(home, [home / ".gitignore"], f"doc-qa: initialize scope {cfg.scope}")
    report = {"scope": cfg.scope, "home": str(home), "added": [], "updated": [], "unchanged": [],
              "skipped": [], "removed": [], "errors": []}
    existing = _source_notes(home)
    seen = set()
    for f in _files(cfg):
        seen.add(str(f))
        try:
            doc = ing.convert(f)
        except notes.NoteError as exc:
            report["errors"].append({"file": str(f), "reason": str(exc)})
            continue
        labels = ing._dedupe(doc.labels + text_labels(doc.markdown))
        ok, why = gate(cfg, f, labels)
        if not ok:
            report["skipped"].append({"file": str(f), "reason": why})
            if str(f) in existing and not dry_run:
                _remove(home, existing[str(f)], "no longer passes the gate")
                report["removed"].append({"file": str(f), "reason": why})
            continue
        if dry_run:
            report["added"].append({"file": str(f), "reason": why, "labels": labels})
            continue
        res = service.ingest(str(f), ntype="reference", tags=["doc-qa", notes.slugify(cfg.scope)],
                             update=True)
        key = {"created": "added", "updated": "updated", "unchanged": "unchanged"}[res["status"]]
        report[key].append({"file": str(f), "note": res["path"], "labels": labels})
    for src, note in existing.items():
        if src not in seen and not dry_run:
            _remove(home, note, "source file no longer in an approved folder")
            report["removed"].append({"file": src, "reason": "source gone"})
    return report


ANSWER_RULES = ("Answer only from the passages below. Cite each statement with its passage "
                "number, e.g. [2]. If the passages do not contain the answer, say that the approved "
                "documents do not answer it. Do not add knowledge from elsewhere.")


def ask(cfg: Config, question: str, k: int = 5) -> dict:
    require_enabled(cfg)
    use_scope(cfg)
    if not cfg.home.is_dir():
        raise DocQaError("the scope has no documents yet; run 'doc-qa sync'")
    idx = service.fresh_index()
    results, mode = idx.search(question, k=k * 2)
    home = cfg.home.resolve()
    passages = []
    for r in results:
        src = notes.load(home / r.path).meta.get("source")
        if not isinstance(src, dict):  # only ingested documents answer questions
            continue
        if len(passages) >= k:
            break
        n = len(passages) + 1
        passages.append({"n": n, "source": src.get("file") or r.path, "source_path": src.get("path"),
                         "location": r.heading, "note": r.path, "text": r.text.strip()})
    return {"scope": cfg.scope, "question": question, "mode": mode, "rules": ANSWER_RULES,
            "passages": passages}


def render_prompt(res: dict) -> str:
    parts = [res["rules"], "", f"Question: {res['question']}", ""]
    for p in res["passages"]:
        loc = f", {p['location']}" if p["location"] else ""
        parts += [f"[{p['n']}] {p['source']}{loc}", p["text"], ""]
    return "\n".join(parts)


def status(cfg: Config) -> dict:
    probs = cfg.problems()
    out = {"config": str(cfg.path), "enabled": not probs, "problems": probs, "scope": cfg.scope,
           "home": str(cfg.home), "sources": [str(s) for s in cfg.sources]}
    if not probs and cfg.home.is_dir():
        out["documents"] = len(_source_notes(cfg.home))
    return out


# -- CLI / MCP -------------------------------------------------------------------------------
MCP_TOOLS = [
    {"name": "ask_documents",
     "description": "Search the approved company documents (doc-qa scope) and return numbered "
                    "passages with their source. Answer only from these passages and cite them. "
                    "Fails when no approved scope is configured.",
     "inputSchema": {"type": "object",
                     "properties": {"question": {"type": "string"},
                                    "k": {"type": "integer", "minimum": 1, "maximum": 20,
                                          "default": 5}},
                     "required": ["question"]}},
    {"name": "documents_status",
     "description": "Show whether doc-qa is enabled, which scope is approved and how many "
                    "documents it holds.",
     "inputSchema": {"type": "object", "properties": {}}},
]


def _mcp_call(name: str, args: dict) -> str:
    cfg = load_config()
    if name == "ask_documents":
        return json.dumps(ask(cfg, args["question"], int(args.get("k", 5))), ensure_ascii=False,
                          indent=1)
    if name == "documents_status":
        return json.dumps(status(cfg), ensure_ascii=False, indent=1)
    raise KeyError(name)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="doc-qa", description="Questions over approved company documents.")
    sub = p.add_subparsers(dest="cmd", required=True, metavar="command")
    sub.add_parser("init", help="write the config template (never overwrites)")
    s = sub.add_parser("status", help="show config problems and scope")
    s.add_argument("--json", action="store_true")
    s = sub.add_parser("sync", help="ingest approved documents, drop ones that no longer pass")
    s.add_argument("--dry-run", action="store_true", help="only show what the gate decides")
    s.add_argument("--json", action="store_true")
    s = sub.add_parser("ask", help="cited passages for a question")
    s.add_argument("question")
    s.add_argument("-k", type=int, default=5)
    s.add_argument("--json", action="store_true")
    s.add_argument("--prompt", action="store_true", help="print a ready prompt for any model")
    sub.add_parser("mcp", help="MCP server on stdio (tools: ask_documents, documents_status)")
    a = p.parse_args(argv)
    try:
        cfg = load_config()
        if a.cmd == "init":
            if cfg.path.exists():
                print(f"config exists, left unchanged: {cfg.path}")
            else:
                cfg.path.parent.mkdir(parents=True, exist_ok=True)
                cfg.path.write_text(TEMPLATE, encoding="utf-8")
                print(f"wrote {cfg.path} (disabled until you fill in an approved scope)")
            return 0
        if a.cmd == "status":
            st = status(cfg)
            if a.json:
                print(json.dumps(st, indent=1))
            else:
                print(f"config   {st['config']}")
                print("state    " + ("enabled, scope " + st["scope"] if st["enabled"]
                                     else "disabled: " + "; ".join(st["problems"])))
                if "documents" in st:
                    print(f"docs     {st['documents']} in {st['home']}")
            return 0
        if a.cmd == "sync":
            rep = sync(cfg, dry_run=a.dry_run)
            if a.json:
                print(json.dumps(rep, ensure_ascii=False, indent=1))
            else:
                for key in ("added", "updated", "removed", "skipped", "errors"):
                    for item in rep[key]:
                        print(f"{key:9} {item['file']}"
                              + (f"  ({item['reason']})" if item.get("reason") else ""))
                print(" ".join(f"{k}={len(rep[k])}" for k in
                               ("added", "updated", "unchanged", "removed", "skipped", "errors"))
                      + (" (dry run)" if a.dry_run else ""))
            return 0
        if a.cmd == "ask":
            res = ask(cfg, a.question, a.k)
            if a.json:
                print(json.dumps(res, ensure_ascii=False, indent=1))
            elif a.prompt:
                print(render_prompt(res))
            else:
                if not res["passages"]:
                    print("no passages found in the approved documents")
                for ps in res["passages"]:
                    loc = f" > {ps['location']}" if ps["location"] else ""
                    print(f"[{ps['n']}] {ps['source']}{loc}\n    {ing_snip(ps['text'])}")
            return 0
        if a.cmd == "mcp":
            from .mcp import serve
            return serve(tools=MCP_TOOLS, call=_mcp_call, name="doc-qa")
    except service.UserError as exc:
        print(f"doc-qa: {exc}", file=sys.stderr)
        return 1
    return 0


def ing_snip(text: str, n: int = 300) -> str:
    text = " ".join(text.split())
    return text if len(text) <= n else text[: n - 1] + "…"


if __name__ == "__main__":
    sys.exit(main())
