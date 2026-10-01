---
name: characterization-tests
description: Pin down the current behavior of legacy code with tests before it changes
done: the new tests pass against the unchanged code and the result names every behavior they pin
skill: characterization-tests
---
Write characterization tests for {{target}}: tests that record what the code does today,
including odd behavior, without changing the code itself. Put the tests next to the existing
tests of the project, in its test framework. Run them against the unchanged code and report the
command and the observed output.
