"""Module selection: whiptail/dialog when present and a terminal is attached, plain prompts otherwise.

KIT_INSTALL_UI = auto (default) | plain | whiptail | dialog  (tests force one).
"""
import os
import shutil
import subprocess
import sys
import textwrap

CHECK_HINT = "Space: select, Enter: confirm"
MENU_HINT = "Up/Down: move, Enter: confirm"
MAX_WIDTH = 110


def _backend():
    want = os.environ.get("KIT_INSTALL_UI", "auto")
    if want == "plain":
        return None
    if want in ("whiptail", "dialog"):
        return shutil.which(want)
    if sys.stdin.isatty() and sys.stdout.isatty():
        return shutil.which("whiptail") or shutil.which("dialog")
    return None


def _describe(m, status_entry):
    text = m.description or m.name
    flags = []
    if m.depends:
        flags.append("needs " + ",".join(m.depends))
    if m.needs_sudo:
        flags.append("needs sudo")
    if not m.default_on:
        flags.append("ask IT first")
    if status_entry.get("status") == "failed":
        flags.append("failed before: %s" % status_entry.get("reason", "?"))
    if status_entry.get("status") == "stale":
        flags.append("installed, check failed (removed by hand?)")
    if status_entry.get("stale"):
        flags.append("installed, check failed (removed by hand?)")
    if status_entry.get("status") == "skipped":
        flags.append("skipped before: %s" % status_entry.get("reason", "?"))
    if status_entry.get("status") == "update":
        # first, so a narrow terminal that cuts the description still shows it
        text = "UPDATE: " + text
    return text + (" (%s)" % "; ".join(flags) if flags else "")


def _default_on(m, status_entry):
    if status_entry.get("status") == "update":
        return True
    if status_entry.get("status") == "installed":
        return False  # --all: an installed module is installed again only when ticked by hand
    return m.default_on and not m.needs_sudo


def term_size():
    """(columns, lines) of the terminal: COLUMNS/LINES, the tty ioctl, `stty size`, else 80x24."""
    cols = lines = 0
    try:
        cols, lines = int(os.environ.get("COLUMNS", "")), int(os.environ.get("LINES", ""))
    except ValueError:
        cols = lines = 0
    if cols <= 0 or lines <= 0:
        for fd in (1, 0, 2):
            try:
                size = os.get_terminal_size(fd)
            except (OSError, ValueError):
                continue
            if size.columns > 0 and size.lines > 0:
                return size.columns, size.lines
        try:
            with open("/dev/tty") as tty:
                out = subprocess.run(["stty", "size"], stdin=tty, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                     universal_newlines=True).stdout.split()
            if len(out) == 2 and int(out[0]) > 0 and int(out[1]) > 0:
                return int(out[1]), int(out[0])
        except (OSError, ValueError):
            pass
        return 80, 24
    return cols, lines


def tag_for(m):
    """Menu tag: number before the name, '71-delegate' -> '71 delegate'."""
    return m.id.replace("-", " ", 1)


def shorten(text, width):
    """Cut text at a word boundary so it fits width columns; '...' marks the cut."""
    text = " ".join(text.split())
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    if width <= 3:
        return text[:width]
    cut = text[: width - 3]
    if text[width - 3] != " " and " " in cut:
        cut = cut[: cut.rindex(" ")]
    return cut.rstrip(" ,;:-(") + "..."


def box_geometry(cols, lines, text, n_items):
    """(height, width, list_height) for whiptail/dialog: never larger than the terminal."""
    width = min(cols, max(24, min(cols - 4, MAX_WIDTH)))
    hmax = max(1, lines - 1)
    text_lines = sum(max(1, len(textwrap.wrap(ln, max(1, width - 4)))) for ln in text.split("\n"))
    list_h = max(1, min(n_items, hmax - text_lines - 7))
    return min(hmax, text_lines + list_h + 7), width, list_h


def wrap_list(head, names):
    """head + names joined by ", ", wrapped at the terminal width between names (a module name is
    never split across lines, as "30-agent-set|up" was in a 80-column terminal)."""
    width = max(40, term_size()[0] - 1)
    return textwrap.fill(head + ", ".join(names), width=width, subsequent_indent="  ",
                         break_long_words=False, break_on_hyphens=False)


def desc_room(width, tag_len, scrolls):
    """Columns left for a description in a whiptail checklist of this width. A list longer than its
    box gets a scroll bar that covers the last text columns (seen in a 80x24 terminal: "(needs 00-pytho▯)")."""
    return width - tag_len - 12 - (2 if scrolls else 0)


def _describe_fit(m, status_entry, avail):
    """_describe() cut to avail columns; the flags (needs sudo, failed before) stay if there is room."""
    full = _describe(m, status_entry)
    if len(full) <= avail:
        return full
    base = m.description or m.name
    prefix = full[:full.index(base)] if base in full else ""   # "UPDATE: " stays in front
    flags = full[len(prefix) + len(base):]
    room = avail - len(prefix) - len(flags)
    if room >= 12:
        return prefix + shorten(base, room) + flags
    return prefix + shorten(base + flags, max(1, avail - len(prefix)))


def choose(singles, groups, entries, notes):
    """singles: modules without group. groups: {group: [modules]}. entries: id -> state entry.
    Returns list of selected module ids, or None if the user quit."""
    backend = _backend()
    if backend:
        return _choose_box(backend, singles, groups, entries, notes)
    return _choose_plain(singles, groups, entries, notes)


