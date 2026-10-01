"""Run a suite: every provider x case x repetition, graded."""

from __future__ import annotations

import datetime as dt
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Callable

from . import __version__, graders
from .providers import Provider, ProviderError
from .shell import render
from .suite import Case, Suite

MAX_OUTPUT_CHARS = 8000


class RunError(ValueError):
    pass


def select_providers(suite: Suite, wanted: list[str] | None) -> list[Provider]:
    if wanted:
        by_id = {p.id: p for p in suite.providers}
        unknown = [w for w in wanted if w not in by_id]
        if unknown:
            raise RunError(f"unknown provider(s): {', '.join(unknown)} (suite has: {', '.join(by_id)})")
        chosen = [by_id[w] for w in wanted]
    else:
        chosen = [p for p in suite.providers if p.default]
        if not chosen:
            raise RunError("no provider is enabled by default; pick one with --provider")
    for p in chosen:
        try:
            p.prepare()
        except ProviderError as exc:
            raise RunError(str(exc)) from exc
    return chosen


def select_cases(suite: Suite, wanted: list[str] | None) -> list[Case]:
    if not wanted:
        return suite.cases
    by_id = {c.id: c for c in suite.cases}
    unknown = [w for w in wanted if w not in by_id]
    if unknown:
        raise RunError(f"unknown case(s): {', '.join(unknown)}")
    return [by_id[w] for w in wanted]


def _now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def _run_one(
    suite: Suite, provider: Provider, case: Case, rep: int, judges: dict[str, Provider]
) -> dict[str, Any]:
    prompt = render(suite.prompt, {"input": case.input}) if suite.prompt else case.input
    resp = provider.complete(prompt, suite.timeout)
    record: dict[str, Any] = {
        "provider": provider.id,
        "case": case.id,
        "rep": rep,
        "passed": False,
        "error": resp.error,
        "latency_s": round(resp.latency, 3),
        "tokens_in": resp.tokens_in,
        "tokens_out": resp.tokens_out,
        "cost": resp.cost,
        "output": resp.text[:MAX_OUTPUT_CHARS],
        "graders": [],
    }
    if resp.error:
        return record
    ctx = graders.Context(resp.text, case.input, suite.base_dir, suite.timeout, judges)
    results: list[graders.Grade] = []
    ordered = sorted(case.graders, key=lambda g: g["type"] == "llm-judge")  # cheap graders first
    failed_early = False
    for spec in ordered:
        if spec["type"] == "llm-judge" and failed_early:
            results.append(graders.Grade("llm-judge", False, "skipped: an earlier grader failed"))
            continue
        g = graders.grade(spec, ctx)
        results.append(g)
        failed_early = failed_early or not g.passed
    record["graders"] = [{"type": g.type, "passed": g.passed, "reason": g.reason} for g in results]
    record["passed"] = all(g.passed for g in results)
    judged = [g.judge for g in results if g.judge is not None]
    if judged:
        record["judge"] = {
            "latency_s": round(sum(j.latency for j in judged), 3),
            "tokens_in": _sum([j.tokens_in for j in judged]),
            "tokens_out": _sum([j.tokens_out for j in judged]),
            "cost": _sum([j.cost for j in judged]),
        }
    return record


def _sum(values: list[Any]) -> Any:
    known = [v for v in values if v is not None]
    return sum(known) if known else None


def run_suite(
    suite: Suite,
    providers: list[Provider],
    cases: list[Case],
    repetitions: int,
    jobs: int = 1,
    progress: Callable[[str], None] | None = None,
) -> dict[str, Any]:
    judges = {j.id: j for j in suite.judges}
    for j in judges.values():
        j.prepare()
    tasks = [(p, c, r) for p in providers for c in cases for r in range(1, repetitions + 1)]
    lock = threading.Lock()
    done = 0
    started = _now()

    def work(task: tuple[Provider, Case, int]) -> dict[str, Any]:
        nonlocal done
        rec = _run_one(suite, *task, judges)
        with lock:
            done += 1
            if progress:
                mark = "PASS" if rec["passed"] else "FAIL"
                progress(f"[{done}/{len(tasks)}] {rec['provider']} / {rec['case']} #{rec['rep']}: {mark} ({rec['latency_s']:.2f}s)")
        return rec

    if jobs <= 1:
        runs = [work(t) for t in tasks]
    else:
        with ThreadPoolExecutor(max_workers=jobs) as pool:
            runs = list(pool.map(work, tasks))
    return {
        "evalkit": __version__,
        "suite": {
            "name": suite.name,
            "description": suite.description,
            "path": str(suite.path),
            "sha256": suite.sha256,
        },
        "started": started,
        "finished": _now(),
        "repetitions": repetitions,
        "providers": [p.id for p in providers],
        "cases": [c.id for c in cases],
        "runs": runs,
    }


def stderr_progress(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)
