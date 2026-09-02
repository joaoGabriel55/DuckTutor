---
description: Build a grounded mental model of this project or a selected subsystem, then check your understanding.
argument-hint: "[optional topic or subsystem]"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash("${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" *) Bash(ls *) Bash(cat *) Bash(find *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git remote *) Bash(git ls-files *)
---

# DuckTutor · teach-me

Use the **tutor** skill in guide-only mode. Read active learning state and inspect the repository,
focusing on `$ARGUMENTS`. Explain purpose, key modules, important flow, and relevant conventions.
For a concrete change, begin persistent state; for orientation, do not create state. Distinguish facts
from gaps. End with up to three places to inspect next and, when useful, one diagnostic question.
