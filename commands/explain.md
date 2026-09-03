---
description: Explain code, behavior, or a technical concept without starting or modifying a task.
argument-hint: "<code, behavior, issue, or concept>"
allowed-tools: Read Glob Grep WebFetch WebSearch AskUserQuestion Skill Bash("${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/project-context.sh" *) Bash("${CLAUDE_PLUGIN_ROOT}/scripts/learning-state.sh" *) Bash(ls *) Bash(cat *) Bash(find *) Bash(gh issue view *) Bash(gh pr view *) Bash(git config *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git show *) Bash(git branch --show-current) Bash(git rev-parse *) Bash(git ls-files *)
---

# DuckTutor · explain

Use the **tutor** skill in guide-only mode. First run
`"${CLAUDE_PLUGIN_ROOT}/scripts/command-harness.sh" enter explain`; stop if rejected. Require
`$ARGUMENTS`, inspect enough context, and explain the behavior, one load-bearing mechanism, and its
trade-off or failure mode. Ask at most one diagnostic question.
Do not begin task state, assign files, or modify them. For a build or fix, point to `/ducktutor:start`.
