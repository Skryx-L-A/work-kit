"""Worklog (`brain log`) and weekly report (`brain week`).

Entries live in `worklog/<ISO year>-W<week>.md`, one Markdown list line each:
    - 2026-09-25 14:05 | 2.5 h | billing | Characterization tests for the tariff engine
Hours and project are optional ("-"). Files stay readable and editable by hand.
"""

from __future__ import annotations

import datetime as dt
import os
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from . import notes

ENTRY = re.compile(
    r"^- (\d{4}-\d{2}-\d{2})(?: (\d{2}:\d{2}))? \| ([^|]*) \| ([^|]*) \| (.*)$")
DEFAULT_LIMIT = 20.0  # working-student weekly limit during lecture periods


@dataclass
class Entry:
    date: dt.date
    time: str
    hours: float | None
    project: str
    text: str


def parse_hours(raw: str | float | None) -> float | None:
    if raw is None:
        return None
    if isinstance(raw, (int, float)):
        h = float(raw)
    else:
        s = raw.strip().lower().replace(",", ".")
        if s in ("", "-", "–"):
            return None
        m = re.fullmatch(r"(\d+(?:\.\d+)?)\s*(h|m|min)?", s)
        if not m:
            m2 = re.fullmatch(r"(\d+):(\d{2})", s)
            if not m2:
                raise notes.NoteError(f"cannot read hours '{raw}' (examples: 2, 1.5, 1,5, 90m, 1:30)")
            h = int(m2.group(1)) + int(m2.group(2)) / 60
        else:
            h = float(m.group(1)) / (60 if m.group(2) in ("m", "min") else 1)
    if not 0 < h <= 24:
        raise notes.NoteError(f"hours must be between 0 and 24, got {h:g}")
    return round(h, 2)


def parse_week(raw: str | None, today: dt.date | None = None) -> tuple[int, int]:
    """'2026-W39', 'W39', '39' or None (current week) -> (iso_year, week)."""
    today = today or dt.date.today()
    if not raw:
        y, w, _ = today.isocalendar()
        return y, w
    m = re.fullmatch(r"(?:(\d{4})-?)?[Ww]?(\d{1,2})", raw.strip())
    if not m:
        raise notes.NoteError(f"cannot read week '{raw}' (examples: 2026-W39, W39, 39)")
    year = int(m.group(1)) if m.group(1) else today.isocalendar()[0]
    week = int(m.group(2))
    try:
        dt.date.fromisocalendar(year, week, 1)
    except ValueError:
        raise notes.NoteError(f"week {week} does not exist in {year}") from None
    return year, week


def week_file(home: Path, year: int, week: int) -> Path:
    return home / "worklog" / f"{year}-W{week:02d}.md"


def format_entry(e: Entry) -> str:
    hours = f"{e.hours:g} h" if e.hours else "-"
    text = " ".join(e.text.split())
    when = e.date.isoformat() + (f" {e.time}" if e.time else "")
    return f"- {when} | {hours} | {e.project or '-'} | {text}"


def read_entries(path: Path) -> list[Entry]:
    if not path.is_file():
        return []
    out = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = ENTRY.match(line.strip())
        if not m:
            continue
        try:
            hours = parse_hours(m.group(3).replace("h", ""))
        except notes.NoteError:
            hours = None
        proj = m.group(4).strip()
        out.append(Entry(dt.date.fromisoformat(m.group(1)), m.group(2) or "", hours,
                         "" if proj in ("-", "–") else proj, m.group(5).strip()))
    return out


def add_entry(home: Path, text: str, hours=None, project: str | None = None,
              day: dt.date | None = None, now: dt.datetime | None = None) -> tuple[Path, Entry, bool]:
    if not text.strip():
        raise notes.NoteError("log text must not be empty")
    now = now or dt.datetime.now()
    day = day or now.date()
    entry = Entry(day, now.strftime("%H:%M") if day == now.date() else "", parse_hours(hours),
                  notes.slugify(project) if project else "", text)
    y, w, _ = day.isocalendar()
    path = week_file(home, y, w)
    created = not path.exists()
    if created:
        path.parent.mkdir(parents=True, exist_ok=True)
        meta = {"title": f"Worklog {y}-W{w:02d}", "type": "note", "tags": ["worklog"],
                "created": notes.today(), "updated": notes.today()}
        path.write_text(notes.render(meta, "Format: date time | hours | project | what\n"),
                        encoding="utf-8")
    notes.append(path, format_entry(entry))
    return path, entry, created


# -- weekly report ---------------------------------------------------------------------------
def _limit() -> float:
    from .config import _load_file
    raw = os.environ.get("BRAIN_WEEK_LIMIT") or _load_file().get("week_limit_hours")
    try:
        return float(raw) if raw else DEFAULT_LIMIT
    except ValueError:
        return DEFAULT_LIMIT


def _work_dir() -> Path:
    from .config import _load_file
    return Path(os.environ.get("BRAIN_WORK_DIR") or _load_file().get("work_dir")
                or Path.home() / "work").expanduser()


