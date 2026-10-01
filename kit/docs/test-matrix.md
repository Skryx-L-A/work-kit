# Ubuntu test matrix

Results of the matrix in SPEC.md ("Ubuntu test matrix"). One row per release, flavour, session,
arch and scenario. Core kit rows (all modules except 95-desktop) come first, the 95-desktop section
follows. Evidence paths point to `tests/linux/results/` on the build Mac (gitignored; the runs are
reproducible with the command in the row).

## Method (core kit)

- Lima VMs from the official Ubuntu cloud images: `template:ubuntu-22.04` (22.04.5, glibc 2.35,
  Python 3.10) and `template:ubuntu-26.04` (26.04, glibc 2.43, Python 3.14); qemu, x86_64 (emulated
  on the Apple Silicon Mac), 4 CPU, 6 GiB, 30 GiB disk. The repository's `kit/` is mounted
  read-only at `/mnt/kit`.
- Runner: `tests/linux/run-e2e.sh <name>:<selection> --vm VM --source mount --minimal
  --desktop-libs --checks`
  - `core` = every module except 95-desktop and the orchestration group; `core,71` / `core,72` /
    `core,70` = the three orchestration variants.
  - `--minimal`: git, curl, tmux, build-essential, gcc, make and jq purged, `/usr/bin/python3`
    hidden, so 01-prereqs and the kit's own CPython are really used.
  - `--desktop-libs`: the GUI runtime every Ubuntu Desktop has (GTK 3, NSS, ALSA, GBM, libsecret,
    xdg-utils; `t64` names on 24.04+). The server cloud image lacks it; without it VS Code (72's
    `code --install-extension`) cannot start. First 26.04 run without it: 72 failed on
    `libatk-1.0.so.0`, everything else passed.
  - Network off (default route removed) after the kit is in place, for install and checks.
  - `--checks`: `tests/linux/smoke.sh`, `tests/cli-help-safety.sh` (own sandbox HOME, all
    modules again), and `kit/modules/70-workbench/verify.sh` when 70 is installed.
- `tests/glibc-floor.py` (build host, no VM): every ELF file in `kit/offline` (loose, and inside
  tar/zip/whl/vsix/deb, zstd included) must need at most glibc 2.35 / GLIBCXX_3.4.30.

## Results

Date 2026-09-25/26, arch x86_64 (qemu), flavour: Ubuntu server cloud image (no desktop; see
`--desktop-libs`), offline (network cut), minimal unless stated. "Install" = modules installed /
selected. Evidence: `tests/linux/results/<dir>/` (install.log, status.log, install-state.json,
smoke.log, cli-help-safety.log, verify-70.log).

| Release | Scenario | Install | smoke.sh | cli-help-safety | 70 verify.sh | Evidence dir |
|---|---|---|---|---|---|---|
| 26.04 | core + 71 | pass 23/23 | pass (0 fails) | invalid run: /tmp tmpfs full (fixed in runner) | n/a | `20260925-223024-kit-mx-2604-core71` |
| 26.04 | core + 72, no desktop libs | fail 22/23: 72 (`code` cannot load `libatk-1.0.so.0`, server image) | pass | - | n/a | `20260925-225545-kit-mx-2604-core72` |
| 26.04 | core + 72, `--desktop-libs` | pass 23/23 | pass (0 fails) | 169 ok, 23 known upstream, 2 upstream (ctags -h, semgrep cache; now known) | n/a | `20260925-234813-kit-mx-2604-core72` |
| 26.04 | core + 70, `--desktop-libs` | pass 24/24 (incl. deps) | pass (0 fails) | aborted (Mac disk floor; covered by the row above) | pass 24/24 | `20260926-003839-kit-mx-2604-core70` |
| 22.04 | core + 71 (kit before the 22.04 fixes; runner stopped after the checks by an in-place edit of the script, since fixed by private runner copies) | pass 23/23, with warnings: tree-sitter did not run, libgomp missing | 1 fail: tree-sitter (GLIBC_2.39) | 147 ok, 33 fail: upstream CLIs (now known list), GUI libs, quassel `--help` (fixed) | n/a | `20260925-223230-kit-mx-2204-core71` |
| 22.04 | fix check: 00, 11 tree-sitter, 15 `--no-models`, 80 | pass | tree-sitter 0.25.10 parses C/Python with the prebuilt parsers; llama-server loads the kit libgomp; `quasseld/-type/-pill --help` start nothing; jammy libxcb-cursor needs no GLIBC_2.38 | - | n/a | `20260926-fixcheck-kit-mx-2204` |
| 22.04 | 01-prereqs + 72, `--desktop-libs` | pass 2/2 (VS Code + extension) | - | - | n/a | `20260926-013426-kit-mx-2204-only72` |
| 22.04 | 00, 01, 10 + 70, `--desktop-libs` | pass 4/4 | - | - | pass 22/22 (python3 hidden, offline) | `20260926-014041-kit-mx-2204-only70` |
| 22.04 | 00, 01, 10 + 70, not minimal (system Python 3.10 runs kit/install and is WB_PYTHON) | pass 4/4 | - | - | pass 22/22 | `20260926-014604-kit-mx-2204-py310-70` |

