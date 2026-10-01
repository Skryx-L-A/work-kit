"""Summaries and Markdown rendering of a result document."""

from __future__ import annotations

import math
from typing import Any


def _sum(values: list[Any]) -> Any:
    known = [v for v in values if v is not None]
    return sum(known) if known else None


def _p95(values: list[float]) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[max(0, math.ceil(0.95 * len(ordered)) - 1)]


def summarize(result: dict[str, Any]) -> dict[str, Any]:
    runs = result["runs"]
    providers: dict[str, Any] = {}
    for pid in result["providers"]:
        mine = [r for r in runs if r["provider"] == pid]
        lat = [r["latency_s"] for r in mine]
        judge = [r["judge"] for r in mine if r.get("judge")]
        passed = sum(1 for r in mine if r["passed"])
        cases: dict[str, Any] = {}
        for cid in result["cases"]:
            cr = [r for r in mine if r["case"] == cid]
            cases[cid] = {"runs": len(cr), "passed": sum(1 for r in cr if r["passed"])}
        providers[pid] = {
            "runs": len(mine),
            "passed": passed,
            "pass_rate": passed / len(mine) if mine else 0.0,
            "errors": sum(1 for r in mine if r["error"]),
            "latency_mean_s": round(sum(lat) / len(lat), 3) if lat else None,
            "latency_p95_s": _p95(lat),
            "tokens_in": _sum([r["tokens_in"] for r in mine]),
            "tokens_out": _sum([r["tokens_out"] for r in mine]),
            "cost": _sum([r["cost"] for r in mine]),
            "judge_cost": _sum([j["cost"] for j in judge]),
            "cases": cases,
        }
    total = len(runs)
    passed = sum(1 for r in runs if r["passed"])
    return {"runs": total, "passed": passed, "pass_rate": passed / total if total else 0.0, "providers": providers}


def _pct(x: float) -> str:
    return f"{x * 100:.0f}%"


def _opt(value: Any, fmt: str = "{}") -> str:
    return "-" if value is None else fmt.format(value)


def _cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ")


def to_markdown(result: dict[str, Any]) -> str:
    summ = result.get("summary") or summarize(result)
    suite = result["suite"]
    lines = [f"# Eval: {suite['name']}", ""]
    if suite.get("description"):
        lines += [suite["description"], ""]
    lines += [
        f"- Started: {result['started']}  Finished: {result['finished']}",
        f"- Repetitions per case: {result['repetitions']}  |  Overall pass rate: "
        f"{_pct(summ['pass_rate'])} ({summ['passed']}/{summ['runs']})",
        "",
        "## Providers",
        "",
        "| Provider | Pass rate | Passed | Errors | Latency mean | Latency p95 | Tokens in | Tokens out | Cost (USD) | Judge cost (USD) |",
        "|---|---|---|---|---|---|---|---|---|---|",
    ]
    for pid, p in summ["providers"].items():
        lines.append(
            "| {id} | {rate} | {ok}/{n} | {err} | {mean} | {p95} | {tin} | {tout} | {cost} | {jc} |".format(
                id=_cell(pid),
                rate=_pct(p["pass_rate"]),
                ok=p["passed"],
                n=p["runs"],
                err=p["errors"],
                mean=_opt(p["latency_mean_s"], "{:.2f}s"),
                p95=_opt(p["latency_p95_s"], "{:.2f}s"),
                tin=_opt(p["tokens_in"]),
                tout=_opt(p["tokens_out"]),
                cost=_opt(p["cost"], "{:.4f}"),
                jc=_opt(p["judge_cost"], "{:.4f}"),
            )
        )
    pids = list(summ["providers"])
    lines += ["", "## Cases (passed / runs)", "", "| Case | " + " | ".join(_cell(p) for p in pids) + " |"]
    lines.append("|---|" + "---|" * len(pids))
    for cid in result["cases"]:
        cells = [f"{summ['providers'][p]['cases'][cid]['passed']}/{summ['providers'][p]['cases'][cid]['runs']}" for p in pids]
        lines.append(f"| {_cell(cid)} | " + " | ".join(cells) + " |")

    seen: set[tuple[str, str]] = set()
    failures = []
    for r in result["runs"]:
        key = (r["provider"], r["case"])
        if not r["passed"] and key not in seen:  # first failing repetition per provider+case
            seen.add(key)
            reasons = [r["error"]] if r["error"] else [
                f"{g['type']}: {g['reason'] or 'failed'}" for g in r["graders"] if not g["passed"]
            ]
            failures.append(f"- `{r['provider']}` / `{r['case']}` (rep {r['rep']}): " + "; ".join(reasons))
    if failures:
        lines += ["", "## Failures", ""] + failures
    lines.append("")
    return "\n".join(lines)
