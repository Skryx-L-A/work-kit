#!/usr/bin/env python3
"""Start script of the kit for Quassel's control center (run by work-kit-quassel-type).

Runs the unchanged app (`quassel.center.main()`) with two adjustments that belong to this kit:

1. Without keyboard access (the user is not in group `input` or /dev/uinput is not writable, i.e.
   root-steps.sh was not run) the hold-to-talk key cannot work. The welcome dialog and the hint of
   the control center then describe what does work: the clipboard shortcut of
   `work-kit-quassel-dictate` (shortcut.sh binds Ctrl+Alt+D on GNOME). The on/off switch starts only
   the speech server instead of the hotkey daemon, which would exit at once.
2. The window opens at most as large as the screen (the app sizes it by its content, which is
   taller than a laptop screen with larger fonts) and may be narrow enough to sit in a half tile.
The app's own files are not changed. See docs/quassel.md.
"""
import glob
import os
import subprocess
import sys

BIN = os.path.expanduser("~/.local/bin")
SHORTCUT_ITEM = ("org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:"
                 "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/work-kit-quassel/")
SERVER_UNIT = "work-kit-quassel-server"
MIN_WIDTH = 560        # two half tiles fit on a 1280 px screen; the app itself asks for 680
MIN_HEIGHT = 420
SCREEN_MARGIN = (40, 120)   # what the window frame and the top bar take from the screen


def keyboard_ready():
    """True when the hotkey daemon can work: it reads /dev/input and types through /dev/uinput."""
    if not os.access("/dev/uinput", os.W_OK):
        return False
    return any(os.access(p, os.R_OK) for p in glob.glob("/dev/input/event*"))


def shortcut_label():
    """The GNOME shortcut set by shortcut.sh as text like 'Ctrl + Alt + D', or None."""
    try:
        out = subprocess.run(["gsettings", "get", SHORTCUT_ITEM, "binding"], capture_output=True,
                             text=True, timeout=3, check=False).stdout.strip().strip("'\"")
    except (OSError, subprocess.SubprocessError):
        return None
    if not out:
        return None
    names = {"control": "Ctrl", "primary": "Ctrl", "alt": "Alt", "super": "Super", "shift": "Shift"}
    parts, rest = [], out
    while rest.startswith("<") and ">" in rest:
        mod, rest = rest[1:].split(">", 1)
        parts.append(names.get(mod.lower(), mod))
    if not rest:
        return None
    return " + ".join(parts + [rest.upper() if len(rest) == 1 else rest])


def clipboard_texts(shortcut):
    """(English, German) replacements for the strings that promise the hold-to-talk key."""
    cmd = os.path.join(BIN, "work-kit-quassel-dictate") + " toggle"
    if shortcut:
        how = (f"Press {shortcut}, speak, press it again.",
               f"{shortcut} drücken, sprechen, noch einmal drücken.")
        short = (f"Press {shortcut} = start recording, press again = stop",
                 f"{shortcut} drücken = Aufnahme starten, nochmal drücken = beenden")
    else:
        how = (f"Set up a keyboard shortcut once (Settings, Keyboard, Custom Shortcuts) for the command {cmd}, "
               "then press it, speak, press it again.",
               f"Richte einmal ein Tastenkürzel ein (Einstellungen, Tastatur, Eigene Kürzel) für den Befehl {cmd}, "
               "drücke es dann, sprich und drücke es noch einmal.")
        short = (f"Shortcut not set yet: bind {cmd} to a key",
                 f"Noch kein Kürzel: lege {cmd} auf eine Taste")
    body = (
        "Quassel turns your voice into text — fully offline.\n\n" + how[0] +
        " The text is copied to the clipboard; paste it with Ctrl + V.\n\n"
        "Hold-to-talk ({chord}) needs one-time administrator setup, which this computer does not have, "
        "so it is off here. There's nothing else you must configure; everything below is optional.",
        "Quassel macht aus deiner Stimme Text — komplett offline.\n\n" + how[1] +
        " Der Text liegt danach in der Zwischenablage; füge ihn mit Strg + V ein.\n\n"
        "Halten zum Sprechen ({chord}) braucht einmalig Administrator-Rechte, die dieser Rechner nicht "
        "hat, und ist hier daher aus. Sonst musst du nichts einstellen; alles Weitere ist optional.")
    hint = (
        short[0] + "; the text goes to the clipboard (paste with Ctrl + V)\n"
        "Hold-to-talk ({chord}) is not set up on this computer (needs one-time administrator setup)",
        short[1] + "; der Text landet in der Zwischenablage (Strg + V)\n"
        "Halten zum Sprechen ({chord}) ist auf diesem Rechner nicht eingerichtet (braucht einmalig Administrator-Rechte)")
    return {
        "ob_body": body,
        "hint": hint,
        "on": ("Speech engine is running", "Spracherkennung läuft"),
        "off": ("Speech engine is idle", "Spracherkennung ruht"),
    }


def apply_clipboard_mode(center, i18n):
    i18n.STRINGS.update(clipboard_texts(shortcut_label()))
    # The switch would start the hotkey daemon, which exits without /dev/input access.
    center.UNITS_START = [SERVER_UNIT]
    center.UNITS_STOP = [SERVER_UNIT]
    center.daemon_active = lambda: center.sysctl("is-active", "--quiet", SERVER_UNIT).returncode == 0


def fit_to_screen(win):
    """Cap the first size at the screen and allow a smaller window than the app's 680x520."""
    from PySide6.QtGui import QGuiApplication
    screen = win.screen() or QGuiApplication.primaryScreen()
    if screen is None:
        return
    avail = screen.availableGeometry()
    max_w = max(avail.width() - SCREEN_MARGIN[0], 320)
    max_h = max(avail.height() - SCREEN_MARGIN[1], 240)
    win.setMinimumSize(min(MIN_WIDTH, max_w), min(MIN_HEIGHT, max_h))
    hint = win.sizeHint()
    win.resize(min(max(hint.width(), win.minimumWidth()), max_w),
               min(max(hint.height(), win.minimumHeight()), max_h))


def main():
    from quassel import center, i18n
    if not keyboard_ready():
        apply_clipboard_mode(center, i18n)
    plain_show = center.Center.show

    def show(self):
        fit_to_screen(self)
        plain_show(self)
    center.Center.show = show
    center.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
