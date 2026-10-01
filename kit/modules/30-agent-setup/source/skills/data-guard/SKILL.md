---
name: data-guard
description: Classify data before it goes anywhere (AI model, chat, ticket, commit, log, note) and respect, check and extend the kit's data guard (data classes, gitleaks pre-commit hook, deny-list). Use before pasting code, logs, documents or database content into any AI tool or external service, before committing, when adding customer names or internal hosts to the deny-list, and when a commit hook blocks. Do not use as legal advice or to decide company policy; unclear cases go to the responsible person, and until IT has confirmed the rules the strictest reading applies.
---

# Data Guard

Every piece of data has a class, and the class decides where it may go. The Work kit-specific
rules are not confirmed yet: `data-classes.md` in the data-guard module contains placeholders
marked `TODO(ask IT)`. Until they are replaced, use the default table below. When unsure,
treat data as the stricter class and ask.

## Default classes (strictest reading, until IT confirms)

| Class | Examples | Allowed AI destinations (default) |
|---|---|---|
| PUBLIC | published docs, open-source code, public websites | any approved tool |
| INTERNAL | internal processes, non-sensitive internal code, meeting notes without personal data | only tools IT has approved for internal data; otherwise local models only |
| CONFIDENTIAL | offers, prices, contracts, security findings, credentials, architecture of company systems, personal data of colleagues | local models only, and only if needed; never cloud AI without written approval |
| CUSTOMER | customer source code, customer databases and logs, customer documents, anything under an NDA | no AI tool, local or cloud, unless the customer contract and IT explicitly allow it |

Secrets (passwords, keys, tokens, connection strings) never go to any AI tool, chat, ticket,
log or commit, whatever the class of the surrounding material.

Read the current version before relying on this table: `data-classes.md` in the kit's
`40-data-guard` module (on the laptop usually `~/work/kit/modules/40-data-guard/`). If that
module is not installed, the table above applies and the checks below are done by hand.

## Procedure before sending data somewhere

1. **Identify the destination.** Which tool, model and provider; cloud or local; is it on
   the company's approved list? Unknown means not approved.
2. **Classify the material.** Take the highest class of anything in it. Customer code with
   a public library inside is CUSTOMER. Logs often contain personal data and host names.
3. **Check the match** against `data-classes.md` (or the default table). If not allowed:
   - reduce: send only the minimal snippet needed;
   - replace: use synthetic data or a self-written minimal reproduction;
   - redact: remove names, IDs, hosts, amounts; keep structure;
   - or switch to an allowed destination (for example a local model).
   If none works, do not send it; ask the responsible person.
4. **Record exceptions.** If someone approved a use that the table does not cover, note who,
   when and what exactly (`brain new note` with project, or the ticket), without the data.

## Procedure before committing

1. Check that the hook is active: `git config --get core.hooksPath` (global opt-in) or
   `.git/hooks/pre-commit` exists in the repository. If neither, install per repository with
   the command in the data-guard module README, or ask whether the global hook should be enabled.
2. Without the hook, scan manually: `gitleaks git --pre-commit --staged --redact .`
   (gitleaks older than 8.19: `gitleaks protect --staged --redact`). If `gitleaks` is not
   installed either, review `git diff --staged` by hand for secrets, customer names,
   internal host names and file paths, and say in your report that no scanner ran.
3. If the hook blocks: read the finding (file, line, rule), remove the data from the change
   and from any earlier unpushed commit. Do not bypass with `--no-verify`. A real false
   positive gets an allow-list entry in the gitleaks config with a comment, reviewed by
   a second person.
4. If a secret was already pushed or shared: treat it as compromised. Tell the owner so it
   can be rotated; removing it from history alone is not enough.

## Extending the deny-list

- File: `~/.config/work-kit/deny-patterns.txt`, one pattern per line (see the module
  README for syntax). It stays local and is never committed to a shared repository.
- Add customer names, project code names, internal host names and domains, network paths.
- Test a new pattern against a staged dummy file before relying on it, then remove the dummy.

## Done when

- Every item sent to an AI tool or external service had a class and an allowed destination.
- Commits were scanned by the hook, by gitleaks, or by a stated manual review.
- Blocked findings were fixed, not bypassed; exceptions are documented without the data.

## Pitfalls

- Assuming "internal tool" means "allowed". Check the approved list and the provider.
- Pasting a whole log or file when ten lines would do.
- Screenshots and PDFs carry the same data as text.
- Treating the placeholders in `data-classes.md` as confirmed rules.
- Committing the deny-list itself: it contains exactly the names it protects.
- AI tool memories, chat histories and uploaded files may be retained by the provider.

## Related skills

`security-review`, `git-workflow`, `code-review`, `debugging-protocol`.
Sources: references/sources.md.
