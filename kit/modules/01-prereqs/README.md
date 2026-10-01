# 01-prereqs

Base tools from the fetched offline files: VS Code, git, tmux, curl, python3, whiptail, ssh (default; needed
by `~/work-kit/setup/git-setup.sh`, skipped when `ssh-keygen` is already there) and
optional jq, sqlite3, zip/unzip, rsync, clipboard, audio, lsof, graphviz, zsh, node,
build-essential, make, Chrome, Edge. Ubuntu 22.04 (jammy), 24.04 (noble), 26.04 (resolute), x86_64.
Depends on nothing. Run it first; `kit/install` itself needs python3.

```sh
cd ~/work/kit/modules/01-prereqs && bash install.sh     # defaults, no sudo
bash install.sh --list                                  # items, defaults, what is already present
bash install.sh git tmux node                           # chosen items; `all` = every item
bash uninstall.sh
```

Open a new terminal.

Optional, needs sudo (apt from the fetched offline repository):

```sh
bash install.sh --sudo              # apt items
bash install.sh --sudo chrome       # sudo only: chrome, edge, zsh
bash uninstall.sh --sudo            # also runs apt-get remove for apt items
```

Notes, build host and tests: `~/work/kit/docs/prereqs.md`.
