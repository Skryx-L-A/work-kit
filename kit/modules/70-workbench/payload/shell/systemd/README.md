# Optional systemd user units

Not enabled by the installer. Each unit runs a workbench tool on a schedule or at login.

| Unit | Runs | When |
|---|---|---|
| `wb-testsuite.service` + `.timer` | `wb-testsuite-run` (the shell test suites), status in `~/.local/state/wb-testsuite-status.txt` | weekly, Sunday 04:00 |
| `wb-hygiene.service` + `.timer` | `wb-hygiene --report`, report in `~/.local/state/wb-hygiene-report.md` | weekly, Monday 04:00 |
| `wb-traeger.service` | `wb-traeger nachsehen --vordergrund`, the carrier process of workbench tasks | at login |

Enable one (example `wb-hygiene`):

```bash
mkdir -p ~/.config/systemd/user
cp wb-hygiene.service wb-hygiene.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now wb-hygiene.timer
systemctl --user list-timers wb-hygiene.timer
```

Run once without waiting: `systemctl --user start wb-hygiene.service`.
To survive logout: `loginctl enable-linger "$USER"` (may be restricted by IT).

Disable:

```bash
systemctl --user disable --now wb-hygiene.timer
rm ~/.config/systemd/user/wb-hygiene.service ~/.config/systemd/user/wb-hygiene.timer
systemctl --user daemon-reload
```
