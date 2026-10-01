# Base prerequisites (01-prereqs)

Design notes and audit for `kit/modules/01-prereqs`. Status: 2026-09-25. The module README has the
commands; this file explains the method, the assumptions of every other module, and the fixes that
other modules still need.

## What the module ships

| Item | Default | No-sudo path | Sudo path |
|---|---|---|---|
| vscode | yes | official portable tar.gz in `~/.local/share/work-kit/vscode`, `code` wrapper, menu entry | official `code` .deb from the offline repo |
| git | yes | unpacked .debs + wrapper (`GIT_EXEC_PATH`, templates, Perl modules) | apt |
| tmux | yes | unpacked .debs, wrapper passes the library path to the loader only | apt |
| curl | yes | unpacked .debs + wrapper | apt |
| python3 | yes | standalone CPython 3.12 from `kit/offline/python` (venv and pip included) | apt `python3 python3-venv` |
| whiptail | yes | unpacked .debs + wrapper | apt |
| ssh (openssh-client) | yes | unpacked .debs + wrappers (skipped when `ssh-keygen` exists; `setup/git-setup.sh` on the stick needs it) | apt |
| jq, sqlite3, zip/unzip, rsync, clipboard (xclip, wl-clipboard), audio (pulseaudio-utils, pipewire-bin), lsof, graphviz, make, shellcheck | no | unpacked .debs + wrappers | apt |
| node | no | official Node.js 24 LTS tar.xz, wrappers for node/npm/npx/corepack | same user-level install (Ubuntu's nodejs is older than the harness CLIs need) |
| build-essential | no | experimental: unpacked toolchain plus a private sysroot, `gcc --sysroot` wrappers | apt |
| chrome, edge | no | none (the browser sandbox needs root-owned files) | vendor .deb from the offline repo |
| zsh | no | none (the only user, the 70-workbench extension, calls `/bin/zsh`) | apt |

The no-sudo path only installs items whose commands are missing (`--force` overrides) and only
unpacks the packages that `dpkg` does not report as installed, so wrappers never shadow system
libraries that are already present. `install.sh --list` reports `PRESENT=yes` both for a system
command and for a kit-owned wrapper whose recorded input fingerprint still matches; a changed
version or artifact fingerprint is installed again.

Sizes (lock files, 2026-09-25): jammy 319 packages, 739 MB (added for the Ubuntu test matrix);
noble 360 packages, 793 MB; resolute 371 packages, 812 MB. Shared
pool on the stick with all three releases, the VS Code tar.gz and Node: 1.5 GB. Largest parts: VS Code
.deb closure 335 MB, Edge 294 MB, Chrome 243 MB, build-essential 89 to 108 MB.

## Offline apt repository

- Source: `snapshot.ubuntu.com/ubuntu/20260924T000000Z`, suites `<release>`, `-updates`,
  `-security`, components `main universe`. The snapshot service serves the archive as it was at
  that time, so indexes and .deb URLs stay reproducible. Ubuntu 26.04 is `resolute`; it is
  published there with the same layout as noble (checked 2026-09-25, `dists/resolute/Release`,
  `Version: 26.04`).
- Integrity chain: `InRelease` signature checked with `gpgv` against the Ubuntu archive key
  `F6ECB3762474EDA9D21B7022871920D1991BC93C` (fetched from keyserver.ubuntu.com, fingerprint
  pinned in `pins.conf`); `Packages.xz` checked against the InRelease SHA256 list; every .deb
  checked against the SHA256 in the index and in `lock/<release>.lock`. Vendor repositories
  (VS Code, Chrome, Edge) are checked the same way against the Microsoft and Google signing keys.
  No key is imported into the build host's keyring (`gpg --show-keys`, `--dearmor`, `gpgv`).
- Resolver (`resolve.py`, standard library only): breadth-first walk over `Pre-Depends` and
  `Depends` (not `Recommends`), highest version across the three suites, alternatives take the
  first satisfiable one and prefer packages already chosen, virtual packages resolve through
  `Provides` (for example Chrome's `libasound2` to `libasound2t64`). The closure goes down to
  `libc6`, so apt on the laptop can fill any gap. Debian version comparison follows dpkg's
  `verrevcmp`; unit tests in `tests/test_resolve.py`.
- Reproducibility check: `fetch.sh` re-resolves on every run and fails when the result differs
  from the committed lock file; only `--relock` rewrites it. A second run on 2026-09-25 produced
  identical lock files.
- Layout: `offline/prereqs/apt/pool/...` shared by both releases, `dists/<release>/Release` and
  `dists/<release>/main/binary-amd64/Packages`.
- Install: `apt-get` runs with a private source list, lists directory and cache
  (`Dir::Etc::SourceList`, `Dir::State::Lists`, `Dir::Cache`), `[trusted=yes]` for the local repo,
  no Recommends. System sources and lists are not touched. The .deb hashes are checked again
  before apt starts.
- Known limit: when an installed package on the laptop is newer than the snapshot and a requested
  package pins an exact older version (for example `curl` and `libcurl4t64`), apt refuses the
  downgrade. The no-sudo path still works in that case; a relock with a newer snapshot fixes it.
- Chrome keeps only the current build online. When `fetch.sh` reports the pinned version as
  missing, update the version in `pins.conf` and relock. The VS Code, Chrome and Edge packages
  add their vendor's online apt source during installation (vendor postinst); IT may want to
  remove it.

## Build hook

`build/build-offline.sh` is not edited by this module. The step to add is documented at the top of
`kit/modules/01-prereqs/fetch.sh` (`step_prereqs`, plus `prereqs` in the default `ONLY` list and in
the manifest merge).

## Audit: tools every module assumes

Method: review of every install.sh, uninstall.sh, helper script, bin/ script, Python code,
TypeScript extension code and generated wrapper in `kit/` on 2026-09-25, plus 70-workbench from
the parallel branch. "Base" means part of every Ubuntu 24.04 installation (grep, sed, awk, find,
tar, gzip, xz, diffutils, procps, perl-base, dpkg, systemd). Build-host-only tools are left out.

| Module | Assumed tool | When | Without it | Provided by |
|---|---|---|---|---|
| kit/install | python3 | install | fails with message | 01-prereqs python3 (missing fallback, see fixes) |
| kit/install | whiptail or dialog | install | plain prompts | 01-prereqs whiptail |
| 00-python | tar, gzip, find, cmp, awk | install | - | base |
| 00-python | uv | install | - | own copy |
| 10-base-tools | rg fd jq fzf just direnv gitleaks yq delta | runtime | - | own copy |
| 10-base-tools | apt-get, sudo, network (apt.sh: git tmux build-essential unzip zip shellcheck) | optional | fails | 01-prereqs (offline, see fixes) |
| 11-legacy-toolbox | none (prebuilt parsers in offline/legacy-toolbox/lib) | - | cc only for grammars without a prebuilt parser | done: prebuilt parsers |
| 11-legacy-toolbox | python3 (kit-depgraph shebang) | runtime | fails | 01-prereqs python3 |
| 11-legacy-toolbox | git | runtime | falls back to a directory walk | 01-prereqs git |
| 11-legacy-toolbox | semgrep, ctags, scc, tree-sitter | runtime | - | own copy |
| 12-docs-tools | d2, pandoc | runtime | - | own copy |
| 12-docs-tools | dot (graphviz) | runtime | log note | 01-prereqs graphviz |
| 12-docs-tools | TeX or Typst for PDF | runtime | pandoc PDF output unavailable | missing |
| 20-brain | git | install and runtime | no versioning, doctor warns | 01-prereqs git |
| 20-brain | uv, CPython | install | fails with message | 00-python |
| 30-agent-setup | python3 (install.sh, kit-sync) | install and runtime | fails with message | 01-prereqs python3 (SPEC fallback to kit CPython missing) |
| 30-agent-setup | matplotlib (dataviz skill template) | skill use | template fails | missing |
| 31-caveman | python3 | install and runtime | fails with message | 01-prereqs python3 |
| 31-caveman | node | runtime (hook) | awk version, level "full" only | 01-prereqs node |
| 40-data-guard | git | runtime | staged checks and hook install fail with message | 01-prereqs git |
| 40-data-guard | gitleaks | runtime | warns, scan skipped | 10-base-tools |
| 50-eval | uv, CPython | install | fails with message | 00-python |
| 50-eval | claude, codex, ollama (user suites) | runtime | provider fails | 16-harness-clis / 15-local-llm |
| 60-terminal | git (kit-new) | runtime | fails without message | 01-prereqs git |
| 60-terminal | tmux (tmux.conf) | runtime | config inert | 01-prereqs tmux |
| 60-terminal | direnv, fzf, fd, just | runtime | skipped | 10-base-tools |
| 71-delegate | tmux | runtime | fails with message | 01-prereqs tmux |
| 71-delegate | git (--worktree) | runtime | fails with message | 01-prereqs git |
| 71-delegate | harness CLIs | runtime | fails with message | 16-harness-clis |
| 72-vscode-workbench | code (VS Code >= 1.101) | install and runtime | prints manual VSIX steps | 01-prereqs vscode |
| 72-vscode-workbench | brain | runtime | feature hidden | 20-brain |
| 80-quassel | dpkg-deb or ar, systemctl, ldconfig, update-desktop-database | install | - | base |
| 80-quassel | xclip, wl-copy/paste, notify-send, curl, ydotool | runtime | - | own copy |
| 80-quassel | pw-record or parecord | runtime | notification, exit 1 | usually present on Ubuntu desktop; 01-prereqs audio |
| 80-quassel | python3 (shortcut.sh), gsettings | runtime | fails | 01-prereqs python3; gsettings base GNOME |
| 70-workbench | python3, hard-coded as `/usr/bin/python3` in hooks | runtime | fails | 01-prereqs python3 with `--sudo` only (a wrapper in ~/.local/bin does not satisfy the absolute path) |
| 70-workbench | tmux | runtime (core) | fails | 01-prereqs tmux |
| 70-workbench | git, jq | runtime | git fails; jq hooks degrade silently | 01-prereqs git, jq (jq also 10-base-tools) |
| 70-workbench | node | runtime | degrades | 01-prereqs node |
| 70-workbench | lsof | runtime | wb-code fails with message | 01-prereqs lsof |
| 70-workbench | curl | optional features | fails | 01-prereqs curl |
| 70-workbench | ssh, scp, rsync | second-machine features | fails | 01-prereqs ssh, rsync |
| 70-workbench | `/bin/zsh` (VS Code extension) | runtime | fails (ENOENT) | 01-prereqs zsh with `--sudo` only |
| 70-workbench | bc, inotifywait, timeout | runtime | degrades | bc/inotify-tools missing; timeout base |
| 70-workbench | check-resources, wb-ssh-worker, msmtp, macOS-only tools | runtime | fails | missing |

Not needed by any module: sqlite3 CLI (brain uses Python's sqlite3), ffmpeg, sox, arecord, xsel,
entr, expect, docker. sqlite3 is still offered as an optional item; ffmpeg was dropped (145 MB
closure, no user).

## Fixes other modules need

Owners of these paths decide; 01-prereqs does not edit them.

1. `kit/install`: when `python3` is missing, fall back to the kit CPython
   that 00-python installs (`uv python find 3.12`) or tell the user to run
   `bash modules/01-prereqs/install.sh python3` first. `kit/README.md` step 1 should say that.
2. `30-agent-setup` (kit-sync, install.sh), `31-caveman`, `11-legacy-toolbox` kit-depgraph and
   `80-quassel` shortcut.sh: SPEC asks for a fallback to the kit CPython when `python3` is missing.
3. `10-base-tools/apt.sh` and `12-docs-tools/apt.sh` use online apt. Point them to
   `01-prereqs/install.sh --sudo <item>` (offline) or drop them.
4. `60-terminal` kit-new: check for git and name 01-prereqs in the error.
5. `71-delegate`: the "tmux not found" message should name `01-prereqs/install.sh tmux`.
6. `70-workbench`: replace `/usr/bin/python3` with `python3` from PATH (or the kit CPython);
   replace `/bin/zsh -lc` in the extension with `bash -lc`; replace `gtimeout`; fix the
   `stat -f`/`stat -c` order in sessionstart-autoresearch.sh; add a module.conf.
7. `16-harness-clis`: reuse the Node.js from 01-prereqs (24.21.0) instead of a second copy, or
   agree on one version.
8. `build/build-offline.sh`: add the `step_prereqs` hook from `fetch.sh`.
9. 01-prereqs python3 without sudo needs `kit/offline/python` from the 00-python build step.

## Open points

- End-to-end test on Ubuntu 24.04 and 26.04 (Lima, network off) is pending: apt path with the
  private lists directory, every wrapper actually running (git over https, tmux panes, VS Code
  start with and without `--no-sandbox`, `gcc --sysroot` hello world, `dot -Tpng`).
- VS Code without sudo runs without the Chromium sandbox on Ubuntu 23.10 and newer (AppArmor
  restricts unprivileged user namespaces and `chrome-sandbox` under $HOME cannot be setuid root).
  With sudo, the .deb installs VS Code under /usr/share/code with the sandbox helper owned by root.
- Chrome and Edge .deb files are copied unchanged from the vendors; whether IT allows them (and
  their online update source) is an IT decision.

## Notes for users

- VS Code without sudo starts with `--no-sandbox` on Ubuntu 24.04+ (see Open points); use
  `bash install.sh --sudo vscode` where sudo is allowed.
- `build-essential` without sudo is experimental (unpacked toolchain plus a private sysroot).

## Tests

In the module folder: `bash tests/test-install.sh` and `python3 tests/test_resolve.py`.

Build host (network): `bash fetch.sh` fills `kit/offline/prereqs/`; `bash fetch.sh --verify`
checks it. New versions: edit `pins.conf` or `lock/files.lock`, run `bash fetch.sh --relock`,
review the `lock/` diff (relocking is also described under "Offline apt repository" above).
