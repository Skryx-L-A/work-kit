# 40-data-guard

Blocks secrets and company-specific strings in commits; holds the data-class policy. CLI `data-guard`.
Offline, no sudo. Needs `git` and `gitleaks` (from 10-base-tools). Without gitleaks commits are blocked
(fails closed); one commit only: `DATA_GUARD_ALLOW_UNSCANNED=1 git commit ...`.

```sh
cd ~/work/kit/modules/40-data-guard && bash install.sh     # CLI + policy; per-repo hooks
bash uninstall.sh
```

Open a new terminal.

Optional, guard every repository: `bash install.sh --global-hooks` (opt in), or per repository:
`data-guard install-hook ~/work/my-repo`.

```sh
data-guard check notes.md               # scan text before sending it anywhere
data-guard deny add 'customer-name'
data-guard deny remove 'customer-name'
data-guard status                       # also lists registered repositories, flags gone paths
data-guard prune                        # forget registered repositories whose path no longer exists
```

AWS access key ids are caught; the documented example id (ends in `EXAMPLE`) is ignored by gitleaks' default rule on purpose.

Then edit `~/.config/work-kit/data-classes.md` (`TODO(ask IT)` items) and
`~/.config/work-kit/deny-patterns.txt`.

Hook mechanics and tests: `~/work/kit/docs/data-guard.md`.
