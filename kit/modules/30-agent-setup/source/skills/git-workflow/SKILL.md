---
name: git-workflow
description: 'Work with git safely in shared and customer repositories: branch per task, small focused commits with clear English messages, clean history before review, sync without losing others'' work, and recover from mistakes. Use when starting a task in a repository, committing, preparing a pull request, rebasing or merging, resolving conflicts, or undoing something. Do not use to decide a team''s branching model or release process (follow the repository''s documented rules), and never force-push, rewrite shared history or push to a protected branch without the owner''s explicit approval.'
---

# Git Workflow

Project rules win: read `CONTRIBUTING`, `AGENTS.md`, the pull request template and the
branch protection settings first. This skill is the default when a repository says nothing.

## Start of a task

1. `git status` and `git fetch`. Know the default branch (`git remote show origin` or ask).
   If the working tree has changes you did not make, stop and ask; do not stash or discard them.
2. Create a branch from the current default branch:
   `git switch -c <type>/<ticket>-<short-name> origin/main` (for example
   `fix/INV-231-negative-rounding`). Use the naming scheme of the repository if it has one.
3. Confirm the commit identity: `git config user.name` and `git config user.email` are your
   work identity for this repository.

## Committing

- One logical change per commit: a refactoring, a behavior change and a formatting run are
  three commits. This keeps review and `git bisect` useful.
- Stage deliberately: `git add -p` or explicit paths. Never `git add -A` blindly in a legacy
  repository with build output, local config or data files lying around.
- Before each commit: `git diff --staged`. Check for secrets, customer data, debug code and
  unrelated files. The data-guard pre-commit hook runs gitleaks if installed; if the hook
  is missing, see the `data-guard` skill.
- Message in English, imperative mood, subject up to about 72 characters, body explains why:
  ```
  Fix rounding of negative invoice amounts

  Amounts below zero were truncated instead of rounded half-up, which made
  credit notes differ by one cent from the ERP export. Adds a regression test.
  Refs: INV-231
  ```
  Use Conventional Commits (`fix:`, `feat:`, `refactor:`) only if the repository does.
- Commit often locally; small safe intermediate commits are cheaper than lost work.

## Syncing and review

1. Update your branch: `git fetch` then `git rebase origin/main` for a private branch, or
   `git merge origin/main` if the branch is shared or the project prefers merges.
2. Resolve conflicts by understanding both sides. Keep others' changes unless you know they
   are wrong; ask the author if unsure. Rebuild and rerun tests after resolving.
3. Before opening a pull request: tidy your own unpushed history (squash fixups with
   `git rebase -i` if the harness allows interactive commands, otherwise
   `git commit --fixup` plus `git rebase --autosquash`), rerun tests, write a description
   with intent, changes, verification and risks (see `verification`).
4. Push your branch only: `git push -u origin <branch>`. After a rebase of an already pushed
   private branch use `git push --force-with-lease`, never plain `--force`, and never on a
   branch others use.

## Recovering

- Undo the last commit but keep the changes: `git reset --soft HEAD~1` (unpushed only).
- Revert a pushed commit: `git revert <sha>` (creates a new commit, safe for shared history).
- Find lost commits: `git reflog`, then `git branch rescue/<name> <sha>`.
- Unstage a file: `git restore --staged <path>`. Discard local edits to a file:
  `git restore <path>` (destructive; check the diff first).
- A secret reached a pushed commit: stop, tell the owner to rotate it (see `data-guard`),
  then clean history only with the repository owner's approval.

## Done when

- The branch contains only commits for this task, each with one intent and a clear message.
- The branch is up to date with the target branch, conflicts resolved, tests rerun.
- No secrets, customer data or unrelated files are in the diff.
- Nothing was force-pushed or rewritten on a shared or protected branch.

## Pitfalls

- Working directly on `main` or a release branch.
- `git add .` picking up local config, dumps or credentials.
- Rebasing a branch someone else has pulled.
- Resolving conflicts by taking "ours" everywhere and silently dropping a colleague's fix.
- Huge commits mixing reformatting with logic changes; reviewers cannot see the real change.
- Line-ending and encoding churn in legacy repositories: respect `.gitattributes` and do not
  normalize files you did not otherwise change.

## Related skills

`data-guard`, `verification`, `code-review`, `refactoring-plan`. Sources: references/sources.md.
