# 95-desktop: Omarchy-like desktop on Ubuntu

Design notes for module `kit/modules/95-desktop`. The module README has the commands only.
Goal (owner request 2026-09-25): Ubuntu's desktop should behave as close to Omarchy 4.x as possible,
in the spirit of DHH's Omakub, offline, user level, fully reversible, and it must respect IT policy.
GNOME is the main target; KDE Plasma (Kubuntu) has its own path, any other desktop gets the
terminal parts only (owner/orchestrator request 2026-09-25: the laptop's desktop is not known).

## Research (sources and dates)

### Omakub (the Ubuntu reference)

- Repository `github.com/basecamp/omakub`, checked 2026-09-25 with the GitHub API and a clone:
  **archived** (read-only), last push 2026-04-03, last commit 2026-03-07, latest release v1.5.0
  (2025-11-09). The README states "released under the MIT License"; the repository has no
  LICENSE file. No Omakub file is copied into the kit; settings are re-implemented.
- What Omakub 1.5.0 installs and configures (from `install/`):
  - Desktop: Alacritty, Chrome, Flameshot, Ulauncher (PPA, sudo), VS Code, Obsidian, Signal,
    LibreOffice and more; fonts CaskaydiaMono Nerd Font and iA Writer Mono via `wget`.
  - GNOME: disables Ubuntu's `tiling-assistant`, `ubuntu-appindicators`, `ubuntu-dock`, `ding`;
    installs Tactile, Just Perfection, Blur my Shell, Space Bar, Undecorate, TopHat,
    Alphabetical App Grid with `gext` (network) and copies their schemas to `/usr/share` (sudo).
  - Keys: `Super+W` close, `Super+Up` maximize, `Super+BackSpace` resize, 6 fixed workspaces on
    `Super+1..6`, pinned apps on `Alt+1..9`, Ulauncher on `Super+Space` (input switching
    removed from it), Tactile grid (`Super+T` then two grid keys), gap 32 px.
  - Themes: 10 themes (Tokyo Night default) that switch Alacritty, Zellij, Neovim, btop, GNOME
    Yaru accent + wallpaper, TopHat and VS Code from a `gum` menu.
  - Terminal: Neovim with the LazyVim starter (network), zellij, btop, fastfetch, lazygit,
    lazydocker, gh, mise, Docker.
  - Everything needs network and several steps need sudo, so the kit cannot use it as is.
- The owner's reference video (ForrestKnight, "My Linux Ubuntu Setup for Software Development",
  2025-07-07, reported by the orchestrator 2026-09-25) shows Omakub with Super+1..6 workspaces,
  Super+W, Tactile, Ulauncher, no dock, a theme switcher, Neovim/LazyVim, Zed, Chrome, and the
  default window spacing removed.

### Omarchy (what "like Omarchy" means)

- The owner's PC runs Omarchy 4.0.4 (read-only over SSH on 2026-09-25): Hyprland with Lua
  config. User overrides in `~/.config/hypr/{bindings,input,looknfeel}.lua` are all commented
  out, so Omarchy's defaults apply: `/usr/share/omarchy/default/hypr/bindings/*.lua`,
  `looknfeel.lua`, `input.lua`. Active theme: Everforest. Terminal font: JetBrainsMono Nerd Font.
  Omarchy is MIT licensed (`github.com/basecamp/omarchy`); the theme colours in `themes/` come
  from its `themes/<name>/colors.toml`.
- Omarchy defaults that matter here: `Super+Return` terminal, `Super+Shift+Return` and
  `Super+Shift+B` browser (Omarchy has no plain `Super+B`), `Super+W` close, `Super+1..0`
  workspaces 1-10, `Super+Space` launcher/menu, arrows focus, `Shift`+arrows swap, dwindle
  layout, gaps 5/10 px, 2 px border, no rounding, no blur, focus follows mouse, key repeat
  40/s after 250 ms, `compose:caps`, click-finger right click, natural scroll off.
- No personal data (hostnames, names, paths) from that machine is in the kit.

### Ubuntu GNOME versions

- Launchpad API, 2026-09-25: Ubuntu 24.04 (noble) `gnome-shell 46.0-0ubuntu6~24.04.15`,
  Ubuntu 26.04 (resolute) `gnome-shell 50.1-0ubuntu1.2`. So the module targets GNOME 46 and 50.
  Ubuntu 22.04 (jammy) ships GNOME Shell 42 (the test VM on 2026-09-26: 42.9); supported since
  2026-09-26 with Forge as the tiler (see "GNOME 42" below).
- Desktop ISO manifests (`releases.ubuntu.com`, 24.04.3 and 26.04): `dconf-cli`,
  `libglib2.0-bin` (gsettings, glib-compile-schemas), `unzip`, `xz-utils`, `fontconfig`, `fuse3`
  are installed by default on both. Ubuntu's own extensions (`ubuntu-dock@ubuntu.com`,
  `tiling-assistant@ubuntu.com`, `ding@rastersoft.com`, `ubuntu-appindicators@ubuntu.com`) exist on
  both (26.04 ships them in `gnome-shell-ubuntu-extensions`, per packages.ubuntu.com).
- GNOME 47+ has `org.gnome.desktop.interface accent-color`; GNOME 46 does not (Ubuntu 24.04 uses
  Yaru colour variants instead). The module writes whichever exists.

### Tiling extensions (extensions.gnome.org API, 2026-09-25)

