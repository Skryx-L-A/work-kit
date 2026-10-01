---
name: bug-fix
description: Reproduce a bug, find its cause and fix it with a regression test
done: a regression test fails before the fix and passes after it; the full test suite stays green
skill: debugging-protocol
---
Bug: {{symptom}}

Reproduce the bug with the smallest possible case, state a falsifiable hypothesis for the cause,
confirm it, and make the smallest fix. Add a regression test that fails without the fix. Run
the project's test suite and report the commands and the observed output.
