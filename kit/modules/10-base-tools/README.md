# 10-base-tools

Static x86_64 binaries into `~/.local/bin`: `rg fd jq fzf just direnv gitleaks yq delta`.
Offline, no sudo. Needs `kit/offline/bin`. No other module needed.

```sh
cd ~/work/kit/modules/10-base-tools && bash install.sh      # all tools
bash install.sh rg fd                                       # only these
bash uninstall.sh
```

Open a new terminal.

Optional, needs sudo and the offline apt repository of 01-prereqs (git, tmux,
build-essential, zip, shellcheck):

```sh
bash apt.sh
```
