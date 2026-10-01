#!/usr/bin/env bash
# Sets up Git with the company identity and creates a new SSH key for this laptop only.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"   # git from the kit (01-prereqs) lives here
command -v git >/dev/null || { echo "git is missing: install the work kit first (module 01-prereqs), then run this again."; exit 1; }
command -v ssh-keygen >/dev/null || { echo "ssh-keygen is missing (02-laptop-setup.md in the kit source, step 6): bash ~/work/kit/modules/01-prereqs/install.sh ssh, then run this again."; exit 1; }

# Keep the identity Git already knows; otherwise ask for the full name.
cur_name="$(git config --global user.name 2>/dev/null || true)"
cur_email="$(git config --global user.email 2>/dev/null || true)"
if [[ -n "$cur_name" ]]; then
  read -rp "Your full name [$cur_name]: " name
  name="${name:-$cur_name}"
else
  read -rp "Your full name: " name
  [[ -n "$name" ]] || { echo "A name is required."; exit 1; }
fi
if [[ -n "$cur_email" ]]; then
  read -rp "Company e-mail [$cur_email]: " email
  email="${email:-$cur_email}"
else
  read -rp "Company e-mail: " email
fi
[[ "$email" == *@* ]] || { echo "Not an e-mail address."; exit 1; }

git config --global user.name "$name"
git config --global user.email "$email"
git config --global init.defaultBranch main

key="$HOME/.ssh/id_ed25519"
if [[ ! -e "$key" ]]; then
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$email" -f "$key"   # asks for a passphrase
fi

echo
echo "Public key, add it to the company Git server:"
cat "$key.pub"