def find_repos(root: Path, max_depth: int = 3) -> list[Path]:
    repos: list[Path] = []

    def walk(d: Path, depth: int):
        if (d / ".git").exists():
            repos.append(d)
            return
        if depth >= max_depth:
            return
        try:
            children = sorted(p for p in d.iterdir() if p.is_dir() and not p.is_symlink()
                              and not p.name.startswith(".") and p.name != "node_modules")
        except OSError:
            return
        for c in children:
            walk(c, depth + 1)

    if root.is_dir():
        walk(root, 0)
    return repos


def git_activity(root: Path, start: dt.date, end: dt.date) -> list[dict]:
    """Own commits per repo in [start, end) — author = the repo's configured user.email."""
    out = []
    for repo in find_repos(root):
        email = subprocess.run(["git", "-C", str(repo), "config", "user.email"],
                               capture_output=True, text=True).stdout.strip()
        args = ["git", "-C", str(repo), "log", "--all", "--no-merges",
                f"--since={start.isoformat()} 00:00", f"--until={end.isoformat()} 00:00",
                "--pretty=format:%ad|%s", "--date=format:%Y-%m-%d %H:%M"]
        if email:
            args.append(f"--author={email}")
        proc = subprocess.run(args, capture_output=True, text=True)
        lines = [ln for ln in proc.stdout.splitlines() if "|" in ln]
        if not lines:
            continue
        commits = [{"time": ln.split("|", 1)[0], "subject": ln.split("|", 1)[1]} for ln in lines]
        commits.sort(key=lambda c: c["time"])
        out.append({"repo": str(repo.relative_to(root)) if repo != root else repo.name,
                    "commits": len(commits), "days": sorted({c["time"][:10] for c in commits}),
                    "first": commits[0]["time"], "last": commits[-1]["time"],
                    "subjects": [c["subject"] for c in commits[-10:]]})
    return out


def week_report(home: Path, week: str | None = None, today: dt.date | None = None) -> dict:
    year, wk = parse_week(week, today)
    start = dt.date.fromisocalendar(year, wk, 1)
    end = start + dt.timedelta(days=7)
    entries = read_entries(week_file(home, year, wk))
    entries = [e for e in entries if start <= e.date < end]
    total = round(sum(e.hours or 0 for e in entries), 2)
    per_day: dict[str, float] = {}
    per_project: dict[str, float] = {}
    for e in entries:
        per_day[e.date.isoformat()] = round(per_day.get(e.date.isoformat(), 0) + (e.hours or 0), 2)
        key = e.project or "(none)"
        per_project[key] = round(per_project.get(key, 0) + (e.hours or 0), 2)
    limit = _limit()
    status = "over" if total > limit else "near" if total >= 0.9 * limit else "ok"
    activity = git_activity(_work_dir(), start, end)
    git_days = sorted({d for a in activity for d in a["days"]})
    return {
        "week": f"{year}-W{wk:02d}", "start": start.isoformat(),
        "end": (end - dt.timedelta(days=1)).isoformat(),
        "hours": total, "limit": limit, "remaining": round(limit - total, 2), "status": status,
        "per_day": per_day, "per_project": per_project,
        "entries": [{"date": e.date.isoformat(), "time": e.time, "hours": e.hours,
                     "project": e.project, "text": e.text} for e in entries],
        "git": activity,
        "git_days_without_hours": [d for d in git_days if d not in per_day],
    }


def render_report(r: dict) -> str:
    flag = {"ok": "within limit", "near": "close to the limit", "over": "OVER THE LIMIT"}[r["status"]]
    lines = [f"# Week {r['week']} ({r['start']} to {r['end']})", "",
             f"Hours: {r['hours']:g} of {r['limit']:g} h ({flag}; {r['remaining']:g} h left)", ""]
    if r["per_day"]:
        lines += ["## Hours per day", "", "| Day | Hours |", "|---|---|"]
        for d, h in sorted(r["per_day"].items()):
            wd = dt.date.fromisoformat(d).strftime("%a")
            lines.append(f"| {d} {wd} | {h:g} |")
        lines.append("")
    if r["per_project"]:
        lines += ["## Hours per project", "", "| Project | Hours |", "|---|---|"]
        lines += [f"| {p} | {h:g} |" for p, h in sorted(r["per_project"].items(), key=lambda x: -x[1])]
        lines.append("")
    if r["entries"]:
        lines += ["## Worklog", ""]
        lines += [f"- {e['date']} {e['time']} {e['hours'] or '-'} h {e['project'] or ''}: {e['text']}"
                  .replace("  ", " ") for e in r["entries"]]
        lines.append("")
    if r["git"]:
        lines += ["## Git activity", ""]
        for a in r["git"]:
            lines.append(f"- {a['repo']}: {a['commits']} commits on {', '.join(a['days'])}")
            lines += [f"  - {s}" for s in a["subjects"]]
        lines.append("")
    if r["git_days_without_hours"]:
        lines += ["Days with commits but no logged hours: " + ", ".join(r["git_days_without_hours"]), ""]
    return "\n".join(lines).rstrip() + "\n"
