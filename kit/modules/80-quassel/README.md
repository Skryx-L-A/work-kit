# 80-quassel

Quassel: local dictation (whisper.cpp on CPU, German + English). Offline, no sudo. Needs `00-python`.
Needs `kit/offline/quassel` (build host: `bash fetch.sh`). Details: `~/work/kit/docs/quassel.md`.

```sh
cd ~/work/kit/modules/80-quassel && bash install.sh    # default model small-q5_1
bash uninstall.sh                                      # keeps settings and history
bash uninstall.sh --purge                              # also deletes settings and history
```

Clipboard mode (no root):

```sh
bash shortcut.sh                       # GNOME: Ctrl+Alt+D runs work-kit-quassel-dictate toggle
work-kit-quassel-dictate toggle         # press: record; press again: text goes to the clipboard
```

`install.sh` runs `shortcut.sh --ensure` itself on GNOME (inside the desktop session; it keeps a key you
set before). Without root steps the "Quassel" window says so: its welcome and hint name this shortcut
instead of the hold-to-talk key.

Other desktops: add a custom shortcut for `~/.local/bin/work-kit-quassel-dictate toggle`.

Optional keyboard mode (hold Ctrl+Meta, text is typed), needs sudo once:

```sh
sudo bash root-steps.sh                # explains every change, asks before applying
```

Log out and back in, then:

```sh
work-kit-quassel-ctl start              # or open "Quassel" and switch it on
```

Settings: open "Quassel" (`work-kit-quassel-type`). Status: `bash root-steps.sh --check`.
Undo the keyboard mode: `sudo bash root-steps.sh --undo`.

Installed names, migration and build: `~/work/kit/docs/quassel.md`.
