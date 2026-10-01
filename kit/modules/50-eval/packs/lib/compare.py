#!/usr/bin/env python3
"""Side-by-side comparison of evalkit result JSON files (and optional bench JSON files).

Usage: compare.py [--title T] [--md OUT.md] LABEL=result.json [LABEL=result.json ...]
       compare.py DIR            (every *.json in DIR; label = file name without .json)

A bench file (from engines/bench.py) next to a result with the same label adds throughput columns.
Standard library only.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def load(items: list[str]) -> list[tuple[str, dict[str, Any]]]:
    out: list[tuple[str, dict[str, Any]]] = []
    if len(items) == 1 and Path(items[0]).is_dir():
        items = [str(p) for p in sorted(Path(items[0]).glob("*.json"))]
    for item in items:
        label, _, path = item.rpartition("=") if "=" in item else ("", "", item)
        p = Path(path)
        data = json.loads(p.read_text(encoding="utf-8"))
        out.append((label or p.stem, data))
    return out


def fmt(v: Any, spec: str = "{}") -> str:
    return "-" if v is None else spec.format(v)


def eval_rows(results: list[tuple[str, dict[str, Any]]]) -> list[str]:
    rows = ["| candidate | provider | runs | pass rate | errors | latency mean | p95 | tokens out | out tok/s | cost USD |",
            "|---|---|---|---|---|---|---|---|---|---|"]
    for label, res in results:
        for pid, s in (res.get("summary") or {}).get("providers", {}).items():
            runs = [r for r in res.get("runs", []) if r.get("provider") == pid]
            tps = [r["tokens_out"] / r["latency_s"] for r in runs
                   if isinstance(r.get("tokens_out"), int) and r.get("latency_s")]
            rows.append(
                f"| {label} | {pid} | {s['runs']} | {s['pass_rate'] * 100:.0f}% | {s.get('errors', 0)} | "
                f"{fmt(s.get('latency_mean_s'), '{:.2f}s')} | {fmt(s.get('latency_p95_s'), '{:.2f}s')} | "
                f"{fmt(s.get('tokens_out'))} | {fmt(sum(tps) / len(tps) if tps else None, '{:.1f}')} | "
                f"{fmt(s.get('cost'), '{:.4f}')} |")
    return rows


def case_matrix(results: list[tuple[str, dict[str, Any]]]) -> list[str]:
    cols: list[str] = []
    table: dict[str, dict[str, str]] = {}
    for label, res in results:
        for pid, s in (res.get("summary") or {}).get("providers", {}).items():
            col = label if len(res["summary"]["providers"]) == 1 else f"{label}/{pid}"
            cols.append(col)
            for cid, c in (s.get("cases") or {}).items():
                table.setdefault(cid, {})[col] = f"{c['passed']}/{c['runs']}"
    if not table:
        return []
    rows = ["| case | " + " | ".join(cols) + " |", "|---|" + "---|" * len(cols)]
    for cid in sorted(table):
        rows.append(f"| {cid} | " + " | ".join(table[cid].get(c, "-") for c in cols) + " |")
    return rows


def bench_rows(benches: list[tuple[str, dict[str, Any]]]) -> list[str]:
    rows = ["| engine | requests | ok | TTFT mean | TTFT p95 | decode tok/s | prompt tok/s | total mean | concurrency |",
            "|---|---|---|---|---|---|---|---|---|"]
    for label, b in benches:
        s = b["summary"]
        rows.append(f"| {label} | {s['requests']} | {s['ok']} | {fmt(s.get('ttft_mean_s'), '{:.2f}s')} | "
                    f"{fmt(s.get('ttft_p95_s'), '{:.2f}s')} | {fmt(s.get('decode_tok_s_mean'), '{:.1f}')} | "
                    f"{fmt(s.get('prompt_tok_s_mean'), '{:.1f}')} | {fmt(s.get('total_mean_s'), '{:.2f}s')} | "
                    f"{b.get('concurrency', 1)} |")
    return rows


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("items", nargs="+")
    ap.add_argument("--title", default="Comparison")
    ap.add_argument("--md", help="also write the Markdown to this file")
    args = ap.parse_args(argv)
    loaded = load(args.items)
    evals = [(l, d) for l, d in loaded if "runs" in d and "summary" in d]
    benches = [(l.removesuffix(".bench"), d) for l, d in loaded if d.get("kind") == "bench"]
    if not evals and not benches:
        print("compare.py: no evalkit results or bench files given", file=sys.stderr)
        return 2
    out = [f"# {args.title}", ""]
    if evals:
        suites = sorted({r["suite"]["name"] for _, r in evals})
        reps = sorted({r.get("repetitions") for _, r in evals})
        out += [f"Suite: {', '.join(suites)}; repetitions: {', '.join(map(str, reps))}.", ""]
        out += eval_rows(evals) + [""]
        m = case_matrix(evals)
        if m:
            out += ["Passed runs per case:", ""] + m + [""]
    if benches:
        out += ["Throughput (engines/bench.py):", ""] + bench_rows(benches) + [""]
    text = "\n".join(out).rstrip() + "\n"
    print(text, end="")
    if args.md:
        Path(args.md).write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
