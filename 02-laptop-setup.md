# Laptop setup

- [ ] `~` = `AltGr` + `+` (German keyboard); `$HOME` works the same

## 1. Ask IT
- [ ] `sudo` and installing software allowed?
- [ ] Is this work kit and its fetched software allowed?
- [ ] Which AI tools are approved? Customer code in cloud AI allowed?
- [ ] Access: VPN, Git, tickets, time tracking, Teams, Outlook
- [ ] Where do files and backups live?
- [ ] Which IDE and languages does the team use?

## 2. Security
- [ ] Change initial password
- [ ] MFA with Microsoft Authenticator
- [ ] Screen lock: Settings > Privacy > Screen Lock, 5 min
- [ ] Confirm full-disk encryption with your company's IT

## 3. Microsoft
- [ ] Open the browser that is already installed (Ubuntu: Firefox); Teams and Outlook run in it
- [ ] Teams needs Edge or Chrome? Ask IT to install one (the kit does not provide them without sudo)
- [ ] Teams in the browser: sign in, install as app if the browser offers it
- [ ] Test headset, camera, screen sharing
- [ ] Outlook in the browser

## 4. Work kit
- [ ] Open a terminal: `Ctrl+Alt+T`
- [ ] Get the repo: `git clone https://github.com/Skryx-L-A/work-kit ~/work-kit`
- [ ] If Git is missing: use GitHub **Download ZIP**, then unpack it to `~/work-kit`
- [ ] Check the laptop: `bash ~/work-kit/setup/check.sh`; confirm "Encrypted: yes", and ask IT about other odd lines
- [ ] Fetch the offline files: `bash ~/work-kit/setup/fetch-offline.sh` (about 15 GB; resumes and checks SHA-256)
- [ ] Install: `bash ~/work-kit/setup/install-kit.sh`
- [ ] It copies the kit with a progress bar, checks it, then opens the menu
- [ ] Menu screen 1 lists the modules (unchecked ones need IT approval first; keep 30, 35 and 60 checked; 16 (AI CLIs) and 80 (dictation) start unticked: tick them if IT approved); screen 2 "Orchestration": pick 70, 71 or 72
- [ ] Then it asks how AI tools may act: Enter = bypass (agents run commands without asking), 2 = ask
- [ ] The install takes 30-60 minutes; one line per module is normal, a long module adds "still running (N min)" every minute (details: cancel, run `~/work/kit/install -v`)
- [ ] With 95-desktop it asks to log out: yes only with nothing open; after login `Super+K` shows the keys
- [ ] Open a new terminal when it is done
- [ ] Optional, if IT gives you a proxy or a root certificate: `kit-net proxy set http://host:port` / `kit-net ca add root.crt`, then `kit-net test https://pypi.org/`
- [ ] Failed items: fix the cause, run `~/work/kit/install` again (it shows only what is left)

## 5. AI tools (only what IT approved; module 16 ticked)
- [ ] Open a new terminal, then sign in, the first time only:
  - Claude Code: `claude`, follow the login in the browser
  - Codex: `codex login`
  - opencode: `opencode auth login`
  - Copilot CLI: `copilot`, then `/login`
  - Gemini CLI: `gemini`, choose the sign-in
  - pi: `pi`, then `/login`
- [ ] Company endpoint from IT instead of a vendor login: `kit-models add`, then `kit-models test <name>`
- [ ] Agent Workbench (module 70): "Agent Workbench" from the app menu, or `wb-code ~/work/<project>` in a terminal
- [ ] Dictation (module 80 ticked): the install binds `Ctrl+Alt+D` on GNOME (run `bash ~/work/kit/modules/80-quassel/shortcut.sh` if it did not: over ssh or outside the desktop session). Press it, speak, press it again, then paste with `Ctrl+V`. "Hold Ctrl+Meta" needs IT's root steps and stays off without them

## 6. Development
- [ ] `bash ~/work-kit/setup/git-setup.sh` (git and ssh come with the kit)
- [ ] `ssh-keygen: command not found`? `bash ~/work/kit/modules/01-prereqs/install.sh ssh`, then run git-setup again
- [ ] It asks for a passphrase for the SSH key: type one, or leave it empty
- [ ] Add the printed public key to the company Git server
- [ ] IDE as the team uses it
- [ ] Brain backup folder: the one IT named in step 1; `brain backup <folder>` steps in `04-daily.md` (Backup)

## Remove
- [ ] `~/work/kit/install --uninstall all`, and the rest in `04-daily.md` (Remove / offboarding)

## Never on this laptop
Private accounts and private files. Keep company data on approved company systems.
