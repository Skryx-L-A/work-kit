"""Run shell commands with a hard timeout that also kills child processes."""

from __future__ import annotations

import os
import shlex
import signal
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping


@dataclass
class ShellResult:
    stdout: str
    stderr: str
    returncode: int | None  # None on timeout
    timed_out: bool = False


def render(template: str, values: Mapping[str, str], quote: bool = False) -> str:
    """Replace {name} for known names only; other braces (awk, jq, JSON) stay untouched."""
    out = template
    for name, value in values.items():
        out = out.replace("{" + name + "}", shlex.quote(value) if quote else value)
    return out


def run_shell(
    command: str,
    stdin: str | None = None,
    timeout: float = 60.0,
    cwd: Path | str | None = None,
    env: Mapping[str, str] | None = None,
) -> ShellResult:
    proc = subprocess.Popen(
        command,
        shell=True,
        stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        cwd=str(cwd) if cwd else None,
        env={**os.environ, **env} if env else None,
        start_new_session=True,
    )
    try:
        out, err = proc.communicate(stdin, timeout=timeout)
        return ShellResult(out, err, proc.returncode)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        out, err = proc.communicate()
        return ShellResult(out or "", err or "", None, timed_out=True)


def python_exe() -> str:
    return sys.executable or "python3"
