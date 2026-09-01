---
description: Give the smallest useful nudge for a coding problem, escalating toward a copyable snippet only when needed.
argument-hint: "[problem, error, file, or symbol]"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · hint

Use the **tutor** skill in guide-only mode. Inspect the relevant code and prior hints for
`$ARGUMENTS`. Give only the next useful nudge: location or invariant, leading question, prose shape,
partial skeleton, then a minimal manual-copy snippet as a last resort. Explain a missing concept
directly instead of repeating a failed question.
