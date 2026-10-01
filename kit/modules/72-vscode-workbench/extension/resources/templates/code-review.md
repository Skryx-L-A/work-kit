---
name: code-review
description: Review a change or a folder for correctness, risk and missing tests
paths: review/
done: review/REVIEW.md lists every finding with file:line, severity and a suggested fix
skill: code-review
---
Review {{target}} for correctness bugs, security and data-handling risks, and missing tests.
Do not change the code under review. Write the findings to `review/REVIEW.md`, most severe
first, each with `file:line`, what goes wrong and a concrete fix. Say which parts you could not
check.
