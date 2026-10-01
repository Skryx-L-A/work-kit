# 80-quassel: design notes

Quassel is a local dictation app (repo `github.com/Skryx-L-A/quassel`, license in the shipped
`LICENSE`). The module installs it offline on Ubuntu 24.04+ x86_64, CPU only, under `$HOME`, without
changing the app apart from the name mapping below. Quassel's own code, comments and UI texts stay as they are (partly German); only
this module's files are English.

## What ships in `kit/offline/quassel/` (about 820 MB)

| Path | Content | Source and check |
|---|---|---|
| `app/quassel-<commit>.tar.gz` | App source, release v2.7.0 (`1a36dc6`) | GitHub archive, sha256 pinned |
| `engine/quassel-engine-linux-cpu-x86_64.tar.gz` | whisper.cpp 1.8.6 `whisper-server` + libs | Quassel release v2.2.0 asset, GitHub digest = pinned sha256 |
| `models/ggml-small-q5_1.bin` (190 MB) | Default model, multilingual | Hugging Face `ggerganov/whisper.cpp`, pinned revision, LFS sha256 |
| `models/ggml-medium-q5_0.bin` (539 MB) | More accurate, slower | same |
| `models/ggml-silero-v5.1.2.bin` | Voice activity detection | Hugging Face `ggml-org/whisper-vad`, pinned revision |
| `bin/ydotool`, `bin/ydotoold` | ydotool 1.0.4 | upstream release binaries, sha256 pinned |
| `debs/*.deb` | wl-clipboard, xclip, libnotify-bin, curl + libcurl4t64, libxcb-cursor0 + deps | Ubuntu noble release pocket, sha256 from the `Packages` index |
| `wheels/*.whl` | PySide6-Essentials 6.9.3 + shiboken6 | PyPI, `requirements.lock` with hashes |

`fetch.lock` and `requirements.lock` hold every sha256. `fetch.sh` downloads, verifies and fails on
any mismatch; `fetch.sh --verify` checks without network; `install.sh` runs the verify first.

## Decisions

- **Engine: prebuilt, not rebuilt.** The v2.2.0 CPU engine is Quassel's own portable build
  (manylinux_2_28 container, `GGML_NATIVE=OFF`). Checked on the build host: ELF x86-64, needs at
  most glibc 2.27 and GLIBCXX 3.4.22, bundles libstdc++/libgomp, supports `--vad`, uses AVX2/FMA/F16C
  and no AVX-512, so the CPU needs AVX2 (Intel since 2013, AMD since 2015). Rebuilding would need a Linux
  container or cross toolchain on the build host, which the kit build does not have.
- **Models: small-q5_1 default, medium-q5_0 optional.** Quassel itself defaults to small-q5_1 on
  CPU and notes that medium is too slow for live dictation on CPU. Medium stays useful for longer
  clipboard dictations where a few seconds more do not matter. Switch with the control center or
  `install.sh --model medium-q5_0`.
- **Qt pill instead of GTK pill.** The app's portable bundle uses `quassel.pill_qt`; that avoids
  PyGObject, GTK4 and `gtk4-layer-shell` (an apt package that needs root). All GUI parts run from
  one venv with PySide6-Essentials (QtCore/Gui/Widgets are all the app imports). The kit's CPython
  3.12 from `00-python` is used; no system Python packages are needed.
- **ydotool from upstream.** Ubuntu 24.04 ships ydotool 0.1.8, whose command syntax Quassel cannot
  use. The 1.0.4 upstream binaries only link libc (glibc >= 2.34).
- **Deb packages are unpacked, never installed.** `install.sh` unpacks them into
  `~/.local/share/work-kit/quassel/sysroot` with `dpkg-deb -x` (no root). Small wrappers in
  `…/tools` set `LD_LIBRARY_PATH` for that one program only. Launchers put `…/tools` at the end of
  `PATH`, so the system's own `wl-copy`, `xclip`, `notify-send` and `curl` win when present. The
  xcb libraries are only added for Qt when `ldconfig` does not know `libxcb-cursor.so.0` (Qt 6
  needs it on X11 sessions). Package release-pocket versions stay in the Ubuntu archive; `-updates`
  versions can disappear when superseded.
- **Prefixed names (owner decision 2026-09-25).** Quassel IRC packages install `quasselcore`,
  `quasselclient`, `quassel.desktop` and the icon "quassel"; the voice app's generic names
  (`quasseld`, `quassel-server`, ...) sat next to them. Everything the module puts on `PATH`, into
  the systemd user units, the launcher and the icon theme is now `work-kit-quassel-*` (table below).
  The app name "Quassel" in texts, the data directory `~/.local/share/work-kit/quassel`, the
  app's config directory `~/.config/quassel` (Quassel IRC uses `~/.config/quassel-irc.org`) and the
  app's window class stay. The app hard-codes the old unit, launcher and icon names in its Python
  strings, so `patch-app.sh` rewrites exactly those quoted literals (and the desktop template) in
  the extracted copy at install time and fails when an old name is left; the pinned tarball is not
  touched. Check it again whenever the app version in `fetch.lock` changes.
