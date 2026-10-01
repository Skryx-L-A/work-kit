# Third-party material in 95-desktop

Shipped in the module folder:
- `themes/*.toml`: colour values from Omarchy (github.com/basecamp/omarchy, MIT, (c) David Heinemeier Hansson / 37signals), `themes/<name>/colors.toml`, read 2026-09-25. The keys `yaru` and `gnome_accent` are ours.
- `keys.tsv`: the list of Omarchy 4.0 default keybindings (same source, MIT), mapped by us.
- Settings follow Omakub (github.com/basecamp/omakub, MIT per its README, archived) where Omarchy has no counterpart; no Omakub file is copied.

Downloaded by `fetch.sh` into `kit/offline/desktop` (not in git), licences as published:
- GNOME extensions from extensions.gnome.org: Tiling Shell GPL-3.0; PaperWM GPL-3.0; Tactile GPL-3.0+; Forge GPL-3.0 (LICENSE in the zip);
  Just Perfection GPL-3.0; Clipboard Indicator MIT (LICENSE.rst in the zip); Space Bar has no licence file in its repository or zip (checked 2026-09-25;
  extensions.gnome.org requires GPL-2.0+-compatible licensing). Replace or drop Space Bar if that is not enough.
- JetBrains Mono Nerd Font: font OFL-1.1 (JetBrains), patcher MIT (Nerd Fonts). OFL.txt is installed with the fonts.
- Ghostty MIT (AppImage build by pkgforge-dev, MIT); lazygit MIT; btop Apache-2.0; fastfetch MIT;
  Neovim Apache-2.0 and Vim licence; mini.nvim MIT; zellij MIT; Zed GPL-3.0/AGPL-3.0/Apache-2.0.
- Ghostty software OpenGL (`gl/`, Arch Linux packages from archive.archlinux.org): Mesa MIT (license.rst), LLVM
  Apache-2.0 WITH LLVM-exception, libdrm MIT, libedit BSD-3-Clause, ncurses MIT-X11. install.sh copies each
  package's licence file to `~/.local/share/work-kit/desktop/apps/ghostty-gl/licenses/`.