Not run (Mac disk below the 12 GB floor, owner's main agent decided 2026-09-26): 22.04 full
core + 72 and core + 70 with smoke and cli-help-safety after the fixes (the heavy modules 15 and
80 are covered by the 22.04 core + 71 row and the fix check), and the stick path
(`stick/setup/install-kit.sh` copying 14 GB to `~/work/kit`; release-independent shell, covered
on 24.04 in the kit-human VM).

Other checks on 26.04: Codex's own bubblewrap sandbox works with
`kernel.apparmor_restrict_unprivileged_userns=1` (`codex sandbox -- /bin/echo` ok, writes to
`/etc` refused read-only). VS Code without sudo runs with `--no-sandbox` and chrome-headless-shell
with `--no-sandbox` (already in 01-prereqs / 90-design). `/tmp` is a tmpfs of half the RAM on the
26.04 image; every kit installer keeps large temporary data out of `/tmp` (all 23 modules
installed with 6 GiB RAM).

`tests/glibc-floor.py` on the offline set (2026-09-26): 959 ELF files, 0 too new, 2 allowed
(95-desktop's Zed libstdc++; Codex's optional zsh-fork `zsh` needs GLIBC_2.38, Codex itself is
musl-static and does not need it).

## Findings and fixes

| # | Release | Module | Finding | Fix | Commit |
|---|---|---|---|---|---|
| 1 | 22.04 | 01-prereqs | No package closure for jammy: `install.sh` dies "no packages for Ubuntu 'jammy'". | `RELEASES="jammy noble resolute"`, `lock/jammy.lock` (319 packages, 739 MB); `offline/prereqs` grows from 1.4 to 1.5 GB (pool shared). noble/resolute locks unchanged. | c2a3f22 |
| 2 | 22.04 | 80-quassel | Fallback `libxcb-cursor0` is the noble build and needs GLIBC_2.38: Qt pill cannot start on X11 on 22.04 without the system package. | `debs/jammy/libxcb-cursor0_0.1.1-4ubuntu1` in `fetch.lock`, unpacked over the noble set on jammy only. | c2a3f22 |
| 3 | 22.04 | 11-legacy-toolbox | tree-sitter CLI >= 0.26 needs GLIBC_2.39: "does not run here". | Fallback `bin/glibc-2.34/tree-sitter-linux-x64.gz` (v0.25.10) chosen when the current build does not run; parser check copes with the 0.25 output format. | a008b39, e7c8e09 |
| 4 | all (minimal) | 15-local-llm | `libgomp.so.1` missing on minimal images: llama-server does not start; hint named `libssl3t64` also on 22.04. | Kit copy of `libgomp1` (jammy build, glibc 2.35) placed next to the engine when the system lacks it (RUNPATH `$ORIGIN`); hint names both package spellings. | a008b39 |
| 5 | all | 80-quassel | `quasseld --help` starts the daemon; `quassel-type/-pill --help` crash. | Launchers answer `-h/--help` themselves. | eaa3cba |
| 6 | all | tests | cli-help-safety installed 18-doc-qa before 20-brain and timed out copying GGUF models, so 15/18 CLIs went untested. | Dependency order, 15 with `--no-models`. | 817202e, d2ddb28 |
| 7 | all | tests/linux | Runner: SIGPIPE race reported "no Lima instance"; an interrupted run left the VM without python3 and default route; `/tmp` tmpfs on 26.04 filled by the sandbox; verify-70 ran when 70 was only "not selected". | Fixed; `--desktop-libs`, `--vm/--template/--source/--checks`, `core` selection. | c2a3f22..d2ddb28 |
| 8 | all | tests | No check that bundled binaries run on the oldest release. | `tests/glibc-floor.py` (fails on the noble libxcb-cursor and the 0.27 tree-sitter without their fallbacks). | 47e197b, a008b39 |

Reported, not changed (upstream behaviour, same on every release): `git -h` exits 129, `tmux -h`,
`d2 -h`, `direnv -h`, `ctags -h` exit non-zero; `npm/npx/corepack`, `codex`, `gemini`, `pi`
(`pi --help` writes `~/.pi/agent/auth.json` and `models-store.json`), `pysemgrep` write caches on
`--help`. The e2e runner passes them as `CLI_SAFETY_KNOWN`.

95-desktop (owned by another worker): not part of this matrix; no findings from these runs.

## 24.04

Re-run 2026-09-26 (kit at 531319e, x86_64 qemu, Lima `template:ubuntu-24.04`, 4 CPU, 6 GiB, 50 GiB
disk instead of 30 GiB: the copy source needs the kit twice in the VM and 30 GiB is too small for
it, see finding 9), server cloud image, `--minimal --desktop-libs`, network off. Runner:
`tests/linux/run-e2e.sh <name>:<selection> --vm kit-t2404 --source <copy|mount> --minimal
--desktop-libs --checks`. Afterwards, as the same test user with the network still off:
`35-company-network/tests/test-net.sh` and `32-harness-profiles/tests/run-tests.sh` (python3
visible: the latter runs with `PATH=/usr/bin:/bin` and needs the system python3).

| Release | Scenario | Install | smoke.sh | cli-help-safety | 70 verify.sh | 35 test-net | 32 run-tests | Evidence dir |
|---|---|---|---|---|---|---|---|---|
| 24.04 | core + 71, `--source copy` | fail 23/24: 80-quassel (finding 10) | pass (0 fails, 53 ok) | 194 ok, 0 fail, 24 known (first run invalid: VM disk full, rerun after freeing space) | n/a | pass 143/0 | pass 17 ok, 0 fail (shellcheck skipped) | `20260926-161845-kit-t2404-core71` |
| 24.04 | core + 72, `--source mount`, `--desktop-libs` | fail 23/24: 80-quassel (finding 10); 72 installed | pass (0 fails, 51 ok) | 194 ok, 0 fail, 24 known | n/a | pass 143/0 | pass | `20260926-180034-kit-t2404-core72` |
| 24.04 | core + 70, `--source mount`, `--desktop-libs` | fail 23/24: 80-quassel (finding 10); 70 installed | pass (0 fails, 51 ok) | 194 ok, 0 fail, 24 known | pass 24/24 | pass 143/0 | pass | `20260926-184247-kit-t2404-core70` |

Findings of this run (reported, not fixed):

| # | Module | Finding |
|---|---|---|
| 9 | tests/linux | `--source copy` with a 30 GiB disk cannot work: `/opt/kit-e2e` (15 GB) + `~/kit-stick` (14 GB) + the installed modules (12 GB) + the cli-help-safety sandbox (5+ GB) exceed 48 GB; the sandbox died with "No space left on device" (the log shows only `sort: write error`). Needs `--disk 60`, or the runner should refuse. |
| 10 | 80-quassel | Install fails on 24.04 (all three scenarios) when `systemctl --user` has no bus (`sudo -iu USER` without a login session): `names.sh:68` `command -v systemctl ... && systemctl --user daemon-reload 2>/dev/null` is the last command of `quassel_legacy_remove` and fails under the `set -e` of `install.sh:6` (call at `install.sh:296`), so step 7 exits 1 before the final status. `tests/cli-help-safety.sh:165-170` counts a module that fails after installing its CLIs as installed, so its sandbox run does not show it. Introduced by a5afdfc (2026-09-25), after the last 24.04 run. |

## Current-kit re-test (2026-09-26/27)

Target: `f0d98ed` plus the isolated `70-workbench` Linux-check tmux cleanup (`6bd16fb`), x86_64/qemu, 4 CPU, 6 GiB RAM, 60 GiB disk, minimal image, desktop libraries and the runner's network cut. The offline set was an authorized APFS clone in this worktree. After the runner, the same fresh user ran 35 and 32 again with the default route removed.

| Release | Scenario | Install | smoke.sh | cli-help-safety | 70 verify.sh | 35 test-net | 32 run-tests | Evidence dir |
|---|---|---|---|---|---|---|---|---|
| 22.04 | core + 70, `--source copy` | pass 24/24 | pass (0 fails) | 193 pass, 0 fail, 25 known | fail: 24 pass, 1 fail | pass 143/0 | pass (shellcheck skipped) | `20260926-223623-kit-matrix2-2204-core70` |
| 26.04 | core + 70, `--source copy` | pass 24/24 | pass (0 fails) | 195 pass, 0 fail, 23 known | fail: 24 pass, 1 fail | pass 143/0 | pass (shellcheck skipped) | `20260926-235918-kit-matrix2-2604-core70` |

The sole failed check on both releases is the same installed-mode `70 verify.sh` assertion: `kit-guard and bash-guard both registered for Claude Bash`. It is reported, not fixed.

Runner/environment findings, also not fixed: `--source mount` is invalid because `/mnt/kit` is `0700 <host user>:dialout` in the guest and cannot be traversed by the fresh test user. On 26.04, `--source copy` initially fails because its 14 GiB archive is copied to the small tmpfs `/tmp`; for the successful isolated run only, `/tmp` was temporarily bind-mounted to a mode-1777 directory on the VM's 60 GiB root filesystem. Both test VMs were deleted after their runs.

## 95-desktop

Method: own Lima VMs on the build Mac, one at a time, deleted afterwards; the module from the
repository (read-only mount), the offline set from `fetch.sh` (sha256 checked). GNOME sessions
headless (`gnome-shell --headless` with virtual monitors for Wayland, `gnome-shell --x11` on Xvfb),
Plasma through `startplasma-x11` on Xvfb or `startplasma-wayland` (KWin virtual backend), the other
flavours as real sessions on Xvfb. Evidence: `docs/desktop.md`, sections "VM test 1" to "VM test 4"
(measured window rects, screenshots checked, `dconf dump /` or KDE config files compared before the
install and after uninstall plus two logins). The laptop checklist in `docs/desktop.md` is still open.

| Release | Flavour / desktop | Session | Arch | Date | Result | Evidence |
|---|---|---|---|---|---|---|
| 22.04 | Ubuntu, GNOME 42.9 | Wayland, 2 monitors | arm64 VM (Rosetta for x86_64 tools) | 2026-09-26 | pass: Forge instead of the kit tiler (reported), dock off after the login, tiling and keys, dconf identical after uninstall | VM test 4 |
| 22.04 | Ubuntu, GNOME 42.9 | X11 | arm64 VM | 2026-09-26 | pass: same as Wayland, applied at once | VM test 4 |
| 24.04 | Ubuntu, GNOME 46.0 | X11 | arm64 VM | 2026-09-25 | pass | VM test 1 |
| 24.04 | Ubuntu, GNOME 46.0 | Wayland, 2 monitors | arm64 VM | 2026-09-25 | pass (kit tiler, login deferral, dconf identical) | VM tests 2 and 3 |
| 26.04 | Ubuntu, GNOME 50.1 | Wayland, 2 monitors | arm64 VM | 2026-09-25 | pass (kit tiler, all tilers, dconf identical) | VM tests 2 and 3 |
| 24.04 | Kubuntu, Plasma 5.27.11 | X11 | arm64 VM | 2026-09-25, 2026-09-26 | pass (Krohnkite tiling, keys by XTest; uninstall leaves only KDE's own rewrites) | VM tests 1 and 4 |
| 24.04 | Kubuntu, Plasma 5.27.11 | Wayland | arm64 VM | 2026-09-26 | fail, fixed: Krohnkite 0.8.1 tiled no Wayland window; pass with the kit's guard (shortcuts invoked through kglobalaccel, no input device); KDE files identical after uninstall | VM test 4 |
| 26.04 | Kubuntu, Plasma 6.6 | Wayland, 2 outputs | arm64 VM | 2026-09-25 | pass | VM test 2 |
| 26.04 | Kubuntu, Plasma 6 | X11 | - | - | not run yet (was not part of the 2026-09-26 task) | - |
| 22.04 | Xubuntu, Xfce 4.16 | X11 | arm64 VM | 2026-09-26 | pass: skipped with message, nothing changed (in the session and over SSH) | VM test 4 |
| 22.04 | Lubuntu, LXQt | X11 | arm64 VM | 2026-09-26 | pass: skipped, nothing changed | VM test 4 |
| 22.04 | Ubuntu MATE, MATE | X11 | arm64 VM | 2026-09-26 | pass: skipped, nothing changed (screen black under Xvfb, session ran) | VM test 4 |
| 22.04 | Ubuntu Budgie, Budgie (`Budgie:GNOME`) | X11 | arm64 VM | 2026-09-26 | pass: skipped, nothing changed | VM test 4 |
| 22.04 | Ubuntu Cinnamon, Cinnamon (`X-Cinnamon`) | X11 | arm64 VM | 2026-09-26 | pass: skipped, nothing changed | VM test 4 |
| 22.04 | no GPU: Ghostty with the kit's software OpenGL | X11 (Xvfb) and Wayland (weston) | x86_64 VM (qemu) | 2026-09-26 | pass: OpenGL 3.3 without, 4.5 with the pack; `kit-desk term` switches by itself | VM test 4, "Ghostty without a GPU" |
| any | laptop with GPU (Ghostty rendering, lock screen, browser keys, German keymap) | - | x86_64 | - | open | manual checklist |

Not run as their own release: the flavours on 24.04 and 26.04. The skip depends only on the session
variable and the session process, which the same flavours set on every release. Stub tests
(`kit/modules/95-desktop/tests/test-install.sh`, sections U, F42, GL, K5w) cover the same logic
on every run.
