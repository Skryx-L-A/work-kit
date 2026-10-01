"""Optional: save a report to the brain via its CLI (only if `brain` is installed)."""

from __future__ import annotations

import shutil
import subprocess


def save_to_brain(title: str, markdown: str, project: str | None = None) -> str:
    """Return a one-line status message; never raises for a missing or failing brain CLI."""
    exe = shutil.which("brain")
    if not exe:
        return "brain CLI not found; skipped --brain"
    cmd = [exe, "new", "reference", title, "--body", "-"]
    if project:
        cmd += ["--project", project]
    try:
        res = subprocess.run(cmd, input=markdown, capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f"brain call failed: {exc}"
    if res.returncode != 0:
        tail = (res.stderr.strip().splitlines() or ["unknown error"])[-1]
        return f"brain call failed (exit {res.returncode}): {tail}"
    return "saved to brain: " + (res.stdout.strip().splitlines() or [title])[-1]
