#!/usr/bin/env python3
"""A stand-in for an agent CLI, for verify.sh: behaves like a chat TUI in a tmux pane.

Shows the prompt '❯ ', reads keys in raw mode, treats bracketed paste as text (not as submit),
and on Enter: prints the submitted text as history, and if it carries a `[Protocol` line, writes
a result file to the path named there ("... to the file <path> (WHAT/...") and answers DONE.
Every submitted text is appended to $FAKE_LOG; at start, KIT_AGENT_ROLE ("-" when unset) is
appended to $FAKE_LOG.roles.
"""
import codecs
import os
import re
import sys
import termios
import tty

LOG = os.environ.get("FAKE_LOG", "")
RESULT = re.compile(r"to the file (\S+) \(WHAT")


def out(text):
    sys.stdout.write(text)
    sys.stdout.flush()


def prompt(buf):
    out("\r\x1b[2K❯ " + buf.replace("\n", " ")[-150:])


def submit(buf):
    out("\r\x1b[2K")
    for line in buf.splitlines():
        out("  " + line + "\r\n")
    if LOG:
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(buf + "\n---\n")
    m = RESULT.search(buf)
    if m:
        path = m.group(1)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("# Result\n\nWHAT: fake agent answered.\n\nHOW-verified: none.\n\nOPEN: none.\n")
        out("DONE\r\n")


def main():
    if LOG:
        with open(LOG + ".roles", "a", encoding="utf-8") as fh:
            fh.write(os.environ.get("KIT_AGENT_ROLE", "-") + "\n")
    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setraw(fd)
    out("\x1b[?2004h")  # bracketed paste on
    buf, pasting, esc = "", False, ""
    decoder = codecs.getincrementaldecoder("utf-8")("replace")
    try:
        prompt(buf)
        while True:
            raw = os.read(fd, 1)
            if not raw:
                break
            ch = decoder.decode(raw)
            if not ch:
                continue  # inside a multi-byte character
            if esc or ch == "\x1b":
                esc += ch
                if esc in ("\x1b[200~",):
                    pasting, esc = True, ""
                elif esc in ("\x1b[201~",):
                    pasting, esc = False, ""
                elif len(esc) >= 6 or (len(esc) > 1 and not "\x1b[200~".startswith(esc)
                                       and not "\x1b[201~".startswith(esc)):
                    esc = ""  # other escape sequence: ignore
                continue
            if pasting:
                buf += "\n" if ch == "\r" else ch
            elif ch == "\r":
                if buf:
                    submit(buf)
                buf = ""
            elif ch == "\x15":  # C-u
                buf = ""
            elif ch in ("\x7f", "\x08"):
                buf = buf[:-1]
            elif ch == "\x03":
                break
            else:
                buf += ch
            prompt(buf)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)


if __name__ == "__main__":
    main()
