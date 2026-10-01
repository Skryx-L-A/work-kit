"""Parse short duration strings like "1h30m", "45s" or "2h"."""
import re

_PART = re.compile(r"(\d+)([hms])")
_FACTOR = {"h": 3600, "m": 60, "s": 1}


def parse_duration(text):
    """Return the duration in seconds. Raise ValueError for empty or malformed input."""
    text = text.strip().lower()
    if not text:
        raise ValueError("empty duration")
    pos = 0
    total = 0
    for m in _PART.finditer(text):
        if m.start() != pos:
            raise ValueError(f"bad duration: {text!r}")
        total += int(m.group(1)) * _FACTOR[m.group(2)]
        pos = m.end()
    if pos != len(text):
        raise ValueError(f"bad duration: {text!r}")
    return total
