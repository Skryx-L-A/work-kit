# 95-desktop

Ubuntu's desktop made to work like Omarchy: tiling without gaps, Omarchy keys, themes, Ghostty,
Neovim and terminal tools. GNOME (Ubuntu 22.04/24.04/26.04) and KDE Plasma (Kubuntu). Other desktops
are skipped without changes. Offline, no sudo.

Run it in a terminal inside the desktop session:

```bash
cd ~/work/kit/modules/95-desktop && bash install.sh --check
bash install.sh
```

If `--check` reports settings locked by IT, stop and ask IT. Then log out and back in.

```bash
kit-desk keys      # Super+K: all shortcuts
kit-desk menu      # Super+Alt+Space: settings, keys, theme, system
kit-desk theme     # Super+Shift+Ctrl+Space: colour themes
kit-desk status    # what is installed and what waits for the next login
```

Undo everything: `bash uninstall.sh`. Terminal tools only, no desktop changes: `bash install.sh --desktop none`.
Options (other tiler, extras, workspaces), key table, tests: `~/work/kit/docs/desktop.md`.
