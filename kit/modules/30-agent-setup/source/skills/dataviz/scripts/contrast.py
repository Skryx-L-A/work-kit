#!/usr/bin/env python3
"""WCAG 2.x contrast ratio checker (standard library only).

Usage:
  contrast.py FG BG                 ratio of two colours, e.g. "#5b6270" "#ffffff"
  contrast.py --palette BG C1 C2... ratio of each colour against BG, min 3:1 for marks
Exit code 1 if any pair fails the threshold (4.5 for text pairs, 3.0 for --palette).
"""
import sys


def luminance(hex_colour: str) -> float:
    h = hex_colour.lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) != 6:
        raise ValueError(f"not a hex colour: {hex_colour}")
    channels = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255
        channels.append(c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4)
    r, g, b = channels
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def ratio(a: str, b: str) -> float:
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def main(argv: list[str]) -> int:
    if len(argv) >= 3 and argv[0] == "--palette":
        bg, colours, threshold = argv[1], argv[2:], 3.0
        pairs = [(c, bg) for c in colours]
    elif len(argv) == 2:
        pairs, threshold = [(argv[0], argv[1])], 4.5
    else:
        print(__doc__.strip())
        return 2
    failed = False
    for fg, bg in pairs:
        r = ratio(fg, bg)
        ok = r >= threshold
        failed |= not ok
        print(f"{fg} on {bg}: {r:.2f}:1 {'PASS' if ok else 'FAIL'} (min {threshold}:1)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
