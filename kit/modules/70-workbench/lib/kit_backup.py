"""Where the workbench installer keeps backups: ~/.local/share/work-kit/backups/70-workbench/,
same relative path as below $HOME, plus .bak-<timestamp>. Nothing is left next to the file."""
import os
import shutil
import time
from pathlib import Path

MODULE = "70-workbench"


def backup_dest(path, stamp=None):
    path = Path(os.path.abspath(path))
    home = Path(os.environ.get("HOME") or Path.home())
    base = Path(os.environ.get("KIT_DATA_DIR") or home / ".local/share/work-kit") / "backups" / MODULE
    try:
        rel = path.relative_to(home)
    except ValueError:
        rel = Path("_root") / path.relative_to(path.anchor)
    dest = base / rel.parent / f"{rel.name}.bak-{stamp or time.strftime('%Y%m%d%H%M%S')}"
    dest.parent.mkdir(parents=True, exist_ok=True)
    return dest


def copy_aside(path, stamp=None):
    """Copy path to its backup place; returns the backup path."""
    dest = backup_dest(path, stamp)
    shutil.copy2(path, dest)
    return dest


def move_aside(path, stamp=None):
    """Move path to its backup place; returns the backup path."""
    dest = backup_dest(path, stamp)
    shutil.move(str(path), str(dest))
    return dest
