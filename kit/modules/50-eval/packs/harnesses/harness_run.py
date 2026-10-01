#!/usr/bin/env python3
"""Run one CLI harness on one task in a fresh temporary git repo and check the result.

Usage (as an evalkit shell provider; the task id arrives on stdin):
    harness_run.py --harness ID [--conf FILE] [--keep] [--timeout S]

Steps: copy tasks/<task>/repo to a new temp dir, `git init` + baseline commit (hooks disabled),
run the harness command from the config with the repo as working directory and stdin closed,
then run tasks/<task>/check.py in the repo. Prints one JSON line:
    {"task", "harness", "check": "pass"|"fail", "reason", "harness_exit", "timed_out",
     "duration_s", "files_changed", "workdir"}
The temp dir is removed unless --keep (or HARNESS_KEEP=1). Config lines: `id|command` with the
placeholders {prompt_file} {repo} {python} {pack}. With HARNESS_LLM_USAGE=1 and `llm-usage` on
PATH, the harness call is recorded as an invoke_agent span (14-llm-usage).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

PACK = Path(__file__).resolve().parent


def load_conf(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "|" not in line:
            continue
        hid, cmd = line.split("|", 1)
        out[hid.strip()] = cmd.strip()
    return out


def git(repo: Path, *args: str) -> str:
    env = {**os.environ, "GIT_CONFIG_NOSYSTEM": "1"}
    r = subprocess.run(["git", "-c", "core.hooksPath=/dev/null", "-c", "user.name=harness-eval",
                        "-c", "user.email=harness-eval@example.invalid", "-c", "commit.gpgsign=false", *args],
                       cwd=repo, capture_output=True, text=True, env=env)
    if r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--harness", required=True)
    ap.add_argument("--conf")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--timeout", type=float, default=float(os.environ.get("HARNESS_TIMEOUT", "600")))
    args = ap.parse_args(argv)

    task = sys.stdin.read().strip()
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", task) or not (PACK / "tasks" / task / "repo").is_dir():
        print(json.dumps({"task": task, "harness": args.harness, "check": "fail", "reason": "unknown task"}))
        return 0
    conf_path = Path(args.conf or os.environ.get("HARNESS_CONF") or
                     (PACK / "harnesses.conf" if (PACK / "harnesses.conf").is_file() else PACK / "harnesses.conf.example"))
    conf = load_conf(conf_path)
    if args.harness not in conf:
        print(f"harness {args.harness!r} not in {conf_path}", file=sys.stderr)
        return 2
    task_dir = PACK / "tasks" / task
    work = Path(tempfile.mkdtemp(prefix=f"harness-eval-{task}-"))
    repo = work / "repo"
    shutil.copytree(task_dir / "repo", repo)
    prompt_file = work / "prompt.md"
    shutil.copy(task_dir / "prompt.md", prompt_file)
    git(repo, "init", "-q")
    # Byte-code and harness caches are noise in the changed-files list.
    (repo / ".git/info").mkdir(parents=True, exist_ok=True)
    (repo / ".git/info/exclude").write_text("__pycache__/\n*.pyc\n.aider*\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "baseline")

    cmd = conf[args.harness]
    for key, val in {"prompt_file": str(prompt_file), "repo": str(repo), "python": sys.executable,
                     "pack": str(PACK)}.items():
        cmd = cmd.replace("{" + key + "}", shlex.quote(val))
    if os.environ.get("HARNESS_LLM_USAGE") == "1" and shutil.which("llm-usage"):
        cmd = (f"llm-usage wrap --provider {shlex.quote(args.harness)} --tag harness-eval:{task} "
               f"-- sh -c {shlex.quote(cmd)}")
    env = {**os.environ, "EVAL_TASK": task, "EVAL_TASK_DIR": str(task_dir), "EVAL_REPO": str(repo)}
    log = work / "harness.log"
    start = time.time()
    timed_out = False
    with open(log, "w") as fh:
        proc = subprocess.Popen(cmd, shell=True, cwd=repo, stdin=subprocess.DEVNULL, stdout=fh,
                                stderr=subprocess.STDOUT, env=env, start_new_session=True)
        try:
            rc = proc.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            os.killpg(proc.pid, 9)
            rc = proc.wait()
    duration = round(time.time() - start, 2)

    chk = subprocess.run([sys.executable, str(task_dir / "check.py")], cwd=repo, capture_output=True,
                         text=True, env=env, timeout=300)
    lines = (chk.stdout.strip() or chk.stderr.strip()).splitlines()
    reason = lines[-1] if lines else ""
    try:
        git(repo, "add", "-A")
        changed = [l for l in git(repo, "diff", "--cached", "--name-only", "HEAD").splitlines() if l]
    except RuntimeError:
        changed = []  # the harness may have rewritten history; the check result still counts
    result = {
        "task": task, "harness": args.harness, "check": "pass" if chk.returncode == 0 else "fail",
        "reason": reason + (" (harness timed out)" if timed_out else ""),
        "harness_exit": rc, "timed_out": timed_out, "duration_s": duration, "files_changed": changed,
    }
    if args.keep or os.environ.get("HARNESS_KEEP") == "1":
        result["workdir"] = str(work)
    else:
        shutil.rmtree(work, ignore_errors=True)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
