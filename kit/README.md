# work-kit

Offline work kit for Ubuntu 22.04/24.04/26.04 x86_64. No sudo needed (optional `--sudo` paths exist).

1. Get the repository in `~/work-kit`: `git clone https://github.com/Skryx-L-A/work-kit ~/work-kit` (or download and unpack the ZIP there).
2. Run `bash ~/work-kit/setup/fetch-offline.sh` (about 15 GB; resumes and verifies downloads).
3. Run `bash ~/work-kit/setup/install-kit.sh` (copies to `~/work/kit`, checks, opens the menu).
4. Answer the menu. Works without system python3 (uses the kit's own).
5. Open a new terminal.

Run `~/work/kit/install` again to retry failed modules or add skipped ones; installed modules are hidden
(`--all` shows them). Options: `--select 00,20,71`, `--permissions bypass|ask`, `--dry-run`, `--status`, `-v`.
Behind a company proxy or a TLS-inspecting firewall: module `35-company-network` (`kit-net proxy set <url>`, `kit-net ca add <file>`).
Missing base tools (git, tmux, curl, VS Code, Node): module `01-prereqs`. Logs and state: `~/.local/share/work-kit/`.
Every module also works alone: `bash modules/<name>/install.sh`. Details: `lib/installer/README.md`.

## Remove the kit
`~/work/kit/install --uninstall all` (asks first; `--yes` skips, `--dry-run` lists) runs every installed module's `uninstall.sh` in reverse order, including `kit-sync --uninstall`.
Single modules: `--uninstall 20,71`. Your notes (`~/work/brain`) and the folder `~/work/kit` stay; hand over or delete them by hand.
