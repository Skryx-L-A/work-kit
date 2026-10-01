#!/usr/bin/env python3
"""Throughput and latency benchmark for one OpenAI-compatible endpoint (streaming chat).

Usage: bench.py --base-url URL --model NAME [--label L] [--requests N] [--concurrency C]
                [--max-tokens M] [--out FILE.json]

Per request: time to first token (TTFT), decode speed (output tokens after the first one per
second), prompt speed (prompt tokens / TTFT) and total time. One warm-up request is not counted.
Prompts: a short German and a short English task plus one long (~1,500 token) German context,
so prompt processing and generation both show up. Each prompt starts with a unique line so
engines cannot answer from a prompt cache. Standard library only; no API key is read
unless --api-key-env names a variable.
"""

from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

LONG_CONTEXT = " ".join(
    f"Abschnitt {i}: Das Modul Auftragsverwaltung liest die Datei KUNDEN-{i:03d} ein, prüft die "
    f"Kundennummer gegen den Stammdatenbestand und schreibt fehlerhafte Sätze in das Protokoll FEHL-{i:03d}."
    for i in range(1, 41)
)
PROMPTS = [
    ("de-short", "Erkläre in drei Sätzen, was ein Regressionstest ist."),
    ("en-short", "Explain in three sentences what a characterization test is."),
    ("de-long", LONG_CONTEXT + "\n\nFasse in zwei Sätzen zusammen, was das Modul tut."),
]


def one_request(base_url: str, model: str, prompt: str, max_tokens: int, timeout: float,
                api_key: str | None) -> dict:
    body = {"model": model, "messages": [{"role": "user", "content": prompt}], "stream": True,
            "max_tokens": max_tokens, "temperature": 0, "stream_options": {"include_usage": True}}
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    req = urllib.request.Request(base_url.rstrip("/") + "/chat/completions", json.dumps(body).encode(), headers)
    t0 = time.perf_counter()
    first = None
    chunks = 0
    usage = {}
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            for raw in r:
                line = raw.strip()
                if not line.startswith(b"data:"):
                    continue
                data = line[5:].strip()
                if data == b"[DONE]":
                    break
                try:
                    obj = json.loads(data)
                except json.JSONDecodeError:
                    continue
                if obj.get("usage"):
                    usage = obj["usage"]
                for c in obj.get("choices") or []:
                    delta = c.get("delta") or {}
                    if delta.get("content") or delta.get("reasoning_content"):
                        chunks += 1
                        if first is None:
                            first = time.perf_counter()
    except (urllib.error.URLError, OSError, TimeoutError) as exc:
        return {"ok": False, "error": str(exc)[:200], "total_s": round(time.perf_counter() - t0, 3)}
    t1 = time.perf_counter()
    out_tokens = usage.get("completion_tokens") or chunks
    in_tokens = usage.get("prompt_tokens")
    ttft = (first - t0) if first else None
    decode = (out_tokens - 1) / (t1 - first) if first and out_tokens > 1 and t1 > first else None
    return {
        "ok": first is not None, "error": None if first else "no tokens received",
        "ttft_s": round(ttft, 3) if ttft is not None else None,
        "total_s": round(t1 - t0, 3), "prompt_tokens": in_tokens, "output_tokens": out_tokens,
        "tokens_reported": bool(usage),
        "decode_tok_s": round(decode, 2) if decode else None,
        "prompt_tok_s": round(in_tokens / ttft, 1) if in_tokens and ttft else None,
    }


def mean(xs):
    xs = [x for x in xs if x is not None]
    return round(statistics.fmean(xs), 3) if xs else None


def p95(xs):
    xs = sorted(x for x in xs if x is not None)
    return xs[min(len(xs) - 1, int(round(0.95 * (len(xs) - 1))))] if xs else None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--label", help="engine name in the report (default: model)")
    ap.add_argument("--requests", type=int, default=6, help="measured requests (prompts rotate)")
    ap.add_argument("--concurrency", type=int, default=1)
    ap.add_argument("--max-tokens", type=int, default=128)
    ap.add_argument("--timeout", type=float, default=600)
    ap.add_argument("--api-key-env")
    ap.add_argument("--no-warmup", action="store_true")
    ap.add_argument("--out")
    args = ap.parse_args(argv)
    key = os.environ.get(args.api_key_env) if args.api_key_env else None

    if not args.no_warmup:
        one_request(args.base_url, args.model, PROMPTS[0][1], 16, args.timeout, key)
    jobs = [PROMPTS[i % len(PROMPTS)] for i in range(args.requests)]
    results: list[dict] = []
    lock = threading.Lock()
    started = time.perf_counter()

    counter = iter(range(1, 1_000_000))

    def run(job):
        name, prompt = job
        # A unique first line defeats prefix caching, so every request pays full prompt processing.
        with lock:
            n = next(counter)
        prompt = f"Request {n} of run {started:.0f}.\n{prompt}"
        r = one_request(args.base_url, args.model, prompt, args.max_tokens, args.timeout, key)
        r["prompt"] = name
        with lock:
            results.append(r)
            print(f"  {name:9} ttft={r.get('ttft_s')}s decode={r.get('decode_tok_s')} tok/s "
                  f"total={r['total_s']}s{'' if r['ok'] else ' ERROR ' + str(r['error'])}", file=sys.stderr)

    with ThreadPoolExecutor(max_workers=max(1, args.concurrency)) as ex:
        list(ex.map(run, jobs))
    wall = time.perf_counter() - started
    ok = [r for r in results if r["ok"]]
    total_out = sum(r.get("output_tokens") or 0 for r in ok)
    summary = {
        "requests": len(results), "ok": len(ok),
        "ttft_mean_s": mean([r["ttft_s"] for r in ok]), "ttft_p95_s": p95([r["ttft_s"] for r in ok]),
        "decode_tok_s_mean": mean([r["decode_tok_s"] for r in ok]),
        "prompt_tok_s_mean": mean([r["prompt_tok_s"] for r in ok]),
        "total_mean_s": mean([r["total_s"] for r in ok]),
        "aggregate_out_tok_s": round(total_out / wall, 2) if wall > 0 else None,
        "tokens_reported": all(r.get("tokens_reported") for r in ok) if ok else False,
    }
    result = {"kind": "bench", "engine": args.label or args.model, "base_url": args.base_url,
              "model": args.model, "concurrency": args.concurrency, "max_tokens": args.max_tokens,
              "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "requests": results, "summary": summary}
    text = json.dumps(result, indent=2)
    if args.out:
        Path(args.out).write_text(text + "\n", encoding="utf-8")
    else:
        print(text)
    print(f"{result['engine']}: {summary['ok']}/{summary['requests']} ok, TTFT {summary['ttft_mean_s']}s, "
          f"decode {summary['decode_tok_s_mean']} tok/s, prompt {summary['prompt_tok_s_mean']} tok/s", file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
