---
description: Check whether you understand an applied change using the actual diff and observed behavior.
argument-hint: "[optional file, path, or concept]"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · checkpoint

Use the **tutor** skill's comprehension rules. The optional focus is: `$ARGUMENTS`

Inspect the actual diff, relevant surrounding code, and any verification result the developer has
shared. Fetch or search a user-supplied specification when needed to ground the checkpoint. If there
is no applied change or pasted diff, ask for one; do not quiz imagined code.

Run two checks in order:

1. Ask the developer to explain one load-bearing line or decision in their own words and predict
   what would break if it changed or disappeared.
2. After their explanation, compose one adaptive `AskUserQuestion` checkpoint with 2–4 shuffled
   options based on the real change and a plausible misconception.

Do not ask trivia or recite syntax. Confirm correct reasoning with one useful nuance. Correct a wrong
answer by connecting the misconception to the code, then ask a simpler follow-up. Never modify the
repository during the checkpoint.