- **Existing files are kept.** Every generated file carries the marker `work-kit:80-quassel`.
  A file at the same path without the marker is moved to `~/.local/share/work-kit/backups/80-quassel/<name>.bak-<timestamp>` first (the original path is
  recorded in `<name>.bak-<timestamp>.origin`). An
  existing `~/.config/quassel/server.env` stays if the engine and model it names exist.

## Control center start script (`bin/quassel_center.py`)

`work-kit-quassel-type` (the app-menu entry and the command the daemon and the pill use to open the
control center) runs `libexec/quassel_center.py`, which starts the unchanged app (`quassel.center.main()`)
with two adjustments. Found by a real-user run in a GNOME VM (2026-09-27); the app source stays as released.

- **Truthful texts without keyboard access.** The app's welcome says "Hold Ctrl + Meta, speak, release ... nothing you must
  configure" and its hint says "Hold Ctrl + Meta = speak". Without root steps that key cannot work, so a
  user following the text got nothing. The script checks what the daemon needs (`/dev/uinput` writable and a
  readable `/dev/input/event*`); when it is missing it replaces the strings `ob_body`, `hint`, `on`, `off`
  in the app's string table (English and German) before the window exists: they name the GNOME shortcut
  (read from gsettings; without one, the command to bind), the clipboard and Ctrl+V, and say that hold-to-talk needs the
  one-time administrator setup. The on/off switch then starts only `work-kit-quassel-server` (the daemon
  would exit at once and restart every 3 s), and the status shows whether the speech engine runs. With keyboard
  access nothing is replaced and the app's own texts apply. The check runs at each start, so the texts
  change after `root-steps.sh` and a new login without reinstalling.
- **Window size.** The app sizes its window by content (680x520 at least). With larger fonts that is
  taller than a 1280x800 screen (measured: 1362x1080 at 192 dpi, 1022x820 at 144 dpi). The script
  lowers the minimum to 560x420 and caps the first size at the screen minus a frame margin. 560 px lets two
  windows share a 1280 px screen, so the kit tiler tiles it as a normal window (the app's 680 px minimum
  overlapped the neighbour by 40 px). No tiler rule is needed: the window is resizable, not transient, not a dialog.
  The welcome dialog is transient and floats by design.

Both hooks only replace values and one method (`Center.show`) at run time; if the app changes and a name
is missing, the script fails at start, and `tests/test_center.py` covers the logic.

## Modes

**Clipboard mode (no root, default).** Quassel's daemon reads `/dev/input` for the Ctrl+Meta hotkey
and types through `/dev/uinput`; both need root setup. Without it, `work-kit-quassel-dictate` (a helper of
this module, not part of the app) gives dictation through a desktop shortcut (on GNOME `install.sh` binds
`Ctrl+Alt+D` with `shortcut.sh --ensure` when it runs inside the desktop session and no shortcut of ours is
set yet; over ssh or on another desktop it prints the command to run instead): first press records
(`pw-record` or `parecord`), second press stops, the local `work-kit-quassel-server` transcribes, and the
text goes to the clipboard. The helper reuses the app's modules for the request (language,
dictionary prompt, `audio_ctx`), post-processing, text replacements and history, so results match
the app. It sends the request with Python's `urllib`, so it does not need curl. If no clipboard tool
works, the text is written to `$XDG_RUNTIME_DIR/quassel-kit/last.txt` (mode 600, cleared on
logout). A recording stops after 300 s. If keyboard mode is set up, the helper pastes directly.

**Keyboard mode (root once).** `root-steps.sh` adds the user to group `input`, installs a udev rule
for `/dev/uinput` and loads the `uinput` module. Security impact, to clear with IT on a managed
laptop: every process of the user can then read all keyboard input, including passwords, and inject
keystrokes. `root-steps.sh --undo` reverts all of it. `work-kit-quassel-ctl start` refuses to start the daemon
while `/dev/uinput` is not writable and starts only the speech server.

## Installed layout

```
~/.local/share/work-kit/quassel/   app/ venv/ engine/cpu/ models/ bin/ sysroot/ tools/ qtlib/ libexec/
~/.local/bin/                         work-kit-quassel-daemon -type -pill -ctl -dictate
~/.config/systemd/user/               work-kit-quassel-daemon -server -pill -ydotoold (.service)
~/.config/quassel/                    server.env and the app's own settings
~/.local/share/applications/          work-kit-quassel.desktop (extra action: dictate to clipboard)
~/.local/share/icons/hicolor/         work-kit-quassel.svg and .png
/etc/udev/rules.d/                    80-work-kit-quassel-uinput.rules   (only after root-steps.sh)
/etc/modules-load.d/                  work-kit-quassel-uinput.conf       (only after root-steps.sh)
```

## Upgrade from the names before the rename

