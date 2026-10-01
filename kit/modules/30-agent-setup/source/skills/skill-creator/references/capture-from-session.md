# Capture a skill from work that already happened

Load when the user says "we did this three times now, make it a skill" or points at a
session, a checklist or a colleague's how-to as the source.

1. **Collect the evidence**: the session transcript or notes, the commands that were run,
   the result, and what went wrong on the way. Two or three real runs beat one.
2. **Separate the stable from the incidental.** Stable: the order of steps, the checks that
   caught errors, the done criterion. Incidental: file names, customer names, hostnames,
   one-time workarounds, personal paths. Only the stable part goes into the skill.
3. **Name the decisions** the agent had to make in those runs (which tool, which data
   class, when to stop and ask). Each becomes a step with its rule, or a question to ask.
4. **Turn failures into pitfalls**: every mistake from the runs becomes a pitfall with the
   better alternative. These are the most valuable lines of the skill.
5. **Generalize carefully**: replace concrete values with placeholders or with "the
   project's ..."; keep one synthetic example if it clarifies a step.
6. **Scrub**: no secrets, no customer or personal data, no internal hostnames, no
   references to one person's machine or accounts. Check the result with `data-guard`
   if installed.
7. **Write, validate and test** as in the main procedure: description with triggers and
   near misses, validator, one request that should load the skill and one that should not.
8. **Replay**: run the new skill on a fresh instance of the task (or the next real one)
   and compare with the original runs: same result, fewer detours? Fix what differed.
9. **Record the origin** in the commit message ("from three runs of X in September"), not
   in the skill body.

Done when the skill reproduces the result of the original runs on a new instance, and no
incidental detail from those runs remains in it.
