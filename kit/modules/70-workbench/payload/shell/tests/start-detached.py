#!/usr/bin/env python3
"""Start a test process outside the invoking harness ancestry.

Usage: start-detached.py PIDFILE LOGFILE STATUSFILE COMMAND [ARG ...]

STATUSFILE ``-`` execs COMMAND directly.  Otherwise the detached supervisor
waits for COMMAND and atomically records its exit status.  The double fork is
intentional: GUI provenance tests must exercise the same launchd-parented
process shape as a user-started application, not inherit the test harness.
"""

from __future__ import annotations

import os
import sys


def write_text(path: str, value: str) -> None:
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="ascii") as handle:
        handle.write(value)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def main() -> int:
    if len(sys.argv) < 5:
        print(__doc__.splitlines()[2], file=sys.stderr)
        return 2
    pid_file, log_file, status_file = sys.argv[1:4]
    command = sys.argv[4:]

    first = os.fork()
    if first:
        _, status = os.waitpid(first, 0)
        return os.waitstatus_to_exitcode(status)

    os.setsid()
    second = os.fork()
    if second:
        write_text(pid_file, str(second) + "\n")
        os._exit(0)

    read_fd = os.open(os.devnull, os.O_RDONLY)
    log_fd = os.open(log_file, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    os.dup2(read_fd, 0)
    os.dup2(log_fd, 1)
    os.dup2(log_fd, 2)
    if read_fd > 2:
        os.close(read_fd)
    if log_fd > 2:
        os.close(log_fd)

    if status_file == "-":
        os.execvp(command[0], command)

    child = os.fork()
    if child == 0:
        os.execvp(command[0], command)
    _, status = os.waitpid(child, 0)
    code = os.waitstatus_to_exitcode(status)
    write_text(status_file, str(code) + "\n")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