Names up to 2026-09-25: `quasseld`, `quassel-type`, `quassel-pill`, `quassel-ctl`, `quassel-dictate`
(commands), `quasseld`, `quassel-server`, `quassel-pill`, `quassel-ydotoold` (units), `quassel.desktop`,
icon `quassel-voice`, `80-quassel-uinput.rules`, `quassel-uinput.conf`. `names.sh` holds both lists.

- `install.sh` over an old install: stops and disables the old units and cancels a running old
  dictation first, installs the new names, then moves the old launchers, units (and `*.service.d`
  drop-in directories) and `quassel.desktop` to `backups/80-quassel/` and removes the old icons.
  Only files with the module marker are touched: a `quassel.desktop` or `quasseld` that belongs to
  something else stays. If the old `quasseld` was enabled, `work-kit-quassel-daemon` is enabled in
  its place; a GNOME shortcut made by `shortcut.sh` is repointed and keeps its key binding.
  `server.env`, the models and the history stay where they are.
- `root-steps.sh` writes the new udev rule and module list and removes the old ones (it needs
  root, so `install.sh` only prints a hint when the old files exist). `--undo` and `--check` know
  both names.
- `uninstall.sh` removes the current names and, in the same way, any old ones that are left.

Nothing starts automatically. Models are hard links to `kit/offline` when both are on one disk.

## Build hook

`build/build-offline.sh` needs one step that calls `kit/modules/80-quassel/fetch.sh` and records its
files in `manifest.lock`, in the same way as the `model` step:

```bash
step_quassel() {
  local script="$ROOT/kit/modules/80-quassel/fetch.sh" f
  [ -f "$script" ] || { log "quassel: $script not present, skipped"; return; }
  KIT_OFFLINE="$OFFLINE" bash "$script" || die "80-quassel/fetch.sh failed"
  while IFS= read -r f; do
    check_or_record "file:${f#"$OFFLINE"/}" "$(sha256_of "$f")" "80-quassel/fetch.sh"
  done < <(find "$OFFLINE/quassel" -type f | sort)
}
```

plus `quassel` in the default `ONLY` list, `want quassel && step_quassel` in the run list, and
`file:quassel/*) want quassel || echo "$sum  $key  $rest" >>"$NEW" ;;` in the manifest merge.

## Updating

- App: pick a new commit or tag, fetch `https://github.com/Skryx-L-A/quassel/archive/<commit>.tar.gz`,
  put its sha256 and URL into `fetch.lock`. Check that `quassel/pill_qt.py` still exists.
- Models, VAD: take the LFS sha256 from the Hugging Face file page and pin the revision in the URL.
- Debs: take the sha256 from `dists/noble/<component>/binary-amd64/Packages.xz`.
- Wheels: edit `requirements.in`, run `fetch.sh --relock-wheels`, review, run `fetch.sh`.

## Tests

- `bash tests/smoke_install.sh`: install, upgrade over a simulated old install, re-install and
  uninstall in a throwaway `HOME`; checks layout, new and old names, markers, backups and removal. On macOS it checks the layout only (see its header).
- `bash tests/test-upgrade.sh`: the real `install.sh` and `uninstall.sh` in a throwaway `HOME` with a
  synthetic offline folder, stub `uv`/`systemctl`/`dpkg-deb`: install over an old-name install,
  second run, uninstall of new and leftover old names. `QUASSEL_OLD_MODULE=<dir>` (module checkout
  from before the rename) makes the old install come from the real old `install.sh`.
- `bash tests/test-rename.sh`: name lists, `patch-app.sh` (synthetic tree, and the real app when
  `QUASSEL_APP_SRC` points at an unpacked release), upgrade path of `names.sh` (old units stopped,
  files backed up and removed, foreign files kept, shortcut repointed, enable state carried over),
  `root-steps.sh --check/--undo` with old and new names, no old names left in the module.
- `QUASSEL_APP=<app dir> python3 -m pytest tests/`: `work-kit-quassel-dictate` toggle, stop, cancel and file
  fallback against a fake whisper server; `tests/test_center.py` (no app needed): shortcut text, keyboard
  check and the clipboard-mode strings of `quassel_center.py`.
- `bash tests/test-shortcut.sh`: `shortcut.sh` with a fake gsettings (kit CPython, venv python, no python,
  `--ensure` sets a missing shortcut and keeps an existing one). The install tests set
  `QUASSEL_KIT_NO_SHORTCUT=1` so they never write to the tester's own GNOME settings.
- Not testable on the build host: running the Linux binaries, Qt on Wayland/X11, audio recording,
  clipboard and hotkeys. They belong to the end-to-end Linux test.

## Known limits

- Clipboard on GNOME Wayland: whether `wl-copy` can set the clipboard from a shortcut without a
  focused window was not verified on the target laptop. If it fails, the text lands in `last.txt`
  and the notification says so.
- Wayland positions of the Qt pill depend on the compositor (noted by the app itself).
- `curl` from the noble release pocket is 8.5.0 without later security updates. It is used only
  if the system has no curl, and only for requests to `127.0.0.1`.