def _choose_plain(singles, groups, entries, notes):
    out = sys.stdout
    for n in notes:
        out.write(n + "\n")
    selected = []

    def ask(prompt):
        out.write(prompt)
        out.flush()
        line = sys.stdin.readline()
        return None if line == "" else line.strip().lower()

    for m in singles:
        default_yes = _default_on(m, entries.get(m.id, {}))
        out.write("\n%s\n  %s\n" % (m.id, _describe(m, entries.get(m.id, {}))))
        while True:
            ans = ask("  Install? [%s] (y/n/q) " % ("Y/n" if default_yes else "y/N"))
            if ans is None or ans == "q":
                return None if ans == "q" else selected
            if ans == "":
                ans = "y" if default_yes else "n"
            if ans in ("y", "yes"):
                selected.append(m.id)
                break
            if ans in ("n", "no"):
                break
            out.write("  answer y, n or q\n")
    for group, members in sorted(groups.items()):
        out.write("\n%s: pick at most one\n" % group.capitalize())
        for i, m in enumerate(members, 1):
            out.write("  %d) %s  %s%s\n" % (i, m.id, _describe(m, entries.get(m.id, {})), "  (default)" if i == 1 else ""))
        out.write("  0) none\n")
        while True:
            ans = ask("  Choice [1]: ")
            if ans is None:
                return selected
            if ans == "":
                ans = "1"
            if ans == "0":
                break
            if ans == "q":
                return None
            if ans.isdigit() and 1 <= int(ans) <= len(members):
                selected.append(members[int(ans) - 1].id)
                break
            out.write("  enter a number from 0 to %d\n" % len(members))
    return selected


# whiptail takes its colours from the terminal palette: in the kit's Ghostty theme the default
# newt colours came out pink on pink and the selected rows were hard to read (VM, 28.09.). This
# palette uses only light grey, black and cyan, readable in light and dark themes. A NEWT_COLORS
# the user set wins.
NEWT_COLORS = ("root=lightgray,black;border=lightgray,black;window=lightgray,black;shadow=black,black;"
               "title=brightcyan,black;button=black,lightgray;actbutton=black,cyan;"
               "compactbutton=lightgray,black;checkbox=lightgray,black;actcheckbox=black,cyan;"
               "entry=lightgray,black;disentry=gray,black;label=lightgray,black;listbox=lightgray,black;"
               "actlistbox=black,cyan;sellistbox=lightgray,black;actsellistbox=black,cyan;"
               "textbox=lightgray,black;acttextbox=black,cyan;emptyscale=,black;fullscale=,cyan;"
               "helpline=lightgray,black;roottext=lightgray,black")


def box_env(backend):
    env = dict(os.environ)
    if os.path.basename(backend) == "whiptail" and not env.get("NEWT_COLORS"):
        env["NEWT_COLORS"] = NEWT_COLORS
    return env


def _box(backend, args):
    """Run whiptail/dialog; result text goes to stderr. Returns (code, lines)."""
    proc = subprocess.run([backend, "--separate-output"] + args, stderr=subprocess.PIPE, universal_newlines=True,
                          env=box_env(backend))
    return proc.returncode, [ln.strip().strip("'\"") for ln in proc.stderr.splitlines() if ln.strip()]


def _choose_box(backend, singles, groups, entries, notes):
    cols, lines = term_size()
    selected = []
    intro = "\n".join(notes)
    if singles:
        tags = {tag_for(m): m.id for m in singles}
        text = CHECK_HINT + "\n" + (intro + "\n" if intro else "") + "\nSelect modules to install:"
        height, width, list_h = box_geometry(cols, lines, text, len(singles))
        avail = desc_room(width, max(len(t) for t in tags), len(singles) > list_h)
        items = []
        for m in singles:
            e = entries.get(m.id, {})
            items += [tag_for(m), _describe_fit(m, e, avail), "ON" if _default_on(m, e) else "OFF"]
        code, got = _box(backend, ["--title", "work-kit", "--checklist", text,
                                   str(height), str(width), str(list_h)] + items)
        if code != 0:
            return None
        selected += [tags[t] for t in got if t in tags]
    for group, members in sorted(groups.items()):
        tags = {tag_for(m): m.id for m in members}
        text = MENU_HINT + "\n%s: pick at most one." % group.capitalize()
        height, width, list_h = box_geometry(cols, lines, text, len(members) + 1)
        avail = width - max(len(t) for t in list(tags) + ["none"]) - 8
        items = ["none", shorten("install none of these", avail)]
        for m in members:
            items += [tag_for(m), _describe_fit(m, entries.get(m.id, {}), avail)]
        # the first member (70 for orchestration) is highlighted, so Enter installs it; 'none' stays selectable
        code, got = _box(backend, ["--title", "work-kit: " + group, "--default-item", tag_for(members[0]),
                                   "--menu", text, str(height), str(width), str(list_h)] + items)
        if code != 0:
            return None
        if got and got[0] in tags:
            selected.append(tags[got[0]])
    return selected


def ask_permissions(modes):
    """One plain question (works with or without whiptail). No answer or end of input: bypass."""
    out = sys.stdout
    out.write("\nAI harness approvals (Claude Code, Codex, Gemini, ...).\n"
              "Change later with: kit-sync --permissions\n"
              "  1) bypass  agents run commands without asking (default)\n"
              "  2) ask     agents ask before commands and edits\n")
    while True:
        out.write("  Choice [1]: ")
        out.flush()
        line = sys.stdin.readline()
        ans = line.strip().lower() if line else ""
        if ans in ("", "1") or ans == modes[0]:
            return modes[0]
        if ans in ("2", modes[1]):
            return modes[1]
        out.write("  answer 1 or 2\n")
