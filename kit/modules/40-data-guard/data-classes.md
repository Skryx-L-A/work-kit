# Data classes

Which data may go to which AI destination. **The company-specific values are not known
yet.** Everything marked `TODO(ask IT)` is a placeholder; until IT confirms it, use the
stricter reading. When unsure about a class or a destination: stop and ask.

Copy this file to `~/.config/work-kit/data-classes.md`, fill in the TODOs, and keep
it there. Agents read that copy.

## Classes

| Class | What it is | Examples |
|---|---|---|
| PUBLIC | Already public or meant to be public | published web pages, open-source code, public documentation, marketing texts |
| INTERNAL | Company-internal, not about a customer | internal wiki pages, process descriptions, non-customer source code, meeting notes without customer content. `TODO(ask IT)`: confirm the list |
| CONFIDENTIAL | Business-sensitive or personal | contracts, prices, financials, HR data, personal data of staff, credentials, keys, tokens, security findings. `TODO(ask IT)`: confirm the list |
| CUSTOMER | Belongs to or describes a customer | customer source code, databases, logs, tickets, documents, names, system landscapes, anything covered by a customer contract or NDA |

A mix takes the strictest class of its parts. Anonymizing or synthesizing data lowers the
class only if nobody can trace it back: replace names, hosts, ids and numbers, not just
the company name.

## Destinations

Only approved AI services are used for company work, for every data class: the approved list
in the AI usage guideline (13-ai-governance, section 4) decides, and unknown means not approved.
Approval of a service is not approval of a class; the cell below decides that. Personal and
consumer accounts are never used, not even for PUBLIC data.

Default per cell is the strict reading. `ask` means: get a written yes from the responsible
person first (team lead, data protection officer, or the customer contract owner).

| Destination | PUBLIC | INTERNAL | CONFIDENTIAL | CUSTOMER |
|---|---|---|---|---|
| Local model or tool on the laptop, no network use | yes | yes | ask | ask |
| Company-approved AI tool under a company contract. `TODO(ask IT)`: which tools, which data processing terms | yes | ask | no | no |
| Any AI service that is not on the approved list: consumer chat, free tier, browser extension, personal account (never, for any class, PUBLIC included) | no | no | no | no |
| Web search, online translators, online formatters (queries are data too) | yes | no | no | no |
| Git hosting, ticket systems, chat. `TODO(ask IT)`: which are approved for what | yes | ask | no | no |

## Rules

1. Classify before you send. Classify the whole input: attachments, pasted logs, file
   names, hostnames and screenshots count.
2. Do not add a new AI service, plugin, model provider or API key on your own. Ask IT.
3. Use synthetic or anonymized data for examples, tests, prompts and demos.
4. Never put secrets into prompts, notes, commits or tickets. `data-guard` blocks commits
   that contain them; it does not replace judgement.
5. Every AI output that reaches a customer or informs a decision is reviewed by a human.
6. Report a leak at once, even if you are not sure. Rotate leaked secrets.
7. The customer's contract wins over this table when it is stricter.

## Open questions for IT

- [ ] Which AI tools and models are approved, for which classes? (`TODO(ask IT)`)
- [ ] Is a local model allowed for CONFIDENTIAL and CUSTOMER data? (`TODO(ask IT)`)
- [ ] May the work knowledge base (`~/work/brain`) have a remote, and where? (`TODO(ask IT)`)
- [ ] Which git hosts and ticket systems are approved? (`TODO(ask IT)`)
- [ ] Customer names and internal hostnames to put into the deny-list. (`TODO(ask IT)`)
- [ ] Who decides a doubtful case? Name and contact. (`TODO(ask IT)`)
