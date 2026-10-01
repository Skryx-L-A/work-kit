# 71-delegate

Skill `delegate` + script `agent-spawn`: start workers (any CLI harness) in tmux panes with a
task file, collect their result files. Needs `tmux`; `git` for `--worktree`
(`01-prereqs/install.sh tmux git`). No sudo.

```sh
cd ~/work/kit/modules/71-delegate && bash install.sh    # agent-spawn -> ~/.local/bin, skill -> ~/.agents/skills
bash uninstall.sh
```

Open a new terminal.

```sh
cd ~/work/my-project                    # an existing Git repository (needed by --worktree)
agent-spawn template > task.md          # fill in: goal, exclusive paths, done criterion, limits
agent-spawn start w1 --harness claude --task task.md --worktree
agent-spawn list
agent-spawn result w1 --wait 1800
agent-spawn stop w1 --remove-worktree
```

Harnesses: `agent-spawn harnesses`. Add or change one in `~/.config/work-kit/harnesses.conf`
(example: `harnesses.conf.example`). Tests: `~/work/kit/docs/delegate.md`.
