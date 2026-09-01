---
description: Check whether you understand an applied change using the actual diff and observed behavior.
argument-hint: "[optional file, path, or concept]"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · checkpoint

Use the **tutor** skill. Focus on `$ARGUMENTS` when supplied. Inspect the actual diff and available
verification; if neither exists, ask for one and stop.

Ask one change-grounded check: preferably explain a load-bearing decision and what would break
without it; otherwise use one adaptive `AskUserQuestion` with plausible misconceptions. Do not ask
trivia or modify files. Correct a misconception briefly, then use a simpler follow-up only if needed.
