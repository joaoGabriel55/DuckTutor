---
description: Check whether you understand an applied change using the actual diff and observed behavior.
argument-hint: "[optional file, path, or concept]"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash("${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" *) Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · checkpoint

Use the **tutor** skill. Read persisted state and inspect the actual diff and verification. Require
the developer to explain one load-bearing decision and failure mode in their own words. Correct a
misconception with a simpler follow-up. An adaptive quiz may reinforce this answer but cannot replace
it. Only after a satisfactory open-ended explanation, request approval for
`phase explained developer-confirmed`. Never modify files.
