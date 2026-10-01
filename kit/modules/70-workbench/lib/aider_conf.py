#!/usr/bin/env python3
"""Switch off aider's co-author and author attribution in ~/.aider.conf.yml, or undo it.

    aider_conf.py add|remove <aider.conf.yml>

add: appends a marked block with the three attribution keys that are not set yet (a key the
user already set is left alone). remove: deletes the marked block. Backup before a change, in
~/.local/share/work-kit/backups/70-workbench/ (lib/kit_backup.py).
"""
import re
import sys
from pathlib import Path

from kit_backup import copy_aside

BEGIN = "# >>> work-kit workbench: no co-author attribution >>>"
END = "# <<< work-kit workbench <<<"
KEYS = ("attribute-co-authored-by", "attribute-author", "attribute-committer")


def write(path, text):
    if path.exists():
        copy_aside(path)
    path.write_text(text, encoding="utf-8")


def main(action, conf):
    path = Path(conf)
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    block = re.compile(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", re.S)
    if action == "remove":
        new = block.sub("", text)
        if new != text:
            write(path, new)
            print("aider: attribution block removed")
        return
    rest = block.sub("", text)
    missing = [k for k in KEYS if not re.search(rf"^\s*{k}\s*:", rest, re.M)]
    new_block = (BEGIN + "\n" + "".join(f"{k}: false\n" for k in missing) + END + "\n") if missing else ""
    sep = "" if not rest or rest.endswith("\n") else "\n"
    new = rest + sep + new_block
    if new != text:
        write(path, new)
    print(f"aider: attribution off ({len(missing)} keys set by the kit, {len(KEYS) - len(missing)} kept from the user)")


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("add", "remove"):
        sys.exit(__doc__)
    main(*sys.argv[1:])
