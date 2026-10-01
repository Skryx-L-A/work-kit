# Sign-off record

Stored with the spec. A person fills it in, not an agent. Copy per spec version.

```
Spec: <title>, version <n>, file <path>, spec sha256 <hash of spec.md>
Code map commit: <sha>       Characterization tests run: <date>, result:
Validator: <name, role>      Review date:
Method: read the full spec | walked through with <who>
Open questions answered: <n> of <n>; remaining unknown items (ids):
Corrections requested (ids):  Items dropped (ids):
Decision: validated | validated with conditions | rejected
Conditions / scope limits:
Signature or reference to the approval message (ticket, mail id):
```

A `validated with conditions` decision lists which spec IDs are unlocked. Everything else stays
blocked in `migration-plan`. Record the hash with `sha256sum spec.md` so a later edit is visible.
