"""evalkit command line: run / report / list."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

from . import __version__
from .brain import save_to_brain
from .report import summarize, to_markdown
from .runner import RunError, run_suite, select_cases, select_providers, stderr_progress
from .suite import SuiteError, load_suite


def home_dir() -> Path:
    env = os.environ.get("EVALKIT_HOME")
    return Path(env) if env else Path.home() / ".local" / "share" / "work-kit" / "evalkit"


def results_dir() -> Path:
    return home_dir() / "results"


def _slug(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-") or "suite"


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _emit(result: dict[str, Any], fmt: str) -> None:
    if fmt == "json":
        print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        print(to_markdown(result))


def _find_result(ref: str | None) -> Path:
    if ref and Path(ref).is_file():
        return Path(ref)
    files = sorted(results_dir().glob("*.json"), key=lambda p: p.stat().st_mtime) if results_dir().is_dir() else []
    if ref:
        slug = _slug(ref)
        files = [f for f in files if f.name.startswith(slug + "-")]
    if not files:
        raise RunError(f"no saved result found{' for ' + repr(ref) if ref else ''} in {results_dir()}")
    return files[-1]


def cmd_run(args: argparse.Namespace) -> int:
    suite = load_suite(args.suite)
    providers = select_providers(suite, args.provider)
    cases = select_cases(suite, args.case)
    reps = args.repetitions or suite.repetitions
    if args.dry_run:
        print(f"suite: {suite.name} ({suite.path})")
        print(f"providers: {', '.join(p.id for p in providers)}")
        print(f"cases: {', '.join(c.id for c in cases)}  repetitions: {reps}")
        print(f"runs: {len(providers) * len(cases) * reps}  judges: {', '.join(j.id for j in suite.judges) or '-'}")
        return 0
    result = run_suite(suite, providers, cases, reps, jobs=args.jobs, progress=None if args.quiet else stderr_progress)
    result["summary"] = summarize(result)

    out = Path(args.out) if args.out else None
    if out is None and not args.no_save:
        stamp = result["finished"].replace(":", "").replace("-", "").replace("+0000", "").split("+")[0]
        out = results_dir() / f"{_slug(suite.name)}-{stamp}.json"
    if out:
        _write(out, json.dumps(result, indent=2, ensure_ascii=False) + "\n")
        print(f"saved: {out}", file=sys.stderr)
    if args.md:
        _write(Path(args.md), to_markdown(result))
    _emit(result, args.format)
    if args.brain:
        title = f"Eval {suite.name} {result['finished'][:10]}"
        print(save_to_brain(title, to_markdown(result), args.brain_project), file=sys.stderr)
    if args.fail_under is not None and result["summary"]["pass_rate"] < args.fail_under:
        print(
            f"pass rate {result['summary']['pass_rate']:.2f} is below --fail-under {args.fail_under}",
            file=sys.stderr,
        )
        return 1
    return 0


def cmd_report(args: argparse.Namespace) -> int:
    path = _find_result(args.result)
    try:
        result = json.loads(path.read_text(encoding="utf-8"))
        result["summary"] = summarize(result)
    except (OSError, ValueError, KeyError) as exc:
        raise RunError(f"{path}: not a valid evalkit result ({exc})") from exc
    _emit(result, args.format)
    return 0


def cmd_list(args: argparse.Namespace) -> int:
    if args.results:
        folder = Path(args.path) if args.path else results_dir()
        files = sorted(folder.glob("*.json")) if folder.is_dir() else []
        if not files:
            print(f"no results in {folder}")
        for f in files:
            try:
                r = json.loads(f.read_text(encoding="utf-8"))
                s = summarize(r)
                print(f"{f.name}\t{r['suite']['name']}\t{s['passed']}/{s['runs']} passed\t{r['finished']}")
            except (OSError, ValueError, KeyError):
                print(f"{f.name}\t(unreadable)")
        return 0
    root = Path(args.path or ".")
    files = [root] if root.is_file() else sorted([*root.glob("*.yaml"), *root.glob("*.yml")])
    found = False
    for f in files:
        try:
            s = load_suite(f)
        except SuiteError as exc:
            print(f"{f}\t(invalid: {exc})")
            found = True
            continue
        print(f"{f}\t{s.name}\t{len(s.cases)} cases\tproviders: {', '.join(p.id for p in s.providers)}")
        found = True
    if not found:
        print(f"no suite files in {root}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="evalkit", description="Run eval suites against models and CLI agents.")
    p.add_argument("--version", action="version", version=f"evalkit {__version__}")
    sub = p.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("run", help="run a suite")
    r.add_argument("suite", help="path to a suite YAML file")
    r.add_argument("-p", "--provider", action="append", help="provider id (repeatable); default: all with default: true")
    r.add_argument("-c", "--case", action="append", help="case id (repeatable)")
    r.add_argument("-n", "--repetitions", type=int, help="override repetitions per case")
    r.add_argument("-j", "--jobs", type=int, default=1, help="parallel runs (default 1)")
    r.add_argument("--format", choices=["md", "json"], default="md", help="stdout format (default md)")
    r.add_argument("--out", help="write the JSON result to this file (default: results dir)")
    r.add_argument("--md", help="also write the Markdown report to this file")
    r.add_argument("--no-save", action="store_true", help="do not write a result file")
    r.add_argument("--brain", action="store_true", help="save the report via 'brain new reference' if brain exists")
    r.add_argument("--brain-project", help="project slug passed to brain")
    r.add_argument("--fail-under", type=float, metavar="RATE", help="exit 1 if overall pass rate < RATE (0-1)")
    r.add_argument("--dry-run", action="store_true", help="validate the suite and show the plan; call nothing")
    r.add_argument("-q", "--quiet", action="store_true", help="no per-run progress on stderr")
    r.set_defaults(func=cmd_run)

    rep = sub.add_parser("report", help="render a saved result")
    rep.add_argument("result", nargs="?", help="result file, or suite name (latest); default: latest overall")
    rep.add_argument("--format", choices=["md", "json"], default="md")
    rep.set_defaults(func=cmd_report)

    ls = sub.add_parser("list", help="list suites in a folder, or saved results")
    ls.add_argument("path", nargs="?", help="folder or suite file (default: current folder)")
    ls.add_argument("--results", action="store_true", help="list saved results instead")
    ls.set_defaults(func=cmd_list)
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if getattr(args, "jobs", 1) < 1:
            raise RunError("--jobs must be >= 1")
        return args.func(args)
    except (SuiteError, RunError) as exc:
        print(f"evalkit: {exc}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("evalkit: interrupted", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
