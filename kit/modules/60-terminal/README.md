# 60-terminal

Additive bash, tmux and direnv config plus a project template. Offline, no sudo.
Needs `git` and `tmux` (`01-prereqs`); `fzf`, `fd`, `direnv`, `just` (10-base-tools) are used when present.

```sh
cd ~/work/kit/modules/60-terminal && bash install.sh    # adds a managed block to ~/.bashrc and ~/.tmux.conf
bash uninstall.sh
```

Open a new terminal.

```sh
kit-new my-prototype       # new repo in ~/work from project-template/
```

Your own additions go to `~/.config/work-kit/bashrc.local`.
`kit-new` also runs `kit-sync --project` and `data-guard install-hook` if those are installed.
Its first commit needs your git name and e-mail (`~/work-kit/setup/git-setup.sh`).
