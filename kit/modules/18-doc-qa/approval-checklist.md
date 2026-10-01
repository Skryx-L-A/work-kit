# doc-qa approval checklist

Answer these with IT / data protection before setting `enabled = true`. Record the answers
(ticket or mail) and put the approver and date into `doc-qa.toml`.

1. Scope: which document collection (folder, share export, handbook) is approved? Name it.
2. Classification: which labels may enter (`allowed_labels`)? Which must never enter
   (`excluded_labels`)? What happens to documents without a label (`unlabeled`)?
3. Personal data: may the collection contain personal data? If not, which folders or file
   patterns must be excluded (`exclude`)?
4. Models: which AI models may see passages from this scope (local only, a company-approved
   cloud service, none)? `doc-qa` itself sends nothing anywhere; the harness or person that
   uses its output does.
5. Storage: is a local copy on the laptop (`home`, default `~/work/doc-qa`, a git repo) allowed?
   Is disk encryption on? How long may the copy stay?
6. Updates and revocation: who tells you when a document is withdrawn or relabelled? Run
   `doc-qa sync` after every change; it removes documents that no longer pass the gate.
7. Review: every answer built from these passages is checked by a human before it is used.