| Extension | Pinned version | GNOME | Behaviour | Verdict |
|---|---|---|---|---|
| kit-tiling (the kit's own, `extensions/kit-tiling@work-kit`) | module version | 46-50 | automatic: 1 window fills the work area, 2 split it, 3+ main + stack; per workspace and monitor; no gaps, a 2 px border in each tile (focused: accent) | **default** (`--tiler kit`), see "Kit tiler" below |
| Tiling Shell | 17.3 (EGO 76) | 45-50 | fixed layouts, optional auto tiling, directional focus and move keys, gaps, focus border | option `--tiler tilingshell` (was the default until 2026-09-25) |
| PaperWM | 50.0.1 (EGO 148) | 45-50 | scrolling columns (like Hyprland's scrolling layout / niri) | option `--tiler paperwm`; its keys are remapped to the Omarchy keys (see "PaperWM" below) |
| Tactile | EGO 38 | 45-51 | grid placement on demand (`Super+T` + keys), no auto tiling | option `--tiler tactile` (Omakub's choice); Ubuntu's Tiling Assistant stays on Super+arrows |
| Forge | 68 (EGO version_tag 41142) for GNOME 42; EGO 89 for 45-49 | 40-44 / 45-49 | i3-like auto tiling (split the focused window, like Hyprland's dwindle), tabbed and stacked containers | **GNOME 42 tiler** (`--tiler kit` means Forge there, `--tiler forge` too); rejected for 46/50: no GNOME 50 release |
| Pop Shell | - | - | auto tiling | rejected: not on EGO, no Ubuntu package for noble/resolute |
| Ubuntu Tiling Assistant | built in | 46, 50 | half/quarter snapping | fallback when extensions are not allowed |

All options install at user level (`~/.local/share/gnome-shell/extensions`) from a zip (the kit
tiler from the module folder), no sudo, no network. GNOME 42 zips (pinned 2026-09-26, EGO API with
`shell_version=42`): Forge 68, Tiling Shell 72 (42-44), Space Bar 22, Just Perfection 26, Clipboard
Indicator 47. PaperWM and Tactile have no GNOME 42 zip in the kit; `--tiler paperwm|tactile` on
GNOME 42 reports the missing zip and leaves GNOME's own tiling.

#### GNOME 42 (Ubuntu 22.04): Forge instead of the kit tiler

The kit tiler is an ES module extension (`import ... from 'resource:///...'`, `export default class`),
which GNOME Shell loads from version 45 on; GNOME 42 needs the older `imports.*` format with an
`init()` function. Owner decision 2026-09-26: on GNOME 42 use the closest working tiler, not a skip.
A GNOME 42 port of the kit tiler would be a second copy of its window code in the old format,
maintained beside the one that is being extended (mouse resize, kit-tiler worker), so the kit uses
Forge, which has a GNOME 42 release on extensions.gnome.org and tiles automatically.

What stays the same as with the kit tiler: every new window is tiled at once, no wasted space (the
kit writes `window-gap-size` = `--border`, default 2 px, `window-gap-hidden-on-single true`, and a
focus border of the same width), the top bar is excluded,
`Super+arrows` focus, `Super+Shift+arrows` swap, `Super+T` float, `Super+W` closes and the rest
reflows, dialogs float. All of Forge's own keys are written (its defaults hold `Super+Return`,
`Super+W`, `Super+H/J/K/L`, `Super+C`, `Super+Period` and more): the Omarchy meaning on its actions,
empty for the rest.

| Omarchy key | Kit tiler (GNOME 46/50) | Forge (GNOME 42) |
|---|---|---|
| 1 window / 2 / 3+ | full / halves / main left + stack | full / halves / the third window splits the focused one (Hyprland's dwindle, Omarchy's default) |
| `Super+J` | not bound | toggle the split direction of the focused container (as in Omarchy) |
| `Super+L` | main left / main on top | same as `Super+J` |
| `Super+Ctrl+F` | monocle | tabbed container (one window visible, a tab bar) |
| `Super+G` | not bound | tabbed container (Omarchy: window group) |
| `Super+-` / `Super+=` | main area narrower / wider | focused window's right edge in / out (`resize-amount` 15 px) |
| `Super+Shift+Alt+arrows` | the tiler's own move to monitor | GNOME's `move-to-monitor-*` |
| Focus border | 2 px border in every tile, the focused window's in the accent colour (`--border`) | 2 px (Forge's `focus-border`, Omarchy has 2 px) |
| Super + drag | swap tiles | Forge's own drag and drop (drop zones) |

Tiling Shell 72 (`--tiler tilingshell`) also runs on GNOME 42 but keeps its fixed layouts and the
first-window finding described below.

#### Kit tiler (owner request 2026-09-25: Omarchy behaviour, no wasted space)

Found in the owner's GNOME 46 VM and reproduced on GNOME 50: with Tiling Shell 17.3 the first new
window landed in a stack tile and the main tile stayed empty, and with its fixed three-tile layout
one or two windows always left empty tiles. Cause 1: its autotiling picks the vacant tile whose centre
is nearest the screen centre, and a missing bracket in that distance (`0.5 - x + width / 2`) rates
the first tile (main) worst. Cause 2: it only fills the tiles of a fixed layout; no setting makes
the layout follow the window count. So the kit ships a small tiler of its own (about 650 lines,
`extension.js` + `layout.js`, GNOME 46-50):

- per workspace and monitor, tiled windows in order: 1 fills the work area, 2 split it 50/50,
  3 or more give a main area on the left (half of the width) and a stack sharing the rest;
  no gaps, the top bar excluded; closing or moving a window reflows the rest at once;
- a border of `border-width` px (default 2, `install.sh --border 0-8`) inside every tile: the
  window sits that far inside its tile and the border fills the strip, so nothing overlaps and the
  boundary between windows is always visible (owner decision 2026-09-27). The focused window's border
  has `border-color` (the theme's accent), the others `inactive-border-color` (the theme's `muted`);
  `kit-desk theme` sets both. The border actors sit just above their window in the stacking order,
  so a window on top (monocle, floating) covers the borders below it; a focused floating window gets
  the accent border too. Borders are hidden with the window (minimized, other workspace, full
  screen, maximized) and in the overview;
- `Super+L`: main on the left / main on top; `Super+Ctrl+F`: monocle (every window fills the area,
  again: back); `Super+-`/`Super+=`: main area narrower / wider by 5 % (20-80 %, per workspace and monitor);
- `Super+T` floats the focused window (centred, 60 x 70 %), again tiles it (also one the tiler floated); `Super+arrows` move
  the focus by direction (across monitors); `Super+Shift+arrows` swap with the neighbour, at the
  monitor edge move the window to the next monitor; `Super+Shift+Alt+arrows` move it to the monitor
  in that direction (the tiler's own `window-to-monitor-*`: GNOME's move-to-monitor put a window at
  a monitor's left edge back to x = 0 of the same monitor on GNOME 46); `Super` + drag onto another
  tiled window swaps;
- not tiled: dialogs, fixed-size, minimized, maximized (`Super+Alt+F`) and full-screen windows, and
  WM classes listed in `float-classes` (default `zenity`: the kit menus float centred); a maximize in a window's first 2 s (mutter's auto-maximize,
  an app's saved state) is undone so the window tiles;
- with GNOME's `workspaces-only-on-primary` (default) the windows of a secondary monitor are one set
  for all workspaces.
- borders between tiles can be dragged with the mouse, like Hyprland (owner request 2026-09-26): the
  border between main and stack sets the main area's share (20-80 %), a border between two stack
  windows moves only that border (the two neighbours share the change, the other stack windows keep
  their size). The other windows follow while the pointer moves; on release the dragged window snaps
  into its new tile. Any edge or corner works (a corner moves both borders), also `Super` + middle
  button drag and the keyboard (`Alt+F8`, arrows, `Return`). Outer edges (screen border) and monocle
  change nothing: the window snaps back. A dragged border stops 100 px before a neighbour vanishes and
  at a neighbour's minimum size: a client that stays larger than asked has one (Ptyxis: 294 px high),
  the tiler notes it during the drag;
- the split (main share and the stack sizes) is kept per workspace and monitor while windows open and
  close: with fewer windows the first stack tiles keep their proportions, when the window count comes
  back the split is exactly as before, a new stack tile gets an even share. `Super+-`/`Super+=` change
  the same split. Splits live in memory until logout, like Hyprland (owner decision 2026-09-26); the
  screen lock, which disables and enables extensions, keeps them. `main-ratio` is the share a workspace
  starts with;
- a client that resizes itself (GNOME Terminal adding its "default terminal?" bar grew past its tile on
  GNOME 50) is put back into its tile;
- a client that does not take its tile size within 0.5 s (more than 32 px off) is asked again, first
  with one pixel less and, once it answered that, with the tile size; the wait doubles after every
  retry (0.5, 1, 2, 4, 8 s), at most four retries (`nextAsk` in `layout.js`). Found 2026-09-27 (F34):
  after its "First Steps" window closed, the Agent Workbench (Electron 40, native Wayland) drew its
  main window over the whole column but kept reporting the old window size (636x302 of 636x764);
  mutter sends no new request for a size it already asked for, so the tiler left the lower half free
  and drew the border at the old size (the "ghost" border of the Sessions window has the same cause).
  A few pixels off is a character grid and a larger window a minimum size: those are left alone after
  the retries. A client that afterwards draws or reports another size on its own while still off its
  tile gets a new round (at most three per tile size); a window that fits its tile starts over the
  next time it slips;
- on a real display the first version of the retry was not enough (F34 follow-up, VM with a QEMU
  display and virtio-gpu, GNOME 46 under gdm, x86 emulation): the Agent Workbench answered a new size
  only after 1.5 to 18 s, the tile size sent right after the one-pixel nudge reached it together with
  the nudge (so it answered only the size it already had), and the three retries were used up before
  it answered; in between it reported 636x405 while it drew 636x380. Low-priority idle callbacks
  (`PRIORITY_DEFAULT_IDLE`), which the tiler used for re-tiling and borders, waited up to 11 s while
  clients redrew (default priority: at most 0.8 s, measured with the app, a busy terminal and CPU
  load), so windows kept old tiles and borders for that long. The tiler now re-tiles and draws borders
  at default priority, sends the tile size only after the client answered the nudge, and waits longer
  after each retry. A client that draws a new buffer without reporting a new size (Electron) is looked
  at again as soon as its actor changes;
- borders follow every move and resize of the window's actor, also one the client or mutter makes on
  its own, and go at once when the window closes; a window that becomes a dialog of another one
  (transient) floats and frees its tile;
- a window that stays more than 32 px larger than its tile floats (owner decision 2026-09-27, Q4;
  `shouldFloat` in `layout.js`): centred on its monitor at its own size, raised, with the kit border
  (focused: accent, else muted), and the other windows re-tile without it. When it closes, the others
  keep their tiles. Never floated: terminals (WM class or app id names a terminal, such as Ghostty,
  GNOME Terminal, Ptyxis, Alacritty, Konsole: a character grid, or a minimum like Ptyxis' 294 px in a
  deep stack), windows that fit or are smaller than their tile (a stale Electron size is the retry's
  case), and a window the user tiled by hand with `Super+T` (for the rest of its life).
  - New windows float fast (follow-up 2026-09-27: after the retries alone, Sessions overlapped its
    neighbours for about 30 s). A window whose first frame is less than 5 s old and that never had its
    tile size floats as soon as it answered the first request made after its first frame and is still
    too large, or 1.5 s after that request without an answer (Sessions at its 700x460 minimum: 1.5 s
    after its first frame). A request sent before the first frame does not count, because the client
    draws its own size first. If such a window takes its tile size after all within 20 s (a slow client
    answering late; on the emulated VM clients answered after up to 18 s), it goes back into the tiles.
  - A floated window stays centred when the client answers the tile request only after the float: mutter
    then applies the tile position it kept for that request, pushed on screen (GNOME 46 VM, Sessions at
    536,260 instead of 268,142, follow-up 2 on 2026-09-27). The tiler centres an auto-floated window again
    after every move or resize the client or mutter makes, for 20 s after the float, until the user
    drags, resizes or moves it to another monitor.
  - Every other window floats only after the retries: a window that had its tile size once, one older
    than 5 s, or one there before the tiler started (the stale Electron sizes of F34, VS Code coming back
    from full screen with 668x422 in a 636x380 tile, which took its tile within 12 s). The tiler looks
    once more after the last retry request; a client that never answers floats about 30 s after it
    was tiled (0.5 s + four nudges with 1, 2, 4, 8 s waits, each followed by the tile size and the same
    wait). A client that draws another size meanwhile gets a new round first.

Electron child windows (`BrowserWindow` with `parent`, such as the Agent Workbench's "Sessions" and
"First Steps") carry no parent on native Wayland (mutter sees no transient), so they tile like normal
windows; where their minimum size is larger than the tile (Sessions: 700x460 content in a 636 px
column), mutter keeps the minimum and the window overlapped its neighbours. Under X11 the same windows
are transient and float. Since 2026-09-27 such a window floats within about 1.5 s of its first frame
(see above); one that fits its tile stays tiled.

Full screen (`Super+F`) and full width (`Super+Alt+F`) are mutter's own states; the tiler leaves such
windows alone and tiles them again when they leave. Checked 2026-09-27 on the real-display VM with VS
Code 1.139 (Electron): mutter gave it 1280x800 at once, but its page stayed at the old tile size until
its renderer caught up (30 s to 2 min in the emulated VM, once with "The window is not responding"),
and it later reported its old size (668x422) to mutter while it drew the whole screen. That lag is the
app's; in full screen nothing overlaps. Leaving full screen, VS Code came back with 668x422 and the
retry put it into its tile within 12 s; full width, monocle and back landed in their tiles too.

Window placement moves first and resizes second: on Wayland a combined request lands only when the
client commits a new size, and GNOME Terminal, which snaps to its character grid, sometimes kept its
size and so never moved (GNOME 46 VM).

GNOME Terminal (the terminal when Ghostty lacks OpenGL 4.3 on Ubuntu 24.04) sizes itself in whole
character cells, so a tiled GNOME Terminal ends up to one cell smaller than its tile (1278x769 in a
1280x776 tile at the default font; the owner saw about 15 px below each window). mutter ignores size
increments only for maximized and half-tiled windows, and GNOME Terminal has no setting for it
(checked all `org.gnome.Terminal.Legacy` settings and profile keys, GNOME 46). Ghostty, Ptyxis and
Konsole fill their tiles exactly (measured).

Only resize grabs change the split: a move (`Super` + drag) that also changes the size, as a terminal
on its character grid does, swaps and nothing else. `Alt+F8` does not resize GNOME Terminal at all,
with or without the tiler (GNOME 46 and 50 VM); GTK 4 windows and Ptyxis resize with it.

Border drags verified 2026-09-26 in two fresh VMs, GNOME Shell 50.1 (Ubuntu 26.04) and 46.0 (Ubuntu
24.04), headless Wayland, 1280x800, with real pointer drags through Mutter RemoteDesktop on the
windows' own resize borders (GTK 4 test windows, Ptyxis on 50, GNOME Terminal on both). Frame rects,
GTK 4 on GNOME 46 (GNOME 50 the same):

| Step | Result |
|---|---|
| 3 windows | main 0,32 640x768; stack 640,32 / 640,416 640x384 |
| stack window's left edge 640 to 800 | while dragging main 722 wide and the stack at 722; after release main 804, stack 804,32 476x384 twice |
| main's right edge 100 px left | main 704, stack at 704 |
| border between the stack windows 416 to 300 | upper 704,32 576x272, lower 704,304 576x496, main unchanged |
| main's outer corner (`Super` + middle drag) | follows while dragging, snaps back on release |
| close a window, reopen it; one window, three again | 704 / 576 split kept, with three windows exactly the rects above |
| `Super+=` | main 768 |
| `Alt+F8`, Right x4, `Return` | stack follows while resizing, main 798 after `Return`; Left (outer edge): unchanged |
| `Super` + drag of a stack window onto main | swapped, split unchanged |

With Ptyxis the stack border stopped at the upper window's minimum height (294 px, lower window from
y 326), no overlap. A second monitor keeps its own split (monitor 1 dragged to 904, monitor 2 stays
640 / 640). After the extension is disabled and enabled the split is unchanged; a new session starts
at 50 %. GNOME Terminal ends a few pixels short of its tile as before (character grid).

The tiler keeps no state on disk; its settings live in `/org/gnome/shell/extensions/kit-tiling/`
(key names as in Tiling Shell, so `keys.tsv` serves both; `kit:` rows only for the kit tiler).
Tiling Shell stays available with `--tiler tilingshell`; its first window still goes to the stack. Extras: Space Bar (workspace numbers in the top bar, like Omarchy's bar; version 34
for GNOME 46-49, version 39 for GNOME 50 only) and Just Perfection (thin top bar, no workspace
popup). `fetch.sh --check-meta` verifies that each pinned zip lists its GNOME major in
`metadata.json`; the result on 2026-09-25 was ok for all ten zips.

### Other choices

- Launcher: Omarchy's Walker and Omakub's Ulauncher both need packages outside the stick (Walker
  needs layer-shell, which GNOME lacks; Ulauncher is only in a PPA). `Super+Space` opens GNOME's
  overview as the launcher instead: offline, no install, IT-neutral. Just Perfection hides the dash,
  the workspace thumbnails and the next-workspace peek there (`dash`, `workspace`, `workspace-peek`
  false), so it is a search field over the open windows: typing searches at once, `Enter` starts
  the first hit, `Escape` closes it (owner walkthrough 2026-09-27: the full app grid was too much;
  the app grid stays on `Super+A`). `Super` alone does nothing, like Omarchy (mutter `overlay-key`
  empty; `--skip superkey` keeps GNOME's overview on it).
- Terminal: Ghostty (Omarchy's default terminal alongside Alacritty) has no official Linux
  binary; the kit ships the pkgforge-dev AppImage 1.3.1 and unpacks it with
  `--appimage-extract` at install time, so no FUSE is needed. Without a GPU that gives OpenGL 4.3
  it uses the kit's software OpenGL (see "Ghostty without a GPU" below). Alacritty has no official
  Linux binary either; it is in Ubuntu universe (0.13.2 noble, 0.16.1 resolute, none in jammy) and
  is offered through `apt.sh` (sudo, needs a 01-prereqs item). Fallbacks for `Super+Return`:
  Ghostty with software OpenGL, Alacritty, Ptyxis (26.04), GNOME Terminal (22.04, 24.04).

#### Ghostty without a GPU: software OpenGL for Ghostty only (owner decision 2026-09-25, measured 2026-09-26)

Ghostty 1.3 needs OpenGL 4.3. The AppImage brings its own libraries through sharun, including a Mesa
26.0.1 (Arch Linux build `26.0.1-arch1.1`), but a reduced one: `libgallium-26.0.1-arch1.1.so`
(31 MB) has no llvmpipe and no libLLVM, so without a usable GPU driver Mesa falls back to softpipe,
which offers OpenGL 3.3. The system's own Mesa is not used by the AppImage. Measured in a qemu
x86_64 VM without GPU (Ubuntu 22.04, TCG): the system Mesa 23.2.1 gives llvmpipe with OpenGL 4.5
(`glxinfo -B`), Ghostty from the AppImage logs `loaded OpenGL 3.3`, `OpenGL version is too old`
and closes, on Xvfb (X11) and on a headless weston (Wayland) alike.

The fix needs no sudo and touches nothing outside the kit: the same Mesa build with llvmpipe (Arch
Linux `mesa 1:26.0.1-1`, whose `libgallium-26.0.1-arch1.1.so` has the same name) and the libraries
it needs that the AppImage lacks (`libLLVM.so.21.1` from `llvm-libs 21.1.8-1`, `libdrm_intel.so.1`
from `libdrm 2.4.131-1`, `libedit.so.0` and `libncursesw.so.6` for libLLVM). sharun puts
`SHARUN_EXTRA_LIBRARY_PATH` before its own libraries, so Ghostty loads these instead of its reduced
Mesa. Five pinned packages (sha256 in `pins.conf`), 55 MB on the stick; `install.sh` unpacks the
five libraries with `zstd` and `tar` to `~/.local/share/work-kit/desktop/apps/ghostty-gl`
(201 MB, licence files beside them).

| Test (qemu x86_64, no GPU, Ubuntu 22.04) | OpenGL | Window |
|---|---|---|
| Ghostty AppImage alone, Xvfb (X11) | 3.3 (softpipe), closes | none |
| same with the pack, Xvfb | 4.5 (llvmpipe), verdict after 14 s | shell prompt drawn (screenshot) |
| Ghostty AppImage alone, weston headless (Wayland, pixman) | 3.3, closes | none |
| same with the pack, weston | 4.5, after 11 s | shell prompt drawn (screenshot) |
| real `install.sh --desktop none`, then `kit-desk term` on Xvfb | 3.3 first, `kit-desk` restarts it with the pack: 4.5 | drawn; the next `kit-desk term` starts with the pack at once |

The pack is used only when needed, so a laptop with a working GPU keeps the AppImage's own Mesa
(hardware drivers iris, radeonsi, nouveau and the rest are in both builds): `kit-desk term` runs
Ghostty; when it reports an OpenGL older than 4.3, `kit-desk` writes `state/ghostty-sw` and starts
it again, and the `ghostty` wrapper in `~/.local/bin` sets `SHARUN_EXTRA_LIBRARY_PATH` whenever that
file exists. Only if Ghostty fails with the pack too, `state/ghostty-broken` is written and
`Super+Return` goes on to Alacritty (if installed with `apt.sh`) and then the desktop's terminal.
A re-install removes both state files, so the check runs again.

Since Ghostty works this way without sudo, the kit does not ship Alacritty as a binary and does not
ask for sudo (the owner decision asks for both only when the no-sudo way fails). `apt.sh alacritty`
stays as the optional sudo path. The pack is tied to the AppImage's Mesa version: `install.sh`
installs it only when the unpacked Ghostty has `libgallium-26.0.1-arch1.1.so`; a new Ghostty
AppImage needs the matching Arch Mesa, LLVM and libdrm pins.
- Font: JetBrainsMono Nerd Font 3.5.1 (what the owner's Omarchy uses; font under OFL-1.1).
  Only the `JetBrainsMonoNerdFont-*` family is installed, not the Mono/Propo/NL variants.
- Neovim 0.12.5 tarball plus mini.nvim 0.18.0 as the only plugin: LazyVim-style keys (`Space`
  leader, `Space Space`/`Space f f` files, `Space /` grep, `Space e` explorer, `Space g g`
  lazygit, `Shift+H/L` buffers) that work offline. LazyVim itself downloads ~30 plugins on first
  start, so it is not the default; the config says how to switch when network is allowed.
- Zed 1.21.0 (optional, `--with zed`): official Linux tarball, user level. Needs Vulkan; telemetry
  and AI features need network and should be reviewed against company policy.
- VS Code's theme is not changed (orchestrator instruction 2026-09-25).
- Clipboard history: Clipboard Indicator (EGO version 71, GNOME 46-50, MIT, the most used GNOME
  clipboard manager) on Omarchy's `Super+Ctrl+V`; history kept in memory only, since clipboard
  contents can include passwords and customer data. KDE uses its built-in Klipper.
- Menus (`Super+Escape` system menu, `Super+Alt+Space` kit menu) use zenity or kdialog, which the
  Ubuntu and Kubuntu desktops ship, instead of Walker (needs layer-shell, not available on GNOME).
- Emoji: GNOME's IBus emoji window (`ibus emoji`, on every Ubuntu desktop) instead of Walker's
  emoji mode; on KDE the Plasma emoji picker.

### KDE Plasma (2026-09-25)

- Kubuntu 24.04 ships Plasma 5.27 (the test VM had 5.27.12), Kubuntu 26.04 ships Plasma 6.
- Tiling: Krohnkite, a dynamic tiling KWin script (MIT), installed at user level with
  `kpackagetool5/6 --type=KWin/Script`, or, when kpackagetool is missing (it is only a recommended
  package; a minimal Plasma 6 install lacks it), by unpacking the `.kwinscript` zip into
  `~/.local/share/kwin/scripts/krohnkite`. Version 0.8.1 (`github.com/esjeon/krohnkite`, 2022) is the
  last one for Plasma 5; 0.9.9.2 (`github.com/anametologin/krohnkite`, July 2025, Plasma 6 API,
  repository archived since) for Plasma 6. Both default to zero gaps and share the config keys, so
  one code path serves both.
- Krohnkite 0.8.1 on a Plasma 5.27 **Wayland** session tiled no native Wayland window (Kubuntu 24.04
  VM, KWin 5.27.11, 2026-09-26): its `adjustGeometry` reads `client.basicUnit`, which KWin 5.27 sets
  only for X11 windows, and stopped with `TypeError: Cannot read property 'width' of undefined`
  (script.js line 649). Kubuntu 24.04 starts X11 by default, Wayland is one click away at the login.
  The kit adds one guard to its own copy after the install (`if (this.client.basicUnit && ...)`,
  `kde_krohnkite_wayland_fix` in `lib/kde.sh`); with it the same session tiles main + stack without
  gaps. A Krohnkite the user installed is not changed.
- Rejected: Polonium 1.2.1 (MIT, maintained, Plasma 6 only). It tiles through KWin's own tile
  manager, whose 4 px padding is stored per output UUID in `kwinrc`, which is not known before the
  first login on the laptop. That breaks the zero-gap requirement for an offline install.
- `kglobalshortcutsrc` is owned by the running shortcut daemon (kglobalaccel): it keeps the file in
  memory and writes it back over any change made while it runs. Measured in the VM: keys written
  with `kwriteconfig5` were gone within seconds, before the logout. The module therefore writes
  them from a login hook in `~/.config/plasma-workspace/env/`, which Plasma runs before it starts
  the daemon (see "KDE path" below).

## Desktop detection and support matrix

`install.sh` picks the path from the running session (`XDG_CURRENT_DESKTOP`, then the running
`gnome-shell`/`plasmashell` process, then what is installed) and prints it first, for example
`desktop: GNOME Shell 46 -> GNOME path`. `--desktop gnome|kde|none` overrides the detection.

Desktops of the other Ubuntu flavours (owner request 2026-09-25, done 2026-09-26): Xfce (Xubuntu),
LXQt (Lubuntu), MATE (Ubuntu MATE), Budgie (Ubuntu Budgie), Cinnamon (Ubuntu Cinnamon), and also
Unity, UKUI (Ubuntu Kylin), GNOME Flashback, LXDE, Pantheon, Deepin, Enlightenment, Lomiri and any
other unknown `XDG_CURRENT_DESKTOP`. They are checked before GNOME, because Budgie reports
`Budgie:GNOME`, GNOME Flashback `GNOME-Flashback:GNOME` and Unity `Unity:Unity7:ubuntu`. Without a
session variable (SSH) the running session process decides (`xfce4-session`, `lxqt-session`,
`mate-session`, `budgie-panel`, `cinnamon`, ...), then what is installed. On such a desktop
`install.sh` stops before it writes anything (no state directory, no dconf access) and prints

```
[desktop] desktop Xfce (Xubuntu) is not supported (95-desktop: GNOME Shell 42-50 and KDE Plasma 5/6), module skipped, nothing changed
[desktop] terminal, font and TUIs without any desktop change: bash .../install.sh --desktop none
KIT_MODULE_SKIPPED: desktop Xfce (Xubuntu) is not supported (...), module skipped, nothing changed
```

and exits 0. The last line is for `kit/install`: with the installer change proposed on 2026-09-26
(`skipped` status, not in this module's paths) the run shows `skipped, nothing changed: <reason>`
and the check report `95-desktop  skipped  <reason>`, no logout box. Without that change the
installer runs the module's `check`, which passes on such a desktop (`install.sh --unsupported`),
so the report reads `installed  check ok`. `--desktop none` still installs the terminal parts
(Ghostty, font, TUIs, Neovim, terminal themes) there, as before. A machine with no desktop at all
(server, SSH without any desktop installed) keeps the old behaviour: terminal parts only.

| Desktop | Window manager part | Keys | Terminal, fonts, TUIs, nvim, terminal themes | Tested |
|---|---|---|---|---|
| Ubuntu 22.04, GNOME 42 | Forge (the kit tiler needs GNOME 45+), Space Bar 22, Just Perfection 26, Clipboard Indicator 47; dock off | dconf (keys.tsv) + Forge's keys | yes | VM test 4: Wayland (2 monitors, login deferral) and X11, real keys, install/uninstall cycles |
| Ubuntu 24.04, GNOME 46 | kit tiler (default) or Tiling Shell, Space Bar, Just Perfection, Clipboard Indicator; dock off | dconf (keys.tsv) | yes | VM: X11 session (test 1) and Wayland session with 2 monitors, login deferral, install/uninstall cycle (test 2) |
| Ubuntu 26.04, GNOME 50 (Wayland only) | same extensions (GNOME 50 zips) | dconf | yes | VM: Wayland session with 2 monitors, all tilers, keys, apps, cycles (tests 2 and 3) |
| GNOME 46 and 50, kit tiler (default) | kit-tiling: 1 window full, 2 halves, 3+ main + stack | dconf (its own schema) | yes | VM test 3: real windows measured on both, 2 monitors, install/uninstall cycles |
| GNOME with `--tiler paperwm` | PaperWM (scrolling columns), keys remapped | dconf + PaperWM keys | yes | VM GNOME 50 (test 2) |
| GNOME with `--tiler tactile` | Tactile grid, Ubuntu's Tiling Assistant kept | dconf | yes | VM GNOME 50 (test 2) |
| Kubuntu 24.04, Plasma 5.27 | Krohnkite 0.8.1 (with the kit's guard for Wayland windows), panel auto-hide, no borders | kglobalshortcutsrc (keys-kde.tsv) | yes | VM, real Plasma X11 session (tests 1 and 4) and Wayland session (test 4) |
| Kubuntu 26.04, Plasma 6 | Krohnkite 0.9.9.2 | kglobalshortcutsrc (Plasma 6 names) | yes | VM: real Plasma 6.6 Wayland session with 2 outputs, keys, apps, cycle (test 2) |
| GNOME with extensions locked by IT | none: dock stays, GNOME's own half tiling | dconf | yes | VM (policy lock, test 1, GNOME 46) |
| Xubuntu, Lubuntu, Ubuntu MATE, Ubuntu Budgie, Ubuntu Cinnamon (and the other desktops above) | module skipped, nothing changed (`--desktop none`: terminal parts) | none | only with `--desktop none` | VM test 4: real sessions of all five on Ubuntu 22.04, in the session and over SSH |
| No desktop (server, company image without GUI, SSH) | none, with a report line | none | yes | stub tests |

x86_64 binaries (lazygit, btop, fastfetch, nvim, Ghostty): run in the arm64 VMs through Rosetta
(test 2). Ghostty's window could not be shown there (no GPU); the rest ran in real terminals.
Not tested anywhere yet: a real x86_64 laptop with a GPU (Ghostty rendering, font, padding), the
lock screen (needs GDM/SDDM), a browser key on a real login (the Firefox snap refuses to start
outside a login session), Alacritty (sudo path), a German keyboard layout on Wayland.

## Everyday actions (usability review 2026-09-25)

The dock is off, so every everyday action must work from the keyboard and be findable. `Super+K`
lists all of them; it opens once by itself after the first login (a notification plus the key
table, from `~/.config/autostart/work-kit-desktop-welcome.desktop`). The key window waits until
the tiler has placed it (terminal size unchanged for 0.6 s), then wraps the texts to its width at word
boundaries with a hanging indent (`kit-desk keys --width N`; a narrow tile cut words before,
owner walkthrough 2026-09-27).

| Action | GNOME | KDE Plasma |
|---|---|---|
| Open an app | `Super+Space` launcher (type, `Enter`), `Super+A` app grid; `Super` alone does nothing | `Super+Space` KRunner; `Meta` alone does nothing |
| Switch workspace with the mouse | click its number in the top bar (Space Bar, no overview) | the Plasma pager |
| Run a command | `Alt+F2` | `Alt+F2` |
| Kit menu (settings, keys, theme, system) | `Super+Alt+Space` | `Super+Alt+Space` |
| Terminal, browser, files, editor | `Super+Return`, `Super+Shift+B`, `Super+Shift+F`, `Super+Shift+N` | same |
| Switch windows / workspaces | `Alt+Tab`, `Super+1..6`, `Super+Tab` | same |
| Close, full screen, maximize, float | `Super+W` (`Alt+F4`), `Super+F`, `Super+Alt+F`, `Super+T` | same |
| Tiling focus, swap, next layout, resize | `Super+arrows`, `Super+Shift+arrows`, `Super+L`, `Super+-`/`Super+=` (German layout: `Super++`) | same |
| Screenshot, screen recording | `Print`, `Alt+Print` | `Print` (Spectacle) |
| Clipboard history | `Super+Ctrl+V` (Clipboard Indicator) | `Super+Ctrl+V` (Klipper) |
| Emoji | `Super+Ctrl+E` (IBus emoji window, copies to the clipboard) | `Super+Ctrl+E` (Plasma emoji picker) |
| Notifications | `Super+Comma` (`Super+V` too) | bell in the panel (no key) |
| Settings | `Super+Ctrl+S`; sound, Bluetooth, network, display, power on `Super+Ctrl+A/B/W/D/P`; `Super+S` quick settings | same keys (KCM modules, else System Settings) |
| Lock, log out, restart, power off | `Super+Ctrl+L`, `Super+Escape` menu, `Ctrl+Alt+Delete` | same |
| Volume, brightness, media | media keys | media keys |
| Keyboard layout (German QWERTZ and US) | `Super+Ctrl+Space` | `Super+Ctrl+Space` |
| Move a window to another monitor | `Super+Shift+Alt+arrows` | `Super+Shift+Alt+Left/Right` |

Not stuck without the dock: `Super` alone always opens the overview or launcher, `Alt+F2` always
runs a command, and when IT locks extensions the dock is not disabled at all. `Super+Return`
falls back from Ghostty to Ghostty with the kit's software OpenGL, then Alacritty, then the
desktop's own terminal (GNOME Terminal/Ptyxis on GNOME, Konsole on KDE). Ghostty 1.3 needs OpenGL
4.3; without it (no GPU, old driver, VM) it logs "OpenGL version is too old" and exits with status
0 before a window appears. `kit-desk term` watches Ghostty's log: on that message it starts Ghostty
again with the software OpenGL and remembers that (`state/ghostty-sw`); if that fails too, or on
any other start error, it writes `state/ghostty-broken` and opens the next terminal, now and from
then on.
The menus use zenity, else kdialog, else a numbered list in a terminal.

Layout: German QWERTZ works with all keys (they are letters, digits, arrows and named keys).
`Super+Shift+N` on KDE/X11 arrives as `Super+!`, `Super+@` (US) or `Super+"`, `Super+§` (German);
the module binds all of them. `--skip input` keeps Caps Lock (GNOME otherwise makes it Compose).

## What install.sh changes (GNOME)

Order: policy check, `dconf dump /` backup, files, extensions, keys, settings, theme, report.
Every dconf write goes through a journal (`~/.local/share/work-kit/desktop/state/`): the
original value (or "unset") is recorded once, list keys (enabled extensions, custom shortcuts,
xkb options) record only the items added or removed, so other entries the user adds later survive
`uninstall.sh`. Files that existed are moved to
`~/.local/share/work-kit/backups/95-desktop/<path below $HOME>.bak-<timestamp>` (with a
`.origin` file holding the original path; nothing is left beside the file) and moved back on
uninstall; user configs that were there before the kit (`~/.config/nvim`, `~/.config/ghostty/config`)
are never replaced.
`uninstall.sh` also clears the settings directories of the extensions the module installed (they
write their own keys at first start) and first empties Tiling Shell's record of the GNOME keys it
overrode, because Tiling Shell writes those back when it is disabled.
Uninstalling inside a running session makes GNOME stop the removed extensions at once. Several of
them write GNOME keys while they stop, after `uninstall.sh` restored them: PaperWM writes back every
key it emptied (as explicit values), Just Perfection `enable-animations`, Space Bar its styles, and
Ubuntu's Tiling Assistant, enabled again, records the kit's key values as its originals. A live
disable can also fail half-way (Space Bar and Clipboard Indicator ended in state ERROR in the GNOME
50 VM). `uninstall.sh` therefore waits (at most 10 s) until none of the extensions is active and
leaves a one-time login script (`~/.config/autostart/work-kit-desktop-restore.desktop` and
`~/.local/share/work-kit/desktop-restore-gnome/restore.sh`): at the next login, when the
extensions no longer run, it resets their settings and puts these keys back from the journal, else
from the dconf dump taken before the first install, else to the schema default, then deletes itself.
A re-install after a kit update replaces the module's own files without new `.bak` copies.

User config files with a kit default (Ghostty `config`, `alacritty.toml`, zellij `config.kdl`, nvim
`init.lua`; `put_config` in `install.sh`) follow a kit update only while the user left them alone
(owner decision 2026-09-27, Q3). The installer notes the sha256 of every such file it writes in
`state/config-hashes.tsv`. On a re-install:

- the file still has the content 95 wrote last time: it is replaced by the new kit default
  (`updated <file> to the new kit default` in the install output);
- 95 wrote the file and the user changed it since: it stays, and the new kit default goes next to it
  as `<file>.kit-new`, with one line in the install output (`kept your changed <file>; the new kit
  default is in <file>.kit-new`). Once the file equals the kit default again (the user copied the
  `.kit-new` over it), the `.kit-new` goes and later kit updates move the file again;
- 95 wrote the file under an older kit that noted no hashes: treated like a changed file (kept, plus
  `.kit-new`), because the old default is not known;
- the file was there before 95 (not in `state/files.tsv`): it stays untouched, without a `.kit-new`
  (`kept your <file> (not replaced)`), as before.

`uninstall.sh` removes the `.kit-new` files with the module's other files. Extensions the user had
installed before the kit are left alone as before.

### Wayland: what waits for the next login (owner install test 2026-09-25)

GNOME on Wayland cannot restart the shell, so an extension installed now is loaded only at the
next login. The first version switched the Ubuntu Dock off at once: the dock vanished, the new
extensions were not running yet, and the screen showed an empty grey strip. Now the install is
split:

| When | Applied at install | Queued for the login |
|---|---|---|
| Wayland session (or unknown session type), the extension is not running yet | extension files, enabled-extensions, extension settings, kit shortcuts, workspaces, input, theme | dock and desktop icons off, Ubuntu tiling assistant off, the tiler's keys, GNOME's half-screen tiling and maximize keys freed, `Super+L` and `Super+Shift+arrows` handed over |
| X11 session | everything at once (the shell restarts with `Alt+F2`, `r`, or a login) | nothing |
| Wayland, `gnome-extensions info` already reports the extension ACTIVE, or an earlier login already applied the queue | everything at once | nothing |

Until the login the desktop is the old one: the dock stays, `Super+Left/Right` keep GNOME's tiling,
`Super+L` locks. `--defer yes|no|auto` overrides the choice (`auto` is the default).

How it works: while `KD_DEFER=1`, `kd_write`, `kd_list_add` and `kd_list_remove` (`lib/desk.sh`) append
`op<TAB>path<TAB>value` to `state/pending-login.tsv` instead of writing (locked keys are still
reported at install time). The keys are written twice: first in the state without the tiler,
then queued in the state with it. `install.sh` also writes `~/.config/autostart/work-kit-desktop-finish-login.desktop`.
At the login `kit-desk finish-login --login` waits up to 300 s for `gnome-extensions info` to report
the extension ACTIVE (`defer_anchor` in `state/install.conf`), replays the queue through the normal
journaled writers, checks each change (list items present or gone, writes accepted), then deletes
the queue and the autostart entry and records the extension in `state/login-applied`. If the
extension did not load (state ERROR, OUT OF DATE, or not ACTIVE within the wait), nothing is applied:
the dock stays, the queue and the autostart entry stay (the next login tries again), a notification
says so, and `kit-desk status` shows it; `kit-desk finish-login --force` applies it anyway. A change
that fails is kept for the next run; after three runs it is dropped and reported. Every run writes
`state/finish-login.log` (start, anchor states with seconds since start, counts, extension states
after the disable, done); a lock (`state/finish-login.lock`) keeps the autostart run and a run by hand
apart. By hand, in a terminal of the desktop session, `kit-desk finish-login` waits 30 s and prints
what it does. Because the replay uses the journal, `uninstall.sh` restores those keys like any other.

Owner walkthrough 2026-09-27 (Ubuntu 24.04 VM, x86_64 emulated, fresh user): after the re-login the
35 queued changes were not applied, the queue and the autostart entry were still there and no report
line was written. Cause: the first `gnome-extensions info` at the login D-Bus-activates the
`org.gnome.Shell.Extensions` service; on a slow machine that call failed (exit 2), and `set -e` with
`pipefail` in `kit-desk` ended `finish-login` at that line without a message. Reproduced in an arm64
GNOME 46 VM with a `gnome-extensions` wrapper that fails while the shell is younger than 25 s (old
code: queue and entry stayed, dock visible; new code: waited 12 s, applied 35, dock and Tiling
Assistant INACTIVE). `finish-login` now runs without `set -e` and checks every step itself.

Where the user sees it: the install report ends with a "PENDING until the next login" block (what
waits and why), and `kit-desk status` prints the same block for as long as the queue is not empty.
`uninstall.sh` removes the autostart entry first, even when nothing else is left to undo.

### No wasted space (owner requirement 2026-09-25)

| Setting | Value |
|---|---|
| Kit tiler (default) | no gaps; a 2 px border inside every tile (`--border`, 0 = none), the focused window's in the accent colour; 1 window = whole work area, 2 = halves, 3+ = main + stack |
| mutter `auto-maximize` | `false` while a tiler runs (mutter maximized the lone first window, which a tiler leaves alone) |
| dash-to-dock `dock-fixed` | `false` (a dock disabled at the login step can end in state ERROR and keep its strip otherwise) |
| Tiling Shell `inner-gaps`, `outer-gaps` | `uint32 2` (= `--border`), `uint32 0`: a visible line between windows, none at the screen edge |
| Tiling Shell `enable-autotiling` | `true` (new windows tile automatically) |
| Tiling Shell layouts | ours first: "Main and stack" (60 % + two stacked 40 % tiles, the closest to Omarchy's dwindle), "Halves", "Thirds", "Grid"; `Super+L` cycles. Tiling Shell's default layout has 22 % side columns, too narrow on small screens. A layout list the user changed is kept. |
| Tiling Shell focus border | `enable-window-border true`, width `uint32 2` (= `--border`), colour = theme accent |
| PaperWM `window-gap` / `horizontal-margin`, `vertical-margin`, `vertical-margin-bottom` | `2` (= `--border`) / `0` |
| Tactile `gap-size` | `2` (= `--border`) |
| Forge `window-gap-size`, `focus-border-size` | `uint32 2` (= `--border`) |
| Krohnkite (Plasma) `tileLayoutGap`, `screenGapBetween` / `screenGap*` | `2` (= `--border`) / `0`; Plasma draws no focus border here |
| Top bar (Just Perfection `panel-size`) | `24` px |
| Dock | `ubuntu-dock@ubuntu.com` and desktop icons `ding@rastersoft.com` disabled (`--keep-dock` keeps them); on Wayland at the next login, see above |
| Title bar buttons | `org.gnome.desktop.wm.preferences button-layout ':'` (none; close with Super+W or Alt+F4) |
| Ghostty | `window-decoration = none`, `window-padding-x = 0`, `window-padding-y = 0` |
| Alacritty | `decorations = "None"`, `padding = { x = 0, y = 0 }` |
| Zellij | `pane_frames false`, compact layout |

Title bars of GTK4/libadwaita apps (Settings, Files) and of GNOME Terminal are drawn by the app
itself and cannot be removed from outside; Ghostty and Alacritty have none. With the kit tiler every
window tiles; with `--tiler tilingshell` a fourth window on a three-tile layout floats in the middle
until a tile is free.

### Other settings

- Workspaces: `dynamic-workspaces false`, `num-workspaces 6` (`--workspaces 1-10`).
- Focus follows mouse (`focus-mode 'sloppy'`), `center-new-windows true`, no hot corner,
  `Super` + drag moves, `Super` + right drag resizes, `edge-tiling false` while a tiler runs.
- Clipboard Indicator (skip with `--skip clipboard`): history in memory only (`cache-only-favorites
  true`, only pinned items are stored), no images, cleared at boot; its own `Ctrl+F8..F12` keys are
  cleared so they do not reach applications. Private mode is one click in its menu.
- Input (skip with `--skip input`): repeat interval 25 ms, delay 250 ms, numlock on,
  `compose:caps` added to xkb options, click-finger right click, natural scroll off.
- Font: `monospace-font-name 'JetBrainsMono Nerd Font 10'`.
- Theme (default Everforest, the owner's active Omarchy theme; 10 themes): Ghostty, Alacritty,
  btop, zellij and Neovim colours from one theme file (`kit/modules/95-desktop/themes/<name>.toml`); GNOME `color-scheme prefer-dark`, Yaru
  variant (`gtk-theme`, `icon-theme`) when that variant exists, `accent-color` on GNOME 47+, a
  solid background in the theme colour (an SVG in `~/.config/work-kit/desktop/theme`, never an
  empty `picture-uri`; `--skip wallpaper` or `kit-desk theme --keep-wallpaper`),
  Tiling Shell border and Space Bar highlight in the accent colour.
- Welcome on the next login (skip with `--skip welcome`), once per install.

### Conflicting GNOME defaults that are cleared or moved

| Key | GNOME default | New value | Why |
|---|---|---|---|
| `switch-input-source` | `Super+Space`, `XF86Keyboard` | `XF86Keyboard`, `Super+Ctrl+Space` | Super+Space = launcher |
| `switch-input-source-backward` | `Shift+Super+Space` | `Shift+XF86Keyboard` | same |
| `switch-applications(-backward)` | `Super+Tab`, `Alt+Tab` | empty | Super+Tab = next workspace, Alt+Tab = windows |
| `switch-to-application-1..9` | `Super+1..9` | empty | workspaces |
| dash-to-dock `hot-keys` | `true` | `false` | same (Ubuntu Dock) |
| `rotate-video-lock-static` | `Super+O` | `XF86RotationLockToggle` | Super+O = pop out |
| `screensaver` | `Super+L` | `Super+Ctrl+L` (plus `Super+L` without a tiler) | Super+L = next tiling layout |
| `restore-shortcuts` (mutter wayland) | `Super+Escape` | empty | Super+Escape = system menu |
| `screenshot-window` | `Alt+Print` | empty | Alt+Print = screen recording |
| `maximize` / `unmaximize` | `Super+Up` / `Super+Down` | empty / `Alt+F5` | focus keys (only with a tiler) |
| mutter `toggle-tiled-left/right` | `Super+Left/Right` | empty | focus keys (only with a tiler) |
| `move-to-monitor-*` | `Super+Shift+arrows` | `Super+Shift+Alt+arrows` (plus the old keys without a tiler); with the kit tiler empty, the keys go to its `window-to-monitor-*` | swap keys (only with a tiler) |
| `tiling-assistant@ubuntu.com` | enabled | disabled (not with Tactile); its own `tile-left-half`, `tile-right-half`, `tile-maximize`, `restore-window` emptied | grabs Super+arrows; disabled at the login step it can end in state ERROR and keep the grab until the next login (GNOME 50 VM) |
| `show-desktop` (Ubuntu value) | `Ctrl+Super+D`, `Ctrl+Alt+D`, `Super+D` | `Ctrl+Alt+D`, `Super+D` | Super+Ctrl+D = display settings (gsd could not grab it, GNOME 50 VM) |
| `move-to-workspace-left/right` | also `Super+Shift+Alt+Left/Right` | those two removed | Super+Shift+Alt+arrows = move to monitor |

While Ubuntu's Tiling Assistant runs it holds `maximize`, `unmaximize`, `toggle-tiled-left/right` and
`edge-tiling` itself (empty) and puts its saved originals back when it stops, after the kit's writes.
The kit journals those originals from the assistant's `overridden-settings`, writes the keys even when
they already look empty, and `kit-desk finish-login` writes the queued values once more after the
disabled extensions stopped (in the GNOME 50 VM Super+Left otherwise went back to GNOME's half tiling).

List keys (`show-desktop`, `move-to-workspace-*`) lose only the named item and get it back on
uninstall; an unset key is reset to its schema default when that gives the same items.

Kept next to the Omarchy key: `Alt+F4` (close), `Alt+F10` (maximize), `Super+A` (app grid),
`Super+V`/`Super+M` (notifications), `Super+PageUp/PageDown`, `Ctrl+Alt+Left/Right` (workspaces).
Without a tiling extension (policy, `--tiler none`, unsupported GNOME) Super+arrows keep GNOME's
half-screen tiling and maximize.

## KDE path

- Backup of `kwinrc`, `kglobalshortcutsrc`, `kcminputrc`, `kdeglobals`, the panel layout files
  into `backup/kde-<timestamp>/` (the first one also as `backup/kde-original/`).
- Every KConfig write goes through `kc_write` (lib/kde.sh), which journals the old value or
  "unset" in `state/kconfig-journal.tsv`.
- Krohnkite from the pinned `.kwinscript` (never replaces a copy the user installed),
  `kwinrc [Plugins] krohnkiteEnabled=true`, `[Script-krohnkite]` gaps 0, `noTileBorder=true` (no
  title bars on tiled windows), `directionalKeyFocus=true` (Super+arrows move the focus; the
  default resizes the master area, found in the VM).
- `kwinrc`: 6 virtual desktops in one row, focus follows mouse, `BorderSize=None`.
  `kcminputrc`: key repeat 40/s after 250 ms (`--skip input`).
- Panel: auto-hide through the Plasma scripting API (`evaluateScript`), old values in
  `state/kde-panels` (`--keep-dock` keeps it visible).
- Colours: `kit-desk theme` applies BreezeDark or BreezeLight to match the theme.
- Keys: 17 launchers `~/.local/share/applications/work-kit-desk-NN.desktop` (one per command,
  all its keys on it) and the login hook `~/.config/plasma-workspace/env/work-kit-desktop-keys.sh`,
  which runs `kit-desk kde-keys` once at the next login, before the shortcut daemon starts. That
  writes the Omarchy keys (journaled) and clears conflicting Plasma defaults: KWin quick tiling
  (`Super+arrows`), Overview (`Super+W`), Edit Tiles (`Super+T`, Plasma 5.27), Activate Window
  Demanding Attention (`Super+Ctrl+A`), zoom out (`Super+-`), task manager entries (`Super+1..0`),
  activity switching (`Super+Tab`), `Meta+Tab` on Walk Through Windows (Plasma 6 default; left
  there, the shortcut daemon strips it without a journal entry and uninstall could not restore it),
  and Krohnkite's own `Super+H/J/K/L`, `Super+Return`, `Super+I/D`,
  `Super+Shift+F`. Lock moves from `Super+L` to `Super+Ctrl+L`.
- Friendly names in `kglobalshortcutsrc` must not contain commas (the value is
  `keys,default,name`); a comma in "System menu: lock, log out" split the value in the first VM
  run and made KRunner lose `Alt+Space`. Names are now stripped of commas and existing entries keep
  their own names.
- `uninstall.sh` restores the other KConfig files at once and leaves a one-time login hook
  (`work-kit-desktop-restore.sh` plus `~/.local/share/work-kit/desktop-restore/restore.sh`)
  that restores `kglobalshortcutsrc`, removes the Krohnkite entries the daemon added on its own and
  puts the panel visibility back in `plasmashellrc`, then deletes itself. An unset colour scheme is
  restored as BreezeLight (Plasma's default); `plasma-apply-colorscheme` refuses a scheme it thinks
  is current, so the key is reset first.
- IT policy: KDE Kiosk markers (`[$i]`) in `/etc/xdg` or the user files are reported by `--check`;
  a write that fails is reported and skipped.

## Help

`install.sh`, `uninstall.sh`, `apt.sh`, `fetch.sh` and `kit-desk` print their header comment for
`-h`/`--help` (wherever the flag stands, also after an option that takes a value, and for every
`kit-desk` subcommand) and change nothing; `kit-desk` with an unknown command exits 2. Checked by
`tests/test-install.sh` (section H) and `tests/cli-help-safety.sh 95-desktop`.

## Keybindings

Source of truth: `kit/modules/95-desktop/keys.tsv` (GNOME) and `keys-kde.tsv` (Plasma), shown by
`kit-desk keys` / `Super+K`. Shortcuts run `~/.local/bin/kit-desk` by absolute path. `N` stands for
the workspace digit: `Super+1` ... `Super+9`, `Super+0` = workspace 10, bound up to the configured
number of workspaces. GNOME accepts the modifier order `<Super><Shift>` and `<Shift><Super>` alike.

### German keyboard layout (QWERTZ, 2026-09-26)

Omarchy's keys assume a US layout. On German QWERTZ `=` is Shift+0, `/` is Shift+7, `[` `]` are
AltGr+8 / AltGr+9, `` ` `` is a dead key, and `-` sits right of the full stop. How the two desktops
bind a key decides what happens:

- GNOME (mutter) binds a key symbol to the first key that types it, lowest shift level first, and
  ignores the level when the key is pressed. `<Super>plus` is therefore the `+` key on German and the
  `=` key (shifted `+`) on US: Omarchy's Super+= place on both, one binding. `<Super>equal` would be
  Super+0 on German (the key whose Shift level is `=`), the key of workspace 10. The binding follows
  the active input source at once; nothing is rewritten when the layout changes.
- KWin (Plasma) matches a shifted symbol key by the symbol it types, without Shift: US Super+Shift+=
  is `Meta++`, German Super+Shift++ is `Meta+*`, Super+Shift+- is `Meta+_` on both, German
  Super+Shift+0 is `Meta+=`. `Meta+Shift+=` and `Meta+Shift+-` never fire. The login hook
  (`kit-desk kde-keys`) writes the keys for the first layout in `kxkbrc` (else the system layout) and
  writes them again at the next login when that layout changes.

Audit of every shipped binding with a non-letter, non-digit key (letters, digits, arrows, Tab,
Return, Space, Escape, Print and `Above_Tab` are the same key on both layouts):

| Binding | US | German before | Now |
|---|---|---|---|
| GNOME kit tiler `grow-main`, Forge `window-resize-right-increase`, PaperWM `resize-w-inc` | `<Super>equal` | Super+0 (workspace 10) | `<Super>plus`: US `=` key, German `+` key |
| GNOME kit tiler `shrink-main`, Forge / PaperWM narrower | `<Super>minus` | the `-` key (right of `.`) | unchanged |
| GNOME `toggle-message-tray` `<Super>comma`, PaperWM `<Super><Shift>comma/period` | same key | same key | unchanged |
| PaperWM defaults `drift-left/right` `<Super>bracketleft/right` | `[` `]` keys | Super+8 / Super+9 (workspaces) | cleared (not an Omarchy key) |
| Space Bar `activate-previous-key` `<Super>grave` | key above Tab | no key (dead key) | `<Super>Above_Tab` (the key above Tab on both); empty with PaperWM, which has its own |
| Plasma Krohnkite Grow Width `Meta+=` | `=` key | Super+Shift+0 (clashes with Super+Shift+0) | US `Meta+=`, German `Meta++` |
| Plasma Krohnkite Grow Height `Meta+Shift+=` | never fired (Zoom In's `Meta++` took it) | never fired | US `Meta++`, German `Meta+*`; KWin Zoom In loses `Meta++` |
| Plasma Krohnkite Shrink Height `Meta+Shift+-` | never fired | never fired | `Meta+_` on both |
| Plasma Window to Desktop N `Meta+Shift+N` | plus `Meta+@` etc. | plus `Meta+"` etc.; `Meta+=` (Shift+0) left out | German: `Meta+=` added for desktop 10 |
| Plasma Shrink Width `Meta+-`, emoji `Meta+.` | same key | same key | unchanged |

`kit-desk keys` / `Super+K` read the active layout (GNOME: first of `mru-sources`, else of `sources`;
Plasma: `kxkbrc`; both else `/etc/default/keyboard`) and name the keys as printed on that keyboard:
`SUPER + PLUS` with German, `SUPER + EQUAL` with US, plus one line that says where `+` and `-` are.

### GNOME

| Key | Action | Status | GNOME mechanism |
|---|---|---|---|
| SUPER + RETURN | Terminal | mapped | shortcut `kit-desk term` |
| SUPER + ALT + RETURN | Terminal with tmux | mapped | shortcut `kit-desk term --tmux` |
| SUPER + SHIFT + RETURN | Browser | mapped | shortcut `kit-desk browser` |
| SUPER + SHIFT + B | Browser | mapped | shortcut `kit-desk browser` |
| SUPER + SHIFT + ALT + B | Browser (private) | mapped | shortcut `kit-desk browser --private` |
| SUPER + SHIFT + F | File manager | mapped | shortcut `kit-desk files` (Files, Dolphin, else the default handler; a notification when none exists) |
| SUPER + SHIFT + N | Editor (nvim) | mapped | shortcut `kit-desk editor` |
| SUPER + CTRL + T | Activity (btop) | mapped | shortcut `kit-desk term -e btop` |
| SUPER + K | Show keybindings | mapped | shortcut `kit-desk keys --window` |
| SUPER + SHIFT + CTRL + SPACE | Theme menu | mapped | shortcut `kit-desk term -e kit-desk theme` |
| SUPER + ESCAPE | System menu: lock, log out, power off | mapped | shortcut `kit-desk power` |
| SUPER + SPACE | Launcher: type to search apps, Enter opens | mapped | GNOME `toggle-overview` (overview without dash and thumbnails; `Super+S` kept) |
| SUPER + ALT + SPACE | Kit menu: settings, keys, theme, system | mapped | shortcut `kit-desk menu` |
| SUPER + A | App grid (GNOME key, kept) | GNOME default | toggle-application-view |
| SUPER | Overview: windows, workspaces, search | off (Omarchy: nothing) | mutter `overlay-key` empty; listed only with `--skip superkey` |
| ALT + F2 | Run a command | GNOME default | panel-run-dialog |
| SUPER + CTRL + L | Lock screen | mapped | GNOME `screensaver` |
| CTRL + ALT + DELETE | Log out dialog | GNOME default | logout |
| SUPER + W | Close window (Alt+F4 also closes) | mapped | GNOME `close` |
| SUPER + H | Hide window (back with Alt+Tab) | GNOME default | minimize |
| SUPER + F | Full screen | mapped | GNOME `toggle-fullscreen` |
| SUPER + ALT + F | Full width (maximize) | mapped | GNOME `toggle-maximized` |
| SUPER + O | Pop window out (keep on top) | mapped | GNOME `toggle-above` |
| SUPER + T | Float window (kit tiler: again tiles it; Tiling Shell: Super+Shift+arrow tiles it again) | mapped | kit tiler / Tiling Shell `untile-window` (PaperWM: `toggle-scratch`) |
| SUPER + LEFT | Focus left | mapped | kit tiler / Tiling Shell `focus-window-left` |
| SUPER + RIGHT | Focus right | mapped | Tiling Shell `focus-window-right` |
| SUPER + UP | Focus up | mapped | Tiling Shell `focus-window-up` |
| SUPER + DOWN | Focus down | mapped | Tiling Shell `focus-window-down` |
| SUPER + SHIFT + LEFT | Swap window left | mapped | kit tiler / Tiling Shell `move-window-left` |
| SUPER + SHIFT + RIGHT | Swap window right | mapped | Tiling Shell `move-window-right` |
| SUPER + SHIFT + UP | Swap window up | mapped | Tiling Shell `move-window-up` |
| SUPER + SHIFT + DOWN | Swap window down | mapped | Tiling Shell `move-window-down` |
| SUPER + L | Next tiling layout (kit tiler: main left / main on top) | mapped | kit tiler / Tiling Shell `cycle-layouts` |
| SUPER + CTRL + F | Monocle (kit tiler) / window spans all tiles (Tiling Shell) | mapped | kit tiler / Tiling Shell `span-window-all-tiles` |
| SUPER + N | Switch to workspace N | mapped | GNOME `switch-to-workspace-N` |
| SUPER + SHIFT + N | Move window to workspace N | mapped | GNOME `move-to-workspace-N` |
| SUPER + SHIFT + ALT + N | Move window silently to workspace N | unmapped | GNOME always follows the window |
| SUPER + TAB | Next workspace | mapped | GNOME `switch-to-workspace-right` |
| SUPER + SHIFT + TAB | Previous workspace | mapped | GNOME `switch-to-workspace-left` |
| SUPER + CTRL + TAB | Former workspace | unmapped | GNOME has no back-and-forth binding |
| ALT + TAB | Next window | mapped | GNOME `switch-windows` |
| ALT + SHIFT + TAB | Previous window | mapped | GNOME `switch-windows-backward` |
| SUPER + ALT + TAB | Next window in group | mapped | GNOME `switch-group` |
| SUPER + ALT + SHIFT + TAB | Previous window in group | mapped | GNOME `switch-group-backward` |
| SUPER + mouse drag | Move / resize window (left / right button) | GNOME default | mouse-button-modifier <Super>, resize-with-right-button true |
| PRINT | Screenshot (area, window, screen) | GNOME default | show-screenshot-ui |
| SHIFT + PRINT | Screenshot of the whole screen | GNOME default | screenshot |
| ALT + PRINT | Screen recording | mapped | GNOME `show-screen-recording-ui` |
| XF86 media keys | Volume, brightness, media | GNOME default | media keys work as before |
| SUPER + S | Quick settings (sound, network, power, dark mode) | GNOME default | toggle-quick-settings |
| SUPER + P | Display mode (mirror, extend) | GNOME default | switch-monitor |
| SUPER + SHIFT + ALT + LEFT | Move window to the monitor on the left | mapped | GNOME `move-to-monitor-left` |
| SUPER + SHIFT + ALT + RIGHT | Move window to the monitor on the right | mapped | GNOME `move-to-monitor-right` |
| SUPER + SHIFT + ALT + UP | Move window to the monitor above | mapped | GNOME `move-to-monitor-up` |
| SUPER + SHIFT + ALT + DOWN | Move window to the monitor below | mapped | GNOME `move-to-monitor-down` |
| SUPER + J | Toggle split direction | unmapped | Tiling Shell has fixed layouts; Super+L switches to the next one |
| SUPER + P (Omarchy) | Pseudo tile | unmapped | no GNOME equivalent (Super+P stays display mode) |
| SUPER + MINUS / PLUS | Main area narrower / wider | mapped (kit tiler) | kit tiler `shrink-main` / `grow-main` (`<Super>minus` / `<Super>plus`: US `=` key, German `+` key); Tiling Shell resizes with the mouse only |
| SUPER + G | Window grouping (tabs) | unmapped | no GNOME equivalent |
| SUPER + S (Omarchy) | Scratchpad | unmapped | GNOME keeps Super+S for quick settings |
| SUPER + SHIFT + ALT + arrows (Omarchy) | Move workspace to monitor | unmapped | on GNOME these keys move the window to that monitor |
| CTRL + ALT + TAB | Focus next monitor | unmapped | no GNOME equivalent |
| SUPER + C / V / X | Universal copy / paste / cut | unmapped | needs key injection; use Ctrl+C/V/X (Ctrl+Shift+C/V in terminals) |
| SUPER + CTRL + V | Clipboard history | mapped | Clipboard Indicator `toggle-menu` |
| SUPER + COMMA | Notifications (Super+V too) | mapped | GNOME `toggle-message-tray` |
| SUPER + CTRL + E | Emoji picker (then paste with Ctrl+V) | mapped | shortcut `kit-desk emoji` |
| SUPER + SHIFT + SPACE | Toggle top bar | unmapped | not shipped |
| SUPER + BACKSPACE | Toggle transparency | unmapped | no GNOME equivalent |
| SUPER + CTRL + SPACE | Background switcher | unmapped | kit-desk theme sets a solid background |
| SUPER + CTRL + A | Sound settings | mapped | shortcut `kit-desk settings sound` |
| SUPER + CTRL + B | Bluetooth settings | mapped | shortcut `kit-desk settings bluetooth` |
| SUPER + CTRL + W | Network settings | mapped | shortcut `kit-desk settings network` |
| SUPER + CTRL + D | Display settings | mapped | shortcut `kit-desk settings display` |
| SUPER + CTRL + P | Power settings | mapped | shortcut `kit-desk settings power` |
| SUPER + CTRL + S | All settings | mapped | shortcut `kit-desk settings` |
| SUPER + SHIFT + (A C E G M O P S W X Y D SLASH) | Web apps and preinstalled apps | unmapped | Omarchy apps and private services are not part of the kit |


### PaperWM and Tactile (GNOME, `--tiler paperwm|tactile`)

PaperWM grabs many keys by default (`Super+Return` new window, `Super+Escape`, `Super+T`,
`Super+Comma`, `Super+F`, `Super+Shift+F`, `Super+Ctrl+B`, `Super+Tab`, ...) and at start empties
every GNOME keybinding that shares an accelerator with one of its own (restored when it stops;
custom shortcuts are not checked, so both grab and PaperWM wins). In the GNOME 50 VM `Super+Return`
opened nothing. `install.sh` therefore writes PaperWM's keys before its first start:

| Key | PaperWM action |
|---|---|
| SUPER + T | `toggle-scratch` (float the window; again to tile it) |
| SUPER + F / SUPER + ALT + F | `paper-toggle-fullscreen` / `toggle-maximize-width` |
| SUPER + SHIFT + arrows | `move-left/right/up/down` (the column moves) |
| SUPER + SHIFT + ALT + arrows | `move-monitor-*` (GNOME's move-to-monitor does not move a PaperWM window) |
| SUPER + MINUS / PLUS | `resize-w-dec` / `resize-w-inc` (`<Super>plus`: US `=` key, German `+` key) |
| (none) | `drift-left` / `drift-right` cleared: `<Super>bracketleft/right` are Super+8 / Super+9 on German QWERTZ |
| SUPER + CTRL + TAB | `previous-workspace` (PaperWM's most recent space) |
| SUPER + CTRL + ESCAPE | `toggle-scratch-window` (show or hide floating windows) |
| SUPER + arrows, SUPER + R, SUPER + I / SHIFT + O | PaperWM defaults: focus, cycle width, slurp / barf |

Cleared (they took a kit key or disabled a GNOME key the kit uses): `new-window`, `live-alt-tab(-backward)`,
`switch-up/down-workspace`, `toggle-top-and-position-bar`, `switch-monitor-*`, `move-space-monitor-*`,
`swap-monitor-*`, `toggle-scratch-layer`, `take-window`, `switch-previous`, `barf-out`,
`center-vertically`. PaperWM keeps a workspace per monitor (it sets `workspaces-only-on-primary`
false while it runs) and paints its own per-workspace background. `Super+L` (layouts) and
`Super+Ctrl+F` have no PaperWM counterpart; `kit-desk keys` says so.

Tactile places a window only on demand: `Super+T`, then two grid keys (`q`..`m`, 4x3 grid). Tiling
Shell's rows of the table (focus, swap, layouts) do not apply. Ubuntu's Tiling Assistant stays
enabled with Tactile, so `Super+Left/Right` tile to half screen and `Super+Up/Down` maximize and
restore, as on stock Ubuntu. (Disabling it and writing GNOME's own keys back instead failed with the
Wayland login deferral: the assistant, still running at that login step, emptied the keys again.)
`kit-desk keys` shows the Tactile meaning of these keys.

### KDE Plasma

| Key | Action | Status | Plasma mechanism |
|---|---|---|---|
| SUPER + RETURN | Terminal | mapped | launcher `kit-desk term` |
| SUPER + ALT + RETURN | Terminal with tmux | mapped | launcher `kit-desk term --tmux` |
| SUPER + SHIFT + RETURN | Browser | mapped | launcher `kit-desk browser` |
| SUPER + SHIFT + B | Browser | mapped | launcher `kit-desk browser` |
| SUPER + SHIFT + ALT + B | Browser (private) | mapped | launcher `kit-desk browser --private` |
| SUPER + SHIFT + F | File manager | mapped | launcher `kit-desk files` |
| SUPER + SHIFT + N | Editor (nvim) | mapped | launcher `kit-desk editor` |
| SUPER + CTRL + T | Activity (btop) | mapped | launcher `kit-desk term -e btop` |
| SUPER + K | Show keybindings | mapped | launcher `kit-desk keys --window` |
| SUPER + SHIFT + CTRL + SPACE | Theme menu | mapped | launcher `kit-desk term -e kit-desk theme` |
| SUPER + ESCAPE | System menu: lock, log out, power off | mapped | launcher `kit-desk power` |
| SUPER + ALT + SPACE | Kit menu: settings, keys, theme, system | mapped | launcher `kit-desk menu` |
| SUPER + SPACE | Launcher (KRunner: apps and files) | mapped | `org.kde.krunner.desktop` launch key |
| SUPER | Application menu | Plasma default | Meta alone opens the launcher menu |
| ALT + F2 | Run a command (KRunner) | Plasma default | KRunner default key |
| SUPER + CTRL + L | Lock screen | mapped | ksmserver `Lock Session` |
| CTRL + ALT + DELETE | Log out dialog | Plasma default | ksmserver Log Out |
| SUPER + W | Close window (Alt+F4 too) | mapped | KWin `Window Close` |
| SUPER + F | Full screen | mapped | KWin `Window Fullscreen` |
| SUPER + ALT + F | Maximize | mapped | KWin `Window Maximize` |
| SUPER + O | Keep above other windows | mapped | KWin `Window Above Other Windows` |
| SUPER + T | Toggle floating | mapped | Krohnkite `Krohnkite: Float` / `KrohnkiteToggleFloat` |
| SUPER + LEFT | Focus left | mapped | Krohnkite `Krohnkite: Left` / `KrohnkiteFocusLeft` |
| SUPER + RIGHT | Focus right | mapped | Krohnkite `Krohnkite: Right` / `KrohnkiteFocusRight` |
| SUPER + UP | Focus up | mapped | Krohnkite `Krohnkite: Up/Prev` / `KrohnkiteFocusUp` |
| SUPER + DOWN | Focus down | mapped | Krohnkite `Krohnkite: Down/Next` / `KrohnkiteFocusDown` |
| SUPER + SHIFT + LEFT | Swap window left | mapped | Krohnkite `Krohnkite: Move Left` / `KrohnkiteShiftLeft` |
| SUPER + SHIFT + RIGHT | Swap window right | mapped | Krohnkite `Krohnkite: Move Right` / `KrohnkiteShiftRight` |
| SUPER + SHIFT + UP | Swap window up | mapped | Krohnkite `Krohnkite: Move Up/Prev` / `KrohnkiteShiftUp` |
| SUPER + SHIFT + DOWN | Swap window down | mapped | Krohnkite `Krohnkite: Move Down/Next` / `KrohnkiteShiftDown` |
| SUPER + L | Next tiling layout | mapped | Krohnkite `Krohnkite: Next Layout` / `KrohnkiteNextLayout` |
| SUPER + J | Rotate layout (split direction) | mapped | Krohnkite `Krohnkite: Rotate` / `KrohnkiteRotate` |
| SUPER + CTRL + F | Monocle: one window fills the screen | mapped | Krohnkite `Krohnkite: Monocle Layout` / `KrohnkiteMonocleLayout` |
| SUPER + MINUS | Narrower window | mapped | Krohnkite `Krohnkite: Shrink Width` / `KrohnkiteShrinkWidth` |
| SUPER + PLUS | Wider window | mapped | Krohnkite `Krohnkite: Grow Width` / `KrohnkitegrowWidth` (US `Meta+=`, German `Meta++`) |
| SUPER + SHIFT + MINUS | Lower window | mapped | Krohnkite `Krohnkite: Shrink Height` / `KrohnkiteShrinkHeight` (`Meta+_`) |
| SUPER + SHIFT + PLUS | Taller window | mapped | Krohnkite `Krohnkite: Grow Height` / `KrohnkiteGrowHeight` (US `Meta++`, German `Meta+*`) |
| SUPER + N | Switch to workspace N | mapped | KWin `Switch to Desktop N` |
| SUPER + SHIFT + N | Move window to workspace N (you stay) | mapped | KWin `Window to Desktop N` |
| SUPER + TAB | Next workspace | mapped | KWin `Switch to Next Desktop` |
| SUPER + SHIFT + TAB | Previous workspace | mapped | KWin `Switch to Previous Desktop` |
| ALT + TAB | Next window | Plasma default | Walk Through Windows |
| SUPER + mouse drag | Move / resize window (left / right button) | Plasma default | KWin default |
| SUPER + SHIFT + ALT + LEFT | Move window to the previous monitor | mapped | KWin `Window to Previous Screen` |
| SUPER + SHIFT + ALT + RIGHT | Move window to the next monitor | mapped | KWin `Window to Next Screen` |
| PRINT | Screenshot (Spectacle) | Plasma default | Spectacle default keys |
| XF86 media keys | Volume, brightness, media | Plasma default | media keys work as before |
| SUPER + CTRL + V | Clipboard history (Super+V too) | mapped | plasmashell `show-on-mouse-pos` |
| SUPER + CTRL + E | Emoji picker (Super+. too) | mapped | `org.kde.plasma.emojier.desktop` launch key |
| SUPER + CTRL + SPACE | Next keyboard layout | mapped | keyboard layout switcher `Switch to Next Keyboard Layout` |
| SUPER + CTRL + A | Sound settings | mapped | launcher `kit-desk settings sound` |
| SUPER + CTRL + B | Bluetooth settings | mapped | launcher `kit-desk settings bluetooth` |
| SUPER + CTRL + W | Network settings | mapped | launcher `kit-desk settings network` |
| SUPER + CTRL + D | Display settings | mapped | launcher `kit-desk settings display` |
| SUPER + CTRL + P | Power settings | mapped | launcher `kit-desk settings power` |
| SUPER + CTRL + S | All settings | mapped | launcher `kit-desk settings` |
| SUPER + SHIFT + ALT + N | Move window silently to workspace N | Plasma default | KWin never follows: same as Super+Shift+N |
| SUPER + CTRL + TAB | Former workspace | unmapped | no KWin back-and-forth binding |
| SUPER + COMMA | Notifications | unmapped | no Plasma key; click the bell in the panel |
| SUPER + P | Pseudo tile | unmapped | no KWin equivalent (Super+P stays display mode) |
| SUPER + G | Window grouping (tabs) | unmapped | no KWin equivalent |
| SUPER + S | Scratchpad | unmapped | no KWin equivalent |
| SUPER + C / V / X | Universal copy / paste / cut | unmapped | use Ctrl+C/V/X (Ctrl+Shift+C/V in terminals) |
| SUPER + SHIFT + SPACE | Toggle top bar | unmapped | the panel hides itself (auto-hide) |
| SUPER + BACKSPACE | Toggle transparency | unmapped | no KWin equivalent |
| SUPER + CTRL + SPACE (Omarchy) | Background switcher | unmapped | Super+Ctrl+Space switches the keyboard layout |
| SUPER + SHIFT + (A C E G M O P S W X Y D SLASH) | Web apps and preinstalled apps | unmapped | Omarchy apps and private services are not part of the kit |

## IT policy handling

- `install.sh --check` prints the report without changing anything.
- A key is written only if `gsettings writable` does not report it as locked; a failed write
  (lock through a dconf system database, missing schema) is reported and skipped.
- Extensions are skipped, with a report line, when `allow-extension-installation` is `false`,
  when `disable-user-extensions` is `true` and locked, or when `enabled-extensions` is locked.
  Keybindings and settings are still applied; Super+arrows then keep GNOME's own tiling, and the
  dock is not disabled (verified in the VM with a real dconf lock).
- An extension that is already installed by the user or by IT is never replaced.
- Another flavour's desktop (Xfce, LXQt, MATE, Budgie, Cinnamon, ...): the module is skipped and
  changes nothing (see "Desktop detection"). No desktop at all (server, SSH session on a machine
  without GNOME or Plasma): desktop parts are skipped; fonts, terminal, TUIs, Neovim and terminal
  themes still install.
- Without the `dconf` CLI the module falls back to `gsettings` (no full dump, the journal still
  allows `uninstall.sh`).
- `dconf` writes need the session bus: run the installer from a terminal inside the session.

## Verification

### Build Mac (2026-09-25)

- `bash tests/test-install.sh`: 111 checks pass (stub `dconf`/`gsettings`/`gnome-shell` and stub
  `kreadconfig5/6`, `kwriteconfig5/6`, `kpackagetool5/6`, `plasmashell`; fake artifacts): GNOME keys,
  custom shortcuts next to an existing one, zero gaps, layouts, clipboard settings, welcome entry,
  extension selection for GNOME 46, 48, 50 and 51, IT locks, rerun idempotent, theme switch,
  uninstall restores the stub dconf database exactly, dry run changes nothing, other-desktop path;
  KDE Plasma 5 and 6: Krohnkite, zero gaps, launchers, login hook, keys untouched until login,
  `kit-desk kde-keys` writes the right values (Plasma 5 and 6 names, shifted digits, no split names),
  uninstall plus restore script bring the KDE files back exactly.
- After VM test 2 (below): 163 checks, adding the key conflicts found there, PaperWM's key map and
  its overrides handed back by the login script, Tactile keeping Tiling Assistant, the Ghostty
  exit-0 fallback, re-install after a kit update without `.bak` copies, Krohnkite without
  kpackagetool, Meta+Tab on Plasma 6, `picture-uri` pointing to an existing file, and main's login
  deferral (section W).
- Follow-up (help, backups): 169 checks; help acts on nothing (section H), user files in the way
  are backed up below the kit data dir with `.origin` and put back by `uninstall.sh`.
- `shellcheck` (shellcheck-py) on all scripts and stubs: clean.
- `fetch.sh` with the new pins (Clipboard Indicator, Krohnkite 0.8.1 and 0.9.9.2) and
  `fetch.sh --check-meta`: ok.

### VM test 1 (2026-09-25, X11)

Setup: Lima 2.2.0, own instance `kit-desktop-test` (vmType vz, arm64, 2 CPUs, 4 GiB, 20 GiB),
Ubuntu 24.04.4 with `ubuntu-desktop-minimal` (GNOME Shell 46), later `kde-plasma-desktop`
(Plasma 5.27.12) in the same VM, network on for apt only. Deleted after the test.

How: vz offers no VNC and its native display would open a window on the host, so the sessions ran
headless on `Xvfb :1` (1600x900): `gnome-session --session=ubuntu` (X11, Ubuntu mode) and
`startplasma-x11`, both real sessions with gnome-shell/gsd-media-keys or kwin_x11/plasmashell/
kglobalaccel5. "Log out and in" = end the session and start a new one. The module was installed from
the kit folder with `KIT_OFFLINE` pointing at the fetched artifacts and
`--skip terminal,tuis,nvim` (those binaries are x86_64). Keys were sent with `xdotool key`,
window state read with `wmctrl -lG`/`xprop`, screenshots taken with `import -window root` and
looked at.

GNOME 46 results:
- Install: 4 extensions ACTIVE after the new login; dock and desktop icons gone; top bar shows
  workspaces 1-6; the welcome notification and the key table appeared.
- Worked: Super+Return (GNOME Terminal fallback), autotiling with zero gaps, Super+arrows focus,
  Super+Shift+Left swap, Super+2 / Super+Shift+3, Super+F, Super+Alt+F,
  Super+T, Super+O (`_NET_WM_STATE_ABOVE`), Super+W, Super+Space with typing, Super overview,
  Alt+F2, Super+K, Super+Escape and Super+Alt+Space menus (zenity), Super+Ctrl+V with two copied
  entries, Super+Comma notification list, Super+Ctrl+E (IBus emoji window), Super+Ctrl+A (Sound
  settings), Print (screenshot UI), Alt+Print (recording UI), Super+S, Super+Shift+F (Files),
  Super+Shift+Ctrl+Space theme menu (tokyo-night applied: background and border colour changed),
  Super+Ctrl+Space layout switch between German and US. Super+L (next layout) is bound; its
  effect on the next windows was not checked.
- IT policy: with `disable-user-extensions=true` locked in `/etc/dconf/db/local.d`, `--check` and
  the install report it, no extension is installed, the dock stays, Super+Space works.
- Uninstall, new login: dock, desktop icons and Ubuntu's tiling assistant back; `dconf dump /`
  equals the dump before the install except two apport notification keys the VM wrote itself.
- Fixed from this run: Tiling Shell's 22 % default layout (own layouts), Tiling Shell's stored
  defaults mistaken for user layouts, extension settings left after uninstall, Tiling Shell
  restoring kit values when disabled, key table lines too long for an 80-column terminal, Konsole
  preferred over GNOME Terminal on GNOME when both are installed.
- Test artefact, not a module issue: on Xvfb, mutter delivers a window's first frame only after
  input, so Tiling Shell (which tiles on "first-frame") placed windows late; the test clicked each
  new window. Lock screen needs GDM, so `Super+Ctrl+L` was checked in dconf only.

KDE Plasma 5.27 results:
- Install and new login: Krohnkite active, three Konsole windows tile 800x900 + 2x 800x450 with no
  gap; Super+Left focus, Super+Shift+Right swap, Super+Shift+2 (after the fix), Super+T float,
  Super+F, Super+W, Super+1/2, Super+Space KRunner, Super+K, Super+Escape and
  Super+Alt+Space menus, Super+Ctrl+V Klipper, Super+Ctrl+E emoji picker, Super+Shift+F Dolphin;
  colour scheme BreezeDark; 6 desktops. Super+L (next layout) is bound, its effect not checked.
- Uninstall and new login: `kglobalshortcutsrc`, `kwinrc` and `kdeglobals` identical to the copies
  taken before the install; panel visible again; Krohnkite removed.
- Fixed from this run: shortcut daemon overwriting the file (login hook), comma in names,
  `Edit Tiles` stealing Super+T, `Super+Shift+N` symbols, Super+arrows resizing instead of focusing,
  conflicts the daemon resolved silently (now journaled), dark colours left after uninstall,
  `plasmashell --version` aborting without a display (now `QT_QPA_PLATFORM=offscreen`), a missing
  sound KCM (now falls back to System Settings).
- Other desktop: with `XDG_CURRENT_DESKTOP=XFCE` the install reports "no window manager changes"
  and installs only the terminal parts.

### VM test 2 (2026-09-25): GNOME 50, Plasma 6, Wayland, two monitors, x86_64 binaries, PaperWM, Tactile

Setup: Lima 2.2.0, own instances `kit-gap-gnome` (Ubuntu 26.04, GNOME Shell 50.1), `kit-gap-kde`
(Ubuntu 26.04 with Plasma 6.6.6 packages) and `kit-gap-gnome46` (Ubuntu 24.04.4, GNOME Shell 46.0),
each vmType vz, arm64, 4 CPUs, 6 GiB, Rosetta enabled (`vmOpts.vz.rosetta`, binfmt) plus
`libc6:amd64`, so the kit's x86_64 binaries run. One VM running at a time; all deleted afterwards.
Offline artifacts fetched with `fetch.sh` (sha256 ok) and mounted read-only; the module was
installed from the read-only kit folder with `KIT_OFFLINE` pointing there.

How the sessions ran (headless, no window on the host):
- GNOME: `gnome-shell --mode=ubuntu --headless --no-x11 --virtual-monitor 1280x800` twice (two
  monitors) under `dbus-run-session`, plus `gsd-media-keys` (custom shortcuts) and `gsd-keyboard`;
  the user's autostart entries were run after start ("login" = stop and start again). With Xwayland
  on demand, headless gnome-shell deadlocked in about half of the starts, so X11 was off (all tested
  apps are Wayland clients). Keys: `org.gnome.Mutter.RemoteDesktop` (real key events through mutter,
  including the gsd custom shortcuts). State: `org.gnome.Shell.Eval` and screenshots through
  `org.gnome.Shell.Screenshot`, enabled by a test-only extension that sets unsafe mode. Screenshots
  were looked at.
- Plasma 6: the real `startplasma-wayland` (runs `~/.config/plasma-workspace/env` hooks and autostart),
  with KWin (systemd unit override) nested in a headless sway: two KWin outputs = two sway outputs.
  Keys: a uinput keyboard (python-evdev) read by sway through libinput and seatd, so KWin gets real
  evdev keycodes (wtype's own keymap arrived as wrong keys; xdotool into Xwayland and KWin
  `--virtual` had no working input path). Window state through KWin scripts, screenshots with grim.

GNOME 50 (Wayland, Tiling Shell): 4 extensions ACTIVE after login, dock and desktop icons gone,
workspaces 1-6 in the top bar. Worked by key: Super+Return (Ghostty fallback to Ptyxis, see below),
autotiling main and stack with zero gaps (0,24 768x776 + 768,24/768,412 512x388 on 1280x800),
Super+arrows focus in all four directions, Super+Shift+arrows swap, Super+T float, Super+Shift+arrow
tiles it again, Super+Ctrl+F span, Super+F, Super+Alt+F, Super+O, Super+1..6, Super+Shift+3,
Super+Tab, Super+L (next layout in `selected-layouts`), Super+W, Super+Space, Super+Comma,
Super+Ctrl+V, Super+S, Super+K, Super+Escape and Super+Alt+Space (zenity), Super+Ctrl+A/D (Settings),
Super+Shift+F (Files), Super+Shift+N (nvim with the kit config: mini.starter, `Space f f`,
`Space Space`, `Space /`, `Space e`, `Space g g`, `H`/`L` mapped, colour scheme work-kit-everforest),
Super+Ctrl+T (btop), Super+Ctrl+E (IBus emoji), Super+Shift+Ctrl+Space (theme menu), Alt+F2, Print,
Alt+Print; `kit-desk theme tokyo-night` changed background, border, accent and terminal colours.
Two monitors: a new window on monitor 2 tiles there (1280,0 768x800 + two 512x400; no top bar on
the second monitor), Super+Shift+Alt+Right/Left move a window between monitors, focus keys work on
monitor 2; workspaces switch on the primary only (GNOME's `workspaces-only-on-primary`, not changed
by the kit). A window moved to the other monitor keeps its size and is not re-tiled (Tiling Shell).

GNOME 50 with PaperWM: columns without gaps (652 px wide each on 1280), Super+Left/Right focus,
Super+Shift+Left/Right move, Super+T float and back, Super+F, Super+Alt+F (full width), Super+O,
Super+-/= (width 512/640), Super+1..6, Super+Tab, Super+Shift+3, Super+Comma, Super+Space, Super+W,
Super+Shift+Alt+Right/Left (window to the other monitor's space), Super+Return. PaperWM keeps a
space per monitor and paints its own workspace background.

GNOME 50 with Tactile: Super+T q s = left half 0,24 640x776, Super+T w f = 320,24 960x776 (zero
gaps), Super+Up maximizes, Super+Left/Right half screen (Tiling Assistant), Super+W.

GNOME 46 on Wayland (Ubuntu 24.04, headless like GNOME 50, two monitors): main's login deferral
observed for real: the install reported "PENDING until the next login: 20 desktop change(s)", the
dock stayed, and at the next login `kit-desk finish-login` applied the 20 changes and removed its
autostart entry; the extensions ran. The GNOME 50 key run passed here too (Super+arrows, swap,
float, span, workspaces, move to monitor, Super+L, Super+W, Super+Space, Super+Comma,
Super+Ctrl+V, Super+S). GNOME Terminal (the 24.04 fallback) resizes in character cells, so it fills
a tile to within one cell (766x769 in a 768x776 tile); Ghostty and Ptyxis fill it exactly.

Plasma 6.6 (Wayland, two outputs): Krohnkite loaded (unpacked without kpackagetool6), 6 desktops,
panel auto-hidden, BreezeDark, no title bars on tiled windows, the welcome window after login.
Worked by key: Super+Return (Konsole; Ghostty marked broken), main and stack without gaps
(640x800 + 2x 640x400 on one output), Super+arrows focus, Super+Shift+Right swap, Super+F, Super+Alt+F,
Super+O, Super+T float and back, Super+L (monocle), Super+J (rotate), Super+-/=, Super+Ctrl+F,
Super+1/2, Super+Tab, Super+Shift+Tab, Super+Shift+3 (window moves, you stay),
Super+Shift+Alt+Left (window to the other output, tiled there), Super+W, Super+Space (KRunner),
Super+K, Super+Escape and Super+Alt+Space (kdialog), Super+Shift+F (Dolphin), Super+Shift+N (nvim),
Super+Ctrl+T (btop), Super+Alt+Return (tmux), Super+Ctrl+S and Super+Ctrl+A (System Settings, Sound
page after the fix), Super+Ctrl+E (emoji picker), Super+Ctrl+V (clipboard popup), theme switch.
Print (Spectacle) did not open a window headless; the key is Plasma's default and not changed.

x86_64 binaries under Rosetta: `lazygit --version` 0.65.1, `btop` 1.4.7 (ran in a terminal; too
narrow at 78 columns in a 640 px tile), `fastfetch` 2.68.1, `nvim` 0.12.5 (kit config loaded, keys
mapped), Ghostty 1.3.1 (`--version`, config and theme read; see below).

Uninstall: every cycle (install, login, use, uninstall, two logins) ended with `dconf dump /` equal to
the dump before the install, apart from app state (Ptyxis, Settings, Files window sizes): GNOME 50
with Tiling Shell, PaperWM and Tactile, GNOME 46 with Tiling Shell. Plasma 6 from a fresh profile:
`kglobalshortcutsrc` identical, Krohnkite and both login hooks gone, colours back; left are KWin's own
per-output tiling data, a recomputed `ColorSchemeHash` and `panelVisibility=0` (the default).

Found and fixed in this run (each with a stub test):
- GNOME: Ubuntu's `show-desktop` held Super+Ctrl+D (gsd-media-keys: "Failed to grab accelerator"),
  `move-to-workspace-left/right` held Super+Shift+Alt+Left/Right.
- Ghostty without OpenGL 4.3 exits with status 0 after about 1 s: `kit-desk term` did not fall back
  and Super+Return opened nothing. It now reads Ghostty's log. The AppImage is unpacked under
  `$HOME` instead of `/tmp` (noexec `/tmp` on company images).
- PaperWM took Super+Return, Super+Escape, Super+T, Super+Comma, Super+F, Super+Shift+F,
  Super+Ctrl+B, Super+Tab and emptied GNOME keys the kit uses; its keys are now written first.
- Tactile: the kit disabled Tiling Assistant, which left GNOME's half-tiling keys empty; it now stays.
- Uninstall inside the running session: extensions that stop write keys after the restore (PaperWM's
  saved keys, Just Perfection's `enable-animations`, Space Bar's styles, Tiling Assistant's record);
  the wait and the one-time login script settle them. A re-install after a kit update no longer
  leaves `.bak` copies of the module's own files.
- `kit-desk theme` wrote an empty `picture-uri` (GNOME 46: "Failed to load background
  'file:///home/...': Is a directory", reported from the owner's VM); now a solid SVG file.
- Plasma 6: `kpackagetool6` is missing on a minimal install (Krohnkite is unpacked directly),
  `kcmshell6` too (settings keys open the module through `systemsettings`), Meta+Tab on Walk Through
  Windows was lost after uninstall, `plasmashell --version` segfaults with `QT_QPA_PLATFORM=offscreen`
  (the version comes from `kwriteconfig6` then, as before).

Not verifiable in these VMs: Ghostty's window (Ghostty 1.3 needs OpenGL 4.3; the VMs have no GPU and
software GL under Rosetta never showed a frame), the lock screen, the browser key (the Firefox snap
refuses to start outside a real login: "not a snap cgroup"), Spectacle headless, a German keymap.

### VM test 3 (2026-09-25): the kit tiler on GNOME 46 and 50

Same headless harness as test 2, new VMs (Ubuntu 26.04 / GNOME Shell 50.1 and Ubuntu 24.04.4 /
GNOME Shell 46.0, two virtual monitors 1280x800 each, top bar 24 px on the primary), installed with
the Wayland login deferral as on a laptop. Frame rects of real windows (Ptyxis on 50, GNOME Terminal
on 46, opened with `Super+Return`) after each step:

| Step | GNOME 50 (Ptyxis) | GNOME 46 (GNOME Terminal) |
|---|---|---|
| 1 window | 0,24 1280x776 | 0,24 1278x769 |
| 2 windows | 0,24 640x776 + 640,24 640x776 | 638x769 each at x 0 / 640 |
| 3 windows | main 0,24 640x776, stack 640,24 / 640,412 640x388 | same, 638x769 / 638x373 |
| 4 windows | main + 3 stacked (Ptyxis has a minimum height of 294 px, so they overlap slightly) | main + 3 x 638x247 |
| Super+W | back to main + 2 | same |
| Super+Shift+Left (stack to main), Super+T float (768x543 centred) / again, Super+L (main on top: 1280x388 + two 640x388), Super+Ctrl+F (all 1280x776), Super+= twice (main 768) | as expected | as expected |
| Super+Shift+Alt+Right / Super+Shift+Left at the edge | window on monitor 2 fills 1280,0 1280x800; back on monitor 1 it tiles as main | same (1278x787) |
| two windows on monitor 2 | 1280,0 / 1920,0 640x800 each, monitor 1 refills | same |
| Super+Shift+2 | window to workspace 2, the rest refills | same |
| close all but one | 0,24 1280x776 | 0,24 1278x769 |

Uninstall cycles (install, login, use, uninstall, two logins): `dconf dump /` identical to the dump
before the install on GNOME 50 and GNOME 46.

Found and fixed during this test (stub tests added where the logic is in the shell scripts):
- mutter's auto-maximize maximized the lone first window (`auto-maximize` off while a tiler runs;
  the tiler also undoes a maximize in a window's first 2 s);
- on GNOME 50 the Ubuntu Dock and Tiling Assistant, disabled at the login step, ended in state ERROR
  and kept their strip (work area from x = 67) and their Super+arrow grabs until the next login
  (`dock-fixed` false, the assistant's own keys emptied);
- the Tiling Assistant put GNOME's Super+Left/Right/Up back when it stopped, after the queued
  writes (journal its saved originals, force the writes, `finish-login` writes again after the
  disabled extensions stopped);
- GNOME 46: move-to-monitor put a window back on the same monitor, a moved window was counted on
  two monitors in one pass, a move and resize never landed for GNOME Terminal (see "Kit tiler").

### VM test 4 (2026-09-26): GNOME 42, Plasma 5.27 Wayland, the other flavours, Ghostty without GPU

Own Lima VMs, one at a time, deleted afterwards (`kit-d2-gl`, `kit-d2-g42`, `kit-d2-kde`). The
module ran from the worktree (read-only mount) with `KIT_OFFLINE` on the fetched set (`fetch.sh`,
sha256 and `--check-meta` ok for all pins including the new GNOME 42 zips and `gl/` packages).

- **Ghostty without GPU** (`kit-d2-gl`: qemu x86_64 TCG, Ubuntu 22.04 cloud image plus Xvfb, weston,
  mesa-utils): see the table in "Ghostty without a GPU". The real `install.sh` unpacked the pack
  (201 MB), the first `kit-desk term` got OpenGL 3.3, restarted Ghostty with the pack (OpenGL 4.5,
  window with the shell prompt, screenshot), the second `kit-desk term` started with the pack at once.
- **GNOME 42** (`kit-d2-g42`: vz arm64, Rosetta, Ubuntu 22.04 + `ubuntu-desktop-minimal`, GNOME
  Shell 42.9). Wayland: headless `gnome-shell --headless` with two 1280x800 virtual monitors, keys
  through Mutter RemoteDesktop (real key events), a legacy-format test extension for unsafe mode.
  X11: `gnome-shell --x11` on Xvfb. Install report: `tiler: the kit tiler needs GNOME 45 or newer;
  GNOME 42 gets Forge`; on Wayland 18 changes waited for the login, `kit-desk finish-login` applied
  them and removed its autostart entry; Forge, Space Bar, Just Perfection and Clipboard Indicator
  ACTIVE, Ubuntu Dock and desktop icons off. Frame rects (GNOME Terminal, which rounds to its cells):

  | Step | Wayland | X11 |
  |---|---|---|
  | 1 window | 0,24 1278x769 | same |
  | 2 windows | 0,24 638x769 + 640,24 638x769 | same |
  | 3 windows | main 0,24 638x769, stack 640,24 / 640,412 638x373 | same |
  | `Super+J` on the stack | stack side by side: 640,24 / 960,24 318x769; again: back | 350 wide (GNOME Terminal's minimum) |
  | `Super+Left` | focus to the main window | same |
  | `Super+=` twice on main | main 654 wide, stack 622 | same |
  | `Super+Shift+Right` | main and stack window swapped | not run |
  | `Super+Ctrl+F` on the stack | tabbed: both stack windows 654,25 622x769 | not run |
  | `Super+T` | float (224,121 830x571, above), again: back into the tree | not run |
  | 4th window | splits the focused window (dwindle) | not run |
  | `Super+Shift+2`, `Super+W` | window to workspace 2, the rest refills; close refills | not run |

  Screenshot: no gaps, no dock, workspaces 1-6 in the top bar, Forge's 2 px focus border in its own
  red (Forge 68 takes the colour from its stylesheet, not from dconf, so the kit theme does not
  change it). `Super+Return`: Ghostty cannot run in this VM (below), so `kit-desk term` marked it
  broken and opened GNOME Terminal, the planned fallback. Install, login, use, uninstall, two logins:
  `dconf dump /` identical to the dump before the install, on Wayland and on X11.
- **Plasma 5.27** (`kit-d2-kde`: vz arm64, Ubuntu 24.04 + `kde-plasma-desktop`, KWin 5.27.11). X11:
  `startplasma-x11` on Xvfb, keys with xdotool (XTest): 1 window 0,0 1280x800, 2 = 640x800 each,
  3 = main 640x800 + 2 x 640x400, `Meta+Left` focus, `Meta+Shift+Right` swap, `Meta+T` float and
  back, `Meta+W` closes and the rest refills. Wayland: the real `startplasma-wayland` with KWin's
  virtual backend and without Xwayland (nested KWin 5.27 needs a DRM render node, Xwayland crashed
  on the virtual backend; both are VM limits); no input device, so the shortcuts were invoked
  through kglobalaccel (`invokeShortcut "Krohnkite: Left"` etc.), which checks the registered
  actions, not the physical keys. Here Krohnkite 0.8.1 tiled nothing until the guard above; with it:
  main + stack, focus, move, float as on X11. Uninstall cycles: on Wayland all six KDE files
  (`kwinrc`, `kglobalshortcutsrc`, `kcminputrc`, `kdeglobals`, `plasma-org.kde.plasma.desktop-appletsrc`,
  `plasmashellrc`) identical to before the install; on X11 (first login of a fresh profile) the
  known KDE rewrites remain: kglobalaccel writes `none` for two empty entries it had not yet
  normalised, a recomputed `ColorSchemeHash`, `panelVisibility=0` (the default) and `PreloadWeight`
  lines; two further plain logins changed nothing.
- **Other flavours** (in `kit-d2-g42`, next to Ubuntu's GNOME, `--no-install-recommends` session
  packages): real sessions on Xvfb of Xfce 4.16 (`startxfce4`, `XDG_CURRENT_DESKTOP=XFCE`), LXQt
  (`startlxqt`, `LXQt`), MATE (`mate-session`, `MATE`; the screen stayed black under Xvfb, the
  session process ran), Budgie (`budgie-desktop`, `Budgie:GNOME`) and Cinnamon
  (`cinnamon-session-cinnamon`, which sets `X-Cinnamon` itself). For each: `install.sh` inside the
  session (its environment) and from outside without `XDG_CURRENT_DESKTOP`/`DISPLAY` (SSH): exit 0,
  the skip message naming the flavour, the `KIT_MODULE_SKIPPED` line, the module check passes,
  `dconf dump /` unchanged and no file created or removed under `$HOME`. The patched installer
  (proposal) with the real module and `XDG_CURRENT_DESKTOP=XFCE`: `skipped, nothing changed: ...`,
  check report `95-desktop  skipped  desktop Xfce (Xubuntu) is not supported ...`, exit 0; today's
  installer: `installed  check ok`.
- Found and fixed in this run: Krohnkite 0.8.1 on Plasma 5.27 Wayland (above). Test-environment
  limits, not kit defects: the Ghostty AppImage's uruntime reads `/proc/self/exe`, which is Rosetta
  in the arm64 VMs, so it can neither unpack nor start there (on x86_64 `install.sh` unpacked it);
  KWin 5.27 nested needs `/dev/dri`.

### VM test 5 (2026-09-26): German keyboard layout, GNOME 46 and Plasma 6.6

Lima vz aarch64 VMs (4 CPUs, 6 GiB, 20 GiB), one at a time, deleted afterwards. Keys were sent as
physical key positions (evdev keycodes), so the active layout decided the symbol, as on a keyboard.

- GNOME Shell 46.0 (Ubuntu 24.04.4), headless session, `install.sh --tiler kit`, input sources
  `de`, `us`, switched in the running shell. Keys through Mutter RemoteDesktop
  `NotifyKeyboardKeycode` (`tests/vm-harness/desktop/gkc.py`, `kprobe.sh` in the share folder).
  German: the `+` key fired `grow-main`, the `-` key (right of `.`) `shrink-main`, Super+, the
  notifications, Super+2 workspace 2; Super+0, Super+Shift+0 and the dead-acute key fired nothing.
  US: the `=` key fired `grow-main`, `-` `shrink-main`. Counter test with the old `<Super>equal`:
  German Super+0 fired `grow-main` (the workspace-10 key), the `+` key nothing.
  `kit-desk keys` printed `SUPER + PLUS` and the German note. The headless session has no IBus, so
  gnome-shell never wrote `mru-sources` and the first configured source decided the names.
- Plasma 6.6.6 (Ubuntu 26.04), real `startplasma-wayland` nested in a headless sway, uinput keys
  (`kkd.py`), fired shortcuts read from kglobalaccel's `globalShortcutPressed` signal. Old keys:
  German Super+Shift+0 fired Grow Width (`Meta+=`); US Super+Shift+= fired Zoom In, not Grow Height;
  `Meta+Shift+=` and `Meta+Shift+-` never fired, `Meta+_` did on both layouts. After the change, a
  fresh install with `kxkbrc` `de,us`: the login hook wrote `Meta++`, `Meta+*`, `Meta+-`, `Meta+_`;
  the `+` key, Shift and `+`, the `-` key, Shift and `-` fired Grow Width, Grow Height, Shrink Width,
  Shrink Height; Super+Shift+0 fired nothing. `kxkbrc` switched to `us,de` and logged in again: the
  hook rewrote `Meta+=`, `Meta++`, `Meta+-`, `Meta+_`, all four fired with the US keys, and
  `kit-desk keys` named `SUPER + EQUAL`.

## Manual test checklist (x86_64 laptop or VM with a display, later)

Prepare: kit copied, network off. Log in to the desktop session, open a terminal.

1. `bash kit/modules/95-desktop/install.sh --check`: shows the desktop and version, no locks.
2. `bash install.sh --dry-run | tail`: lists changes; `dconf dump / | md5sum` before and after is equal.
3. `bash install.sh`: exit 0; report ends with "Log out and back in"; a backup exists. On Wayland
   the dock is still there and the report has a "PENDING until the next login" block;
   `kit-desk status` shows it too.
4. Log out and in: on Wayland the dock and desktop icons disappear a few seconds after the shell
   is up (`kit-desk status` no longer shows PENDING, `~/.config/autostart/work-kit-desktop-finish-login.desktop`
   is gone, `~/.local/share/work-kit/desktop/state/finish-login.log` ends with "done"). Still
   pending: run `kit-desk finish-login` in a terminal and read the log. The welcome window lists the keys. GNOME: `gnome-extensions list --enabled`
   shows kit-tiling, space-bar, just-perfection, clipboard-indicator. KDE: windows tile.
5. `Super+Return` opens Ghostty (theme colours, JetBrainsMono Nerd Font, no title bar, no padding).
   The first terminal fills the screen, the second splits it, the third makes main + stack; no gaps,
   a thin border around each window, the focused one in the accent colour. `Super` alone opens
   nothing; `Super+Space` opens the search, typing finds apps; a click on a workspace number in the
   top bar switches to it. `Super+K` in a half-width window wraps the texts at word boundaries.
   If Ghostty fails (no OpenGL 4.3), the next
   `Super+Return` opens the desktop terminal and `state/ghostty-broken` exists.
6. Every row of the "Everyday actions" table above.
7. `Super+Shift+N` opens nvim: `Space f f`, `Space e`, `Space g g` (lazygit); `Super+Ctrl+T` btop.
8. Two monitors: `Super+Shift+Alt+Right` moves the window; `Super+P` (GNOME) switches display mode.
9. Re-run `bash install.sh`: no new files in `~/.local/share/work-kit/backups/95-desktop/`, no
   `.bak-*` beside any file, no new journal lines.
10. `bash uninstall.sh`, log out and in: dock/panel back, old keys back, `dconf dump /` equals
    `backup/dconf-original.ini` except keys changed by hand in between.
11. Repeat on the other Ubuntu version (24.04 = GNOME 46 / Plasma 5, 26.04 = GNOME 50 / Plasma 6).

## Open points

- German layout: Plasma 5.27 and GNOME 42 / 50 not run in a VM for it (same mechanisms as Plasma 6
  and GNOME 46; the earlier Plasma 5 X11 run found the same symbol naming for Super+Shift+digit). Plasma writes
  the keys for one layout per login; with two layouts the second one's shifted keys are the first
  one's symbols until the next login after the order changes.

- The kit tiler is new (2026-09-25): tested in the VMs above with Ptyxis and GNOME Terminal, not yet
  on the laptop with Ghostty and a browser (pointer drags, swap and border resize were verified in VMs on
  GNOME 46 and 50).
- Test on the real x86_64 laptop (manual checklist above): Ghostty rendering (OpenGL 4.3 needed;
  older Intel GPUs fall back to Alacritty/Ptyxis/Konsole), the lock screen, the browser keys.
- Krohnkite 0.9.9.2's repository is archived (still the Plasma 6 build to use; Polonium is the
  maintained alternative if a per-output padding of 4 px is acceptable).
- Alacritty (and Ghostty from Ubuntu 26.04 universe) need 01-prereqs items for the sudo path;
  `apt.sh` prints the lines to add. Not needed for a terminal: Ghostty runs without a GPU through the
  kit's software OpenGL (measured 2026-09-26).
- Ghostty's software OpenGL is measured in an x86_64 VM without GPU (X11 and Wayland), not on a
  laptop whose GPU driver offers less than OpenGL 4.3; `kit-desk term` switches by the same log line
  there. The pack is tied to the AppImage's Mesa 26.0.1; a Ghostty update needs new `gl/` pins.
- `kit/install` shows a skipped 95-desktop as `installed  check ok` until the proposed installer
  change (`skipped` status for a `KIT_MODULE_SKIPPED:` line) is merged.
- GNOME 42 uses Forge, not the kit tiler: no monocle over the whole screen (tabbed container
  instead), no main/stack ratio key (right edge instead), no 2-monitor run with Forge beyond focus
  across monitors. Forge's focus border stays red (its stylesheet).
- Space Bar has no licence file (see `NOTICE.md`).
- KDE has no key for the notification list, and Plasma's own terminal/editor font is not changed.
- Omarchy bindings without a counterpart (tables above) stay unmapped: silent move (GNOME),
  grouping, universal clipboard, top-bar toggle, transparency; former workspace and scratchpad only
  with PaperWM.
- GNOME: workspaces switch on the primary monitor only (GNOME default); Tiling Shell does not
  re-tile a window moved to another monitor; btop needs 80 columns (a half or stack tile on a small
  screen is narrower: Super+F).
- With Tiling Shell (`--tiler tilingshell`) the zenity menus are tiled like normal windows and a
  fourth window floats until a tile is free; the kit tiler leaves dialogs alone and tiles every window.

## Install options and helper commands

```bash
bash install.sh --check                 # policy report only: desktop, version, locked keys, extensions
bash install.sh --dry-run               # show every change
bash install.sh                         # dconf backup first, then install
bash install.sh --tiler paperwm         # or kit / tilingshell / tactile / forge / none; --workspaces 10; --theme tokyo-night
bash install.sh --with zellij,zed       # optional extras
bash install.sh --skip input,wallpaper  # leave keyboard/touchpad and background alone
bash install.sh --desktop none          # no desktop changes: fonts, terminal, TUIs, nvim, themes (also on Xfce etc.)
bash install.sh --defer no              # Wayland: change the dock and keys at once (default: at next login)
bash install.sh --border 0              # windows touch, no border (default 2 px); --skip superkey: Super alone = overview
bash uninstall.sh                       # restore every changed setting, remove files
bash uninstall.sh --full-restore        # also load the full dconf dump from before the install
bash apt.sh                             # optional Alacritty via 01-prereqs --sudo
kit-desk power                          # Super+Escape: lock, log out, restart, power off
kit-desk finish-login                   # apply the changes that waited for the login (runs from autostart; safe by hand,
                                        # log: ~/.local/share/work-kit/desktop/state/finish-login.log)
```

On GNOME with Wayland the dock and tiling changes wait for the next login and apply themselves
(`kit-desk status` shows what is pending). Ghostty without a GPU uses the kit's software OpenGL.
Build host: `bash fetch.sh` fills `kit/offline/desktop` (pins in `pins.conf`), `bash fetch.sh --check-meta`.
Test: `bash tests/test-install.sh`.
