---
name: dependency-upgrade
description: Upgrade libraries, frameworks, runtimes or database versions in small verified steps, using release notes, SemVer signals and the project's tests, with a rollback path. Use for security patches, end-of-life runtimes or frameworks, major framework migrations (for example .NET Framework to .NET, Java 8 to 21, Python 2 to 3, AngularJS to Angular) and routine update batches. Do not use to choose a new technology for a system (use modernization-assessment), and do not upgrade in a shared or customer environment without the owner's approval.
---

# Dependency Upgrade

An upgrade is a behavior change you did not write. Treat it like one: read what changed,
move in small steps, and prove the system still does what it did.

## Before you start

- Know the reason: security fix (which advisory), end of life (which date), needed feature,
  or routine hygiene. The reason sets the urgency and how far to go.
- Inventory current versions: manifest and lock files, vendored binaries, runtime and
  database versions in each environment (development, test, production may differ).
- Check the safety net. If the affected area has no tests, write `characterization-tests`
  first for the behavior the upgrade can touch.
- Search earlier upgrade notes: `brain search "<library> upgrade"`. If `brain` is missing,
  check the repository history: `git log --oneline -- <manifest file>`.
- Offline work: the kit installs offline. Package registries and advisories may still be
  reachable at work; if not, note which checks could not be done.

## Procedure

1. **Read before changing.** For each package: release notes and changelog between current
   and target version, migration guide, deprecations, and new minimum runtime requirements.
   Under SemVer, a major version signals breaking changes; minor and patch should not break,
   but projects do not always follow SemVer, so read the notes anyway.
2. **Plan the path.** Order: runtime or toolchain constraints first, then frameworks, then
   libraries. For large jumps, go through intermediate major versions if the migration guides
   assume it. Keep lock files; upgrade one package or one coupled group per step.
3. **Branch and change one step.** Update the manifest, regenerate the lock file with the
   ecosystem's tool (`npm install`, `uv lock`, `mvn versions:use-dep-version`,
   `dotnet add package`, and so on). Do not edit lock files by hand.
4. **Fix the fallout.** Compile or type-check, then run the tests. Resolve deprecation
   warnings that the next version will turn into errors. Keep code changes for the upgrade
   separate from unrelated cleanup.
5. **Check transitive effects.** Diff the lock file: which transitive packages changed,
   were added or removed? Check licenses of new packages against the project's policy.
   Run the security audit tool of the ecosystem if available.
6. **Verify behavior.** Full test suite, characterization tests, a smoke test of the main
   flows, and anything the release notes flagged (serialization, date handling, default
   configuration, SQL dialect, encoding). Compare performance if the notes mention it.
7. **Commit per step** with the versions in the message, for example
   `Upgrade Newtonsoft.Json 9.0.1 to 13.0.3`. Include what was changed to adapt.
8. **Rollout and rollback.** Describe how to deploy and how to revert (previous lock file,
   database compatibility). For database or runtime upgrades, confirm backups and a tested
   restore before the change in any shared environment.
9. **Record** notable breaking changes and workarounds:
   `brain new note "<package> <from> to <to>: upgrade notes" --project <slug> --body -`
   (or in the pull request description if `brain` is missing).

## Done when

- The target versions are in the manifest and lock file, and the build is clean.
- Full tests and characterization tests pass on the final commit; results are recorded.
- Release-note risks were checked individually, with results.
- Transitive changes, licenses and audit results were reviewed.
- Each step is a separate commit, and a rollback path is written down.

## Pitfalls

- Upgrading everything at once. When something breaks, nobody knows which package caused it.
- Trusting SemVer blindly; minor versions sometimes change defaults or behavior.
- Updating only the manifest while the lock file or vendored copy still pins the old version.
- Different versions in development and production because of manual installs on servers.
- Silencing deprecation warnings instead of fixing them.
- Assuming an AI assistant knows the current API of the new version. Check the official docs
  for that exact version.
- Upgrading a database or runtime in a shared environment without a verified backup.

## Related skills

`characterization-tests`, `security-review`, `verification`, `modernization-assessment`,
`git-workflow`. Sources: references/sources.md.
