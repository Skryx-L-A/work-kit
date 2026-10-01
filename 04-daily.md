# Daily use (days 2 to 10)

- Start: open a terminal, `brain recent -n 10`, then start the approved AI tool in the repository.
- Brain: `brain search "<question>" -k 5`, `brain new note "<title>"`, `brain log "<task>" --hours 1.5`, Friday `brain week`.
- New repository: `kit-new <name>` (in `~/work`). Existing clone: `kit-sync --project <path>` and `data-guard install-hook <path>`.
- Logs: `~/.local/share/work-kit/install-logs/<module>.log`. State: `~/work/kit/install --status`.
- Backup (folder IT approved in `02-laptop-setup.md` step 1, never a private account):
  1. Daily, after `brain log`: `brain backup <folder>`
  2. Friday, restore check: `brain doctor`, then `git bundle verify <folder>/brain-<date>.bundle`
  3. Lost laptop: `git clone <folder>/brain-<date>.bundle ~/work/brain`
- Something broken:
  - `~/work/kit/install` (retries failed modules; `--all` shows installed ones too)
  - one module: `bash ~/work/kit/modules/<module>/uninstall.sh`, then `install.sh` in the same folder
  - desktop: dock still there after a login: `kit-desk finish-login` (log: `kit-desk status`); undo: `bash ~/work/kit/modules/95-desktop/uninstall.sh` (`--full-restore` loads the saved dconf dump), log out and in
- Kit update: `git -C ~/work-kit pull --ff-only` (or replace the downloaded ZIP), then run `bash ~/work-kit/setup/fetch-offline.sh` and `bash ~/work-kit/setup/install-kit.sh`. The menu preselects modules marked "UPDATE:".
- AI tool updates when network is allowed: `~/work/kit/modules/16-harness-clis/README.md`.
- Remove / offboarding:
  1. Hand over or delete, as IT says: `~/work/brain` (notes, `worklog/`), `~/work/meetings` (transcripts), `~/work/doc-qa`, your repositories in `~/work`.
  2. Sign out of every AI tool you used: `claude` then `/logout`; `codex logout`; `opencode auth logout`; `copilot` then `/logout`. Gemini, pi: no command, deleted in step 6.
  3. Company endpoints and keys: `kit-models list`, then `kit-models remove <name>` for each.
  4. `~/work/kit/install --uninstall all` (asks first; reverse order, includes `kit-sync --uninstall`). It runs plain `uninstall.sh`; for the data of 33, 50, 80 also `bash ~/work/kit/modules/<module>/uninstall.sh --purge`.
  5. If root steps of 80 were run: `sudo bash ~/work/kit/modules/80-quassel/root-steps.sh --undo`.
  6. Leftovers (logins, configs, workbench state): list, hand over as IT says: `ls -d ~/.claude ~/.codex ~/.gemini ~/.copilot ~/.pi ~/.config/opencode ~/.local/share/opencode ~/.aider* ~/.pi-workers`
  7. Then delete: `rm -rf ~/.claude ~/.codex ~/.gemini ~/.copilot ~/.pi ~/.config/opencode ~/.local/share/opencode ~/.aider* ~/.pi-workers`
  8. `rm -rf ~/work/kit ~/.local/share/work-kit ~/.config/work-kit`.
  9. Log out of the company Git server and remove the laptop's SSH key there; then `rm -f ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub`.
